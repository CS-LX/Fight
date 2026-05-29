---
name: bump-collision
description: |
  纯 Lua 2D AABB 碰撞检测与响应库（空间哈希加速），支持 slide/bounce/cross/touch 四种碰撞响应，适用于平台跳跃、俯视角 RPG、弹幕等。
  Use when users need to (1) 2D 碰撞检测（不依赖物理引擎）, (2) 平台跳跃碰撞/俯视角碰撞,
  (3) AABB 矩形碰撞+滑动响应, (4) 空间哈希/宽相检测优化, (5) 弹幕/射线检测/区域查询,
  (6) bump / spatial hash / AABB collision, (7) 用户需要轻量 2D 碰撞而不想用完整物理引擎。
---

# bump.lua — 轻量 2D AABB 碰撞检测与响应库

> **作者**: [Enrique García Cota (kikito)](https://github.com/kikito)
> **来源**: https://github.com/kikito/bump.lua
> **许可证**: MIT
> **版本**: 3.1.7
> **体积**: 773 行，零依赖，纯 Lua 5.4 兼容

---

## 概述

bump.lua 是一个专为 2D 游戏设计的碰撞检测与响应库。它使用空间哈希（Spatial Hash）实现高效的广相检测，并内置四种碰撞响应算法。

**核心优势**：
- **空间哈希加速**：O(1) 邻居查询，支持大量对象
- **四种碰撞响应**：slide（滑动）、bounce（弹跳）、cross（穿越）、touch（触碰停止）
- **无物理引擎依赖**：纯几何碰撞，不引入重力/速度等物理概念
- **丰富的查询 API**：矩形查询、点查询、射线查询
- **自定义 filter**：精确控制哪些对象之间碰撞、如何响应

**典型适用场景**：
- 平台跳跃游戏（自己管理重力，bump 只做碰撞响应）
- 俯视角 RPG/动作游戏
- 弹幕/射击游戏的子弹碰撞
- NanoVG 2D 游戏（不需要 Box2D 的场景）

---

## 安装

将 `src/bump.lua` 复制到项目 `scripts/` 目录：

```
scripts/
├── main.lua
└── libs/
    └── bump.lua
```

```lua
local bump = require "libs.bump"
```

---

## API 参考

### 创建世界

```lua
local world = bump.newWorld(cellSize)
```

- `cellSize`（可选，默认 64）：空间哈希的网格大小。通常设为对象平均尺寸的 2-4 倍

### 对象管理

| 函数 | 说明 |
|------|------|
| `world:add(item, x, y, w, h)` | 添加对象到碰撞世界 |
| `world:remove(item)` | 移除对象 |
| `world:update(item, x, y, w, h)` | 更新对象的 AABB（不做碰撞检测） |
| `world:hasItem(item)` | 检查对象是否在世界中 |
| `world:countItems()` | 返回世界中的对象总数 |
| `world:getItems()` | 返回所有对象的数组 |

### 碰撞移动（核心）

```lua
local actualX, actualY, cols, len = world:move(item, goalX, goalY, filter)
```

- `item`：要移动的对象
- `goalX, goalY`：目标位置（左上角）
- `filter(item, other)`：碰撞过滤函数，返回碰撞类型或 nil（忽略）
- 返回值：
  - `actualX, actualY`：碰撞响应后的实际位置
  - `cols`：碰撞信息数组
  - `len`：碰撞数量

### 碰撞检查（不移动）

```lua
local cols, len = world:check(item, goalX, goalY, filter)
```

### 查询 API

| 函数 | 说明 |
|------|------|
| `world:queryRect(x, y, w, h, filter)` | 查询矩形区域内的所有对象 |
| `world:queryPoint(x, y, filter)` | 查询包含某点的所有对象 |
| `world:querySegment(x1, y1, x2, y2, filter)` | 射线查询（返回沿线段碰到的对象） |

### Filter 函数与碰撞响应

filter 函数决定碰撞如何响应：

```lua
local function filter(item, other)
    -- 返回碰撞类型字符串：
    -- "slide"   — 沿碰撞面滑动（默认，适合墙壁）
    -- "bounce"  — 反弹（适合弹球）
    -- "cross"   — 穿越（触发事件但不阻挡，适合触发器/收集物）
    -- "touch"   — 碰到即停（适合子弹命中）
    -- nil/false — 完全忽略此碰撞
    
    if other.type == "wall" then return "slide" end
    if other.type == "coin" then return "cross" end
    if other.type == "enemy" then return "touch" end
    return nil  -- 忽略
end
```

### 碰撞信息结构（cols[i]）

| 字段 | 类型 | 说明 |
|------|------|------|
| `col.item` | any | 移动的对象 |
| `col.other` | any | 碰到的对象 |
| `col.type` | string | 碰撞响应类型 |
| `col.overlaps` | bool | 移动前是否已重叠 |
| `col.ti` | number | 碰撞发生的时间比例 [0,1] |
| `col.move` | {x,y} | 实际移动向量 |
| `col.normal` | {x,y} | 碰撞法线 |
| `col.touch` | {x,y} | 碰撞接触点 |
| `col.itemRect` | {x,y,w,h} | 移动对象的初始 AABB |
| `col.otherRect` | {x,y,w,h} | 碰撞对象的 AABB |

---

## UrhoX 集成模式

### 基础用法 — 平台跳跃

```lua
local bump = require "libs.bump"

local world = bump.newWorld(64)
local player = { x = 100, y = 100, w = 32, h = 48, vx = 0, vy = 0, onGround = false }

function Start()
    -- 添加玩家
    world:add(player, player.x, player.y, player.w, player.h)

    -- 添加地面和平台
    local ground = { type = "wall" }
    world:add(ground, 0, 500, 800, 32)

    local platform = { type = "wall" }
    world:add(platform, 200, 350, 150, 16)
end

local function collisionFilter(item, other)
    if other.type == "wall" then return "slide" end
    return nil
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 输入
    if input:GetKeyDown(KEY_A) then player.vx = -200 end
    if input:GetKeyDown(KEY_D) then player.vx = 200 end
    if not input:GetKeyDown(KEY_A) and not input:GetKeyDown(KEY_D) then
        player.vx = 0
    end
    if player.onGround and input:GetKeyPress(KEY_SPACE) then
        player.vy = -400
    end

    -- 重力
    player.vy = player.vy + 800 * dt

    -- 移动 + 碰撞
    local goalX = player.x + player.vx * dt
    local goalY = player.y + player.vy * dt
    local actualX, actualY, cols, len = world:move(player, goalX, goalY, collisionFilter)

    -- 处理碰撞结果
    player.onGround = false
    for i = 1, len do
        local col = cols[i]
        if col.normal.y == -1 then  -- 碰到上表面（脚下）
            player.onGround = true
            player.vy = 0
        elseif col.normal.y == 1 then  -- 碰到下表面（头顶）
            player.vy = 0
        end
    end

    player.x, player.y = actualX, actualY
end
```

### 俯视角 RPG — 多类型碰撞

```lua
local bump = require "libs.bump"
local world = bump.newWorld(48)

-- 碰撞过滤器
local function rpgFilter(item, other)
    if other.type == "wall" then return "slide" end
    if other.type == "coin" then return "cross" end
    if other.type == "npc" then return "slide" end
    if other.type == "trigger" then return "cross" end
    return nil
end

function MovePlayer(dx, dy, dt)
    local goalX = player.x + dx * player.speed * dt
    local goalY = player.y + dy * player.speed * dt
    local actualX, actualY, cols, len = world:move(player, goalX, goalY, rpgFilter)

    -- 处理碰撞事件
    for i = 1, len do
        local col = cols[i]
        if col.other.type == "coin" then
            CollectCoin(col.other)
            world:remove(col.other)
        elseif col.other.type == "trigger" then
            ActivateTrigger(col.other)
        end
    end

    player.x, player.y = actualX, actualY
end
```

### 弹幕/子弹 — 射线检测

```lua
local bump = require "libs.bump"

-- 射线检测：从枪口到远处
function FireBullet(startX, startY, dirX, dirY, range)
    local endX = startX + dirX * range
    local endY = startY + dirY * range

    local items, len = world:querySegment(startX, startY, endX, endY, function(item)
        return item.type == "enemy" or item.type == "wall"
    end)

    if len > 0 then
        local hit = items[1]  -- 最近的碰撞
        if hit.type == "enemy" then
            hit.hp = hit.hp - 10
        end
        return true
    end
    return false
end
```

### 区域查询 — 爆炸范围

```lua
-- 查询爆炸半径内的所有对象
function Explode(cx, cy, radius)
    local x, y = cx - radius, cy - radius
    local size = radius * 2
    local items, len = world:queryRect(x, y, size, size)

    for i = 1, len do
        local item = items[i]
        if item.type == "enemy" then
            local dist = math.sqrt((item.x - cx)^2 + (item.y - cy)^2)
            local damage = math.max(0, 100 * (1 - dist / radius))
            item.hp = item.hp - damage
        end
    end
end
```

### 与 NanoVG 配合 — 纯 2D 游戏

```lua
local bump = require "libs.bump"
local world = bump.newWorld(64)

-- 所有游戏对象都是 table，NanoVG 负责渲染
local entities = {}

function AddEntity(type, x, y, w, h, color)
    local e = { type = type, x = x, y = y, w = w, h = h, color = color }
    world:add(e, x, y, w, h)
    table.insert(entities, e)
    return e
end

-- NanoVG 渲染所有实体
function HandleNanoVGRender(eventType, eventData)
    nvgBeginFrame(vg, width, height, 1.0)
    for _, e in ipairs(entities) do
        nvgBeginPath(vg)
        nvgRect(vg, e.x, e.y, e.w, e.h)
        nvgFillColor(vg, e.color)
        nvgFill(vg)
    end
    nvgEndFrame(vg)
end
```

---

## 与 Box2D 的区别

| 特性 | bump.lua | Box2D (UrhoX 内置) |
|------|----------|-------------------|
| 碰撞形状 | 仅 AABB 矩形 | 多边形、圆形、边 |
| 物理模拟 | 无（纯几何） | 完整刚体物理 |
| 重力/力 | 自己实现 | 引擎自动处理 |
| 适合场景 | 轻量 2D、NanoVG 游戏 | 需要真实物理的游戏 |
| 性能特征 | O(1) 空间哈希查询 | O(n log n) 动态树 |
| 碰撞响应 | 4 种预设 + filter | 物理引擎自动计算 |

**选择建议**：
- 需要真实物理（重力、弹力、摩擦力、关节）→ 用 Box2D
- 只需碰撞检测+简单响应、自己管理运动逻辑 → 用 bump.lua
- NanoVG 纯 2D 游戏（无 Urho2D 节点）→ 用 bump.lua

---

## 注意事项

1. **AABB 坐标是左上角**：`(x, y)` 是矩形左上角，`(w, h)` 是宽高
2. **item 可以是任意 Lua 值**：table、userdata 等都可以作为 item
3. **filter 必须是纯函数**：不要在 filter 中修改游戏状态
4. **移除后不能再 move**：`world:remove(item)` 后不要再对它调用 `world:move()`
5. **cellSize 调优**：太小会增加内存，太大会降低查询效率。一般设为对象平均尺寸的 2-4 倍

---

## 文件清单

```
.claude/skills/bump-collision/
├── SKILL.md          # 本文件
├── LICENSE           # MIT 许可证
└── src/
    └── bump.lua      # 源码（773 行）
```
