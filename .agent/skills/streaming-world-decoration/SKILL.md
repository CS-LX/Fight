---
name: streaming-world-decoration
description: |
  沿程序化路径流式加载/卸载装饰物（建筑、植被、道具等）的完整实现指南。
  Use when users need to (1) 沿赛道/道路/河流两侧生成建筑或树木, (2) 实现无尽世界的流式加载,
  (3) 程序化城市/森林/装饰物生成, (4) 需要确定性重建（同一位置每次生成相同内容）,
  (5) 大世界节点管理（避免一次性创建数千个节点）, (6) streaming world decoration,
  (7) 用户项目中有 buildings.lua / vegetation.lua 类似的流式装饰系统需要理解或修改。
---

# 流式世界装饰系统（Streaming World Decoration）

## 核心问题

在赛道/道路长度数千米的游戏中，如果一次性为所有瓦片生成装饰物（建筑、树木、灌木），活跃节点数可能达到数千个，导致：
- GPU DrawCall 爆炸
- 内存占用过高
- 初始化耗时过长

## 解决方案：流式加载 + 确定性 LCG 重建

### 架构概览

```
┌─────────────────────────────────────────────────┐
│  Track.Update() → currentIdx 变化                │
│         ↓                                        │
│  Decoration.Update(curIdx, loopN)               │
│         ↓                                        │
│  ┌──────────────────────────────────────────┐   │
│  │  加载窗口: [curIdx - BEHIND, curIdx + AHEAD] │
│  │  窗口内 → SpawnTile(i)                      │
│  │  窗口外 → RemoveTile(i)（每 N 帧清理一次） │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### 关键常量

```lua
local STREAM_AHEAD  = 55   -- 前方 55 个瓦片（~550m 可见）
local STREAM_BEHIND = 15   -- 身后保留 15 个瓦片（防止回头时闪现）
```

**规则**: 这两个值必须与 track.lua 的 TILE_AHEAD / TILE_BEHIND 一致或略大，否则装饰物比赛道先消失。

---

## 规则 #1: 确定性 LCG 随机（Deterministic Random）

**问题**: 流式系统会反复创建和销毁同一瓦片的装饰物。如果用 `math.random()`，每次重建结果不同——玩家回头看会发现建筑变了。

**解决方案**: 使用以瓦片索引为种子的线性同余生成器（LCG）：

```lua
local lcgState = 0

local function LcgSeed(s)
    lcgState = s & 0x7FFFFFFF
end

local function LcgRand()
    lcgState = (lcgState * 1664525 + 1013904223) & 0x7FFFFFFF
    return lcgState / 0x7FFFFFFF
end

-- 每个瓦片生成前，用唯一种子初始化
local function SpawnTile(i)
    LcgSeed(i * 137 + side * 31)  -- side: -1=左 1=右
    -- 后续所有 LcgRand() 调用产生确定性序列
    local buildingType = RandInt(#BUILDING_DEFS)
    local height = RandRange(8.0, 25.0)
    ...
end
```

**关键**: `i * 137 + side * 31` 确保同一瓦片的左右两侧使用不同种子，避免镜像对称。

---

## 规则 #2: 局部坐标到世界坐标变换

**问题**: 装饰物的位置以"距路径中心线的横向偏移"和"沿路径方向的纵向偏移"描述，但场景需要世界坐标。

**解决方案**: 每个路径节点存储 midX, midZ, heading；使用旋转矩阵变换：

```lua
--- 将瓦片局部坐标 (lx, lz) 转换为世界坐标
--- @param midX number 瓦片中点世界 X
--- @param midZ number 瓦片中点世界 Z
--- @param heading number 瓦片朝向角度（度）
--- @param lx number 横向偏移（正=右侧，负=左侧）
--- @param lz number 纵向偏移（沿行进方向）
local function LocalToWorld(midX, midZ, heading, lx, lz)
    local rad = math.rad(heading)
    local wx = midX + lx * math.cos(rad) + lz * math.sin(rad)
    local wz = midZ - lx * math.sin(rad) + lz * math.cos(rad)
    return wx, wz
end
```

**注意**: UrhoX 是 Y-up 左手坐标系，sin/cos 的符号必须如上。交换符号会导致装饰物出现在赛道反方向。

---

## 规则 #3: 材质缓存（Material Cache）

**问题**: 每个建筑面可能有不同颜色，每次 Material:Clone() 加 SetShaderParameter 会分配新对象。

**解决方案**: 以参数组合为 key 缓存：

```lua
local matCache = {}

local function GetCachedMaterial(color, roughness, metallic)
    local key = string.format("%.3f_%.3f_%.3f_%.2f_%.2f",
        color[1], color[2], color[3], roughness, metallic)
    if matCache[key] then return matCache[key] end

    local mat = cache:GetResource("Material", "Materials/PBRNoTexture.xml"):Clone("")
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color[1], color[2], color[3], 1.0)))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    matCache[key] = mat
    return mat
end
```

---

## 规则 #4: 帧节流清理（Frame-Throttled Cleanup）

**问题**: 每帧扫描全部 tileRoots 寻找超出范围的瓦片会产生 O(N) 开销。

**解决方案**: 每 90 帧（约 1.5 秒）执行一次清理：

```lua
frameCount = frameCount + 1
if frameCount % 90 == 0 then
    for i in pairs(tileRoots) do
        if not InRange(i, curIdx, loopN) then
            RemoveTile(i)
        end
    end
end
```

**注意**: 加载（SpawnTile）仍然每帧执行——玩家前方不能有空白。只有卸载可以延迟。

---

## 规则 #5: tileRoots 结构与 Reset

```lua
-- tileRoots[tileIndex] = { rootNode1, rootNode2, ... }

local function RemoveTile(i)
    local roots = tileRoots[i]
    if not roots then return end
    for _, r in ipairs(roots) do
        if r then r:Remove() end
    end
    tileRoots[i] = nil
end

function M.Reset()
    for i in pairs(tileRoots) do
        RemoveTile(i)
    end
    tileRoots  = {}
    frameCount = 0
end
```

**关键**: 移除前检查 `r` 非 nil 是必须的——避免重复删除或引用已释放的 Lua userdata。

---

## 规则 #6: 动态配置支持（多关卡）

**问题**: 不同关卡可能有不同的赛道宽度，装饰物的横向偏移需要跟随变化。

```lua
-- 错误：模块加载时固定
local D_OUTER = C.TRACK_WIDTH * 0.5 + C.WALL_W * 5

-- 正确：每次生成时动态读取
local function SpawnForSide(tileIdx, xSign, node)
    local d_outer = C.TRACK_WIDTH * 0.5 + C.WALL_W * 5  -- 每次重新计算
    ...
end
```

---

## 完整模板

```lua
local C = require "config"
local S = require "state"

local M = {}

local STREAM_AHEAD  = 55
local STREAM_BEHIND = 15
local tileRoots     = {}
local frameCount    = 0
local lcgState      = 0

local function LcgSeed(s) lcgState = s & 0x7FFFFFFF end
local function LcgRand()
    lcgState = (lcgState * 1664525 + 1013904223) & 0x7FFFFFFF
    return lcgState / 0x7FFFFFFF
end

local function LocalToWorld(midX, midZ, heading, lx, lz)
    local rad = math.rad(heading)
    return midX + lx * math.cos(rad) + lz * math.sin(rad),
           midZ - lx * math.sin(rad) + lz * math.cos(rad)
end

local function SpawnTile(i)
    if tileRoots[i] then return end
    local path = S.trackPath
    if not path then return end
    local n = path[i]
    if not n or not n.midX then return end

    LcgSeed(i * 137)
    local root = S.mainScene:CreateChild("Decor_" .. i)

    -- 用 LcgRand() 生成确定性装饰物
    -- 用 LocalToWorld() 放置到世界坐标

    tileRoots[i] = { root }
end

local function RemoveTile(i)
    local roots = tileRoots[i]
    if not roots then return end
    for _, r in ipairs(roots) do
        if r then r:Remove() end
    end
    tileRoots[i] = nil
end

local function InRange(i, curIdx, loopN)
    local fwd = (i - curIdx + loopN) % loopN
    return fwd <= STREAM_AHEAD or fwd >= loopN - STREAM_BEHIND
end

function M.Update(curIdx, loopN)
    if loopN == 0 then return end
    for offset = -STREAM_BEHIND, STREAM_AHEAD do
        local i = (curIdx - 1 + offset + loopN) % loopN + 1
        if not tileRoots[i] then SpawnTile(i) end
    end
    frameCount = frameCount + 1
    if frameCount % 90 == 0 then
        for i in pairs(tileRoots) do
            if not InRange(i, curIdx, loopN) then RemoveTile(i) end
        end
    end
end

function M.Reset()
    for i in pairs(tileRoots) do RemoveTile(i) end
    tileRoots = {}
    frameCount = 0
end

return M
```

---

## 常见陷阱

| 陷阱 | 后果 | 解决 |
|------|------|------|
| 用 math.random() 代替 LCG | 回头看装饰物布局变了 | 用 LCG + 瓦片索引种子 |
| 模块顶部计算 D_OUTER | 切换关卡后偏移量不更新 | 在 SpawnForSide 内动态计算 |
| 忘记 nil 检查 | 父节点被删后 Remove 报错 | if r then r:Remove() end |
| STREAM_AHEAD < TILE_AHEAD | 装饰物比赛道先消失 | 保持 >= track 的可见窗口 |
| 每帧都做全量清理扫描 | 低端设备卡顿 | 帧节流（每 60~120 帧一次） |
| 材质不缓存 | 内存持续增长 | key-based matCache |
