---
name: closed-loop-track
description: |
  使用 ABBA 菊花弯数学模型构建精确封闭的程序化环形赛道。
  Use when users need to (1) 生成程序化封闭赛道/跑道, (2) 让赛道终点精确回到起点（零漂移）,
  (3) 在直道中加入 S 弯/菊花弯同时保证闭合, (4) 实现环形赛道的圈数检测,
  (5) 瓦片式赛道的流式可见性管理, (6) closed-loop track / stadium oval / circuit,
  (7) 用户项目中有 track.lua 类似的环形赛道需要理解或修改。
---

# 封闭环形赛道生成（Closed-Loop Procedural Track）

## 核心问题

在赛车/竞速游戏中，程序化生成赛道时需要保证终点**精确回到起点**（位置 + 朝向均为零误差）。
直觉的"对称弯道"方案（AB 对，+dh 后跟 -dh）虽然净航向为 0，但存在**侧向漂移**，
使终点与起点之间有不可接受的偏移。

## 解决方案：ABBA 菊花弯数学模型

### 数学证明

```
AB 对 (+dh×N, -dh×N):
  净航向 = 0 ✓
  侧向漂移 ≠ 0 ✗ （因为前半段偏转时走的路和后半段回正时走的路不平行）

ABBA 组 (+dh, -dh, -dh, +dh):
  弧段 1+2 从全局 heading=H 出发产生漂移 D
  弧段 3+4 从 heading=H 出发（与 1+2 完全镜像）产生漂移 -D
  总漂移 = D + (-D) = 0 ← 精确封闭 ✓
```

### 关键约束

整条赛道的**总净转向必须等于 360°**（或其整数倍）才能首尾相连：

```
总转向 = 直道净转向(0°) + 大弯1(180°) + 直道净转向(0°) + 大弯2(180°) = 360° ✓
```

## 实现模板

### 规则 1：路径定义用 segments 数组

```lua
-- 每个 segment 定义一段等曲率弧
-- tiles = 瓦片数量, dh = 每瓦片航向变化（度）
local LOOP_SEGS = {
    -- ── 直道 1（ABBA 菊花弯，净 0°，侧向漂移精确为零）──
    { tiles = 5,  dh =  0.0 },                        -- 纯直
    { tiles = 10, dh =  1.5 }, { tiles = 10, dh = -1.5 },  -- A B
    { tiles = 10, dh = -1.5 }, { tiles = 10, dh =  1.5 },  -- B A → ABBA ✓
    { tiles = 5,  dh =  0.0 },                        -- 纯直

    -- ── 大弯 1（净 +180°）──
    { tiles = 60, dh = 3.0 },   -- 60 × 3° = 180°

    -- ── 直道 2（另一组 ABBA，可与直道 1 不同参数）──
    { tiles = 5,  dh =  0.0 },
    { tiles = 9,  dh = -1.5 }, { tiles = 9, dh =  1.5 },   -- A B
    { tiles = 9,  dh =  1.5 }, { tiles = 9, dh = -1.5 },   -- B A → ABBA ✓
    { tiles = 5,  dh =  0.0 },

    -- ── 大弯 2（净 +180°）──
    { tiles = 60, dh = 3.0 },
    -- 总净转向 = 0 + 180 + 0 + 180 = 360° → 精确封闭 ✓
}
```

### 规则 2：两遍烘焙法

```lua
local function BakeLoop()
    -- 第一遍：累加 heading → 算出每个节点的世界坐标
    local cx, cz, heading = 0, 0, 0
    for _, seg in ipairs(LOOP_SEGS) do
        for _ = 1, seg.tiles do
            heading = heading + seg.dh
            local rad = math.rad(heading)
            cx = cx + math.sin(rad) * TILE_LEN
            cz = cz + math.cos(rad) * TILE_LEN
            -- 存储节点 { x=cx, z=cz, heading=heading }
        end
    end
    -- 验证封闭性：cx≈0, cz≈0, heading%360≈0

    -- 第二遍：在相邻节点中点放置瓦片（视觉居中）
    local prevX, prevZ = 0, 0
    for i = 1, N do
        local midX = (prevX + nodes[i].x) * 0.5
        local midZ = (prevZ + nodes[i].z) * 0.5
        -- 放置瓦片 at (midX, 0, midZ), rotation = heading
        prevX, prevZ = nodes[i].x, nodes[i].z
    end
end
```

### 规则 3：瓦片流式可见性

赛道可能有数百个瓦片，不能全部启用。使用滑动窗口：

> **必须用 `SetDeepEnabled`** 而非 `SetEnabled`——复合瓦片节点包含多个子节点（台阶、地面等），`SetEnabled` 只影响当前节点，子节点的渲染组件不会被隐藏。

```lua
local TILE_AHEAD  = 55   -- 前方可见瓦片数
local TILE_BEHIND = 15   -- 后方保留瓦片数

local function UpdateTileVisibility(currentIdx, totalN)
    for i = 1, totalN do
        local fwd = (i - currentIdx + totalN) % totalN
        local active = (fwd <= TILE_AHEAD) or (fwd >= totalN - TILE_BEHIND)
        tiles[i]:SetDeepEnabled(active)
    end
end
```

### 规则 4：当前位置追踪（环形索引）

```lua
-- 在 currentIdx 附近扫描，O(常数) 复杂度
local function UpdateCurrentIdx(playerX, playerZ)
    local bestDist = math.huge
    local bestIdx  = currentIdx
    for offset = -3, 20 do
        local idx = ((currentIdx - 1 + offset) % LOOP_N) + 1
        local n   = nodes[idx]
        local d2  = (playerX - n.x)^2 + (playerZ - n.z)^2
        if d2 < bestDist then
            bestDist = d2
            bestIdx  = idx
        end
    end
    currentIdx = bestIdx
end
```

### 规则 5：圈数检测

```lua
-- 当索引从末尾突然跳回开头 → 完成一圈
if bestIdx < currentIdx - SCAN_BACK and currentIdx > LOOP_N - SCAN_FRONT then
    lapCount = lapCount + 1
end
```

### 规则 6：弯道瓦片缝隙补偿

弯道处相邻瓦片外侧会产生三角形缺口，需动态计算额外长度：

```lua
local dh_rad  = math.abs(math.rad(dh))           -- 本格航向变化（弧度）
local d_outer = innerX + nSteps * stepW           -- 最外边缘到中心线距离
local extra   = d_outer * math.sin(dh_rad)        -- 每侧延伸量
local stepLen = TILE_LEN + 2 * extra              -- 补偿后长度
```

## 设计清单

创建封闭环形赛道前确认：

- [ ] 总净转向 = 360°（或 720° 8字形等）
- [ ] 直道部分用 ABBA 模式（不是 AB 对！）
- [ ] 大弯部分：tiles × dh = 180°（或所需角度）
- [ ] 瓦片放置使用"相邻节点中点"法
- [ ] 弯道瓦片长度有缝隙补偿
- [ ] 可见性窗口覆盖前方 500m+ 后方 150m+
- [ ] 圈数检测有 `lapFirstRun` 防抖（避免启动假圈数）

## 常见陷阱

| 陷阱 | 原因 | 解决 |
|------|------|------|
| 终点和起点有 5-10m 偏移 | 使用了 AB 对而非 ABBA | 改为 ABBA 四段组 |
| 弯道外侧有三角形空洞 | 瓦片长度未补偿 | 用 `d_outer * sin(dh_rad)` 延伸 |
| 启动时立即计入一圈 | 船初始位置在尾瓦片附近触发检测 | 添加 `lapFirstRun` 标志位 |
| 全部瓦片常驻导致卡顿 | 数百个瓦片全部 enabled | 滑动窗口只启用 70 个 |
| 可见性每帧全量计算 | O(N) 逐瓦片检查 | 只在 currentIdx 变化时重算 |

## 变体

- **8 字形赛道**: 总转向 = 720°，左弯 360° + 右弯 360°（注意交叉点处理）
- **椭圆形**: 两段 180° 大弯 + 两段纯直道（最简形态）
- **赛道宽度可变**: 通过关卡配置 `trackWidth` 参数化，`Reinit()` 重建
- **海拔变化**: 在 nodes 中增加 `y` 字段，BakeLoop 时累加坡度
