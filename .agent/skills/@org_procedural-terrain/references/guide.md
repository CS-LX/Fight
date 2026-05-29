# 程序化地形/地牢生成算法通用指南

> 适用于任何 2D 瓦片地图项目：地牢、矿洞、地下世界、洞穴、岛屿、地形等
> 最后更新: 2026-04-30

---

## 目录

1. [概述与算法选型](#1-概述与算法选型)
2. [随机游走算法 (Random Walk)](#2-随机游走算法-random-walk)
3. [Perlin 噪声地形生成](#3-perlin-噪声地形生成)
4. [元胞自动机 (Cellular Automata)](#4-元胞自动机-cellular-automata)
5. [BSP 树分割 (Binary Space Partitioning)](#5-bsp-树分割-binary-space-partitioning)
6. [洪水填充与连通性验证](#6-洪水填充与连通性验证)
7. [混合策略与后处理](#7-混合策略与后处理)
8. [瓦片地图渲染基础](#8-瓦片地图渲染基础)
9. [可破坏地形系统](#9-可破坏地形系统)
10. [性能优化通用策略](#10-性能优化通用策略)
11. [算法选型决策树](#11-算法选型决策树)
12. [完整代码模板](#12-完整代码模板)

---

## 1. 概述与算法选型

### 1.1 四大核心算法

| 算法 | 特点 | 适合场景 | 复杂度 |
|------|------|---------|-------|
| 随机游走 | 有机、洞穴感、蜿蜒 | 矿洞、地下通道、自然洞穴 | 低 |
| Perlin 噪声 | 连续、自然、可分层 | 大陆地形、生物群落、高度图 | 中 |
| 元胞自动机 | 平滑、洞穴状、可控密度 | 洞穴系统、岩石分布 | 低 |
| BSP 树 | 结构化、矩形房间 | 传统地牢、室内建筑 | 中 |

### 1.2 关键原则

```
1. 没有单一算法能生成完美地图 → 混合使用
2. 算法只生成骨架 → 后处理让它好玩
3. 种子(seed)决定一切 → 同种子 = 同地图 = 可存档复现
4. 先验证连通性 → 再美化 → 再放置内容
```

---

## 2. 随机游走算法 (Random Walk)

### 2.1 基础原理

在全墙地图上放置一个"挖掘者"，每步随机向上下左右移动一格，走到哪就把该格变成地面。

```
初始状态 → 挖掘者行走中 → 行走完毕
████████    ████████       ████████
████████    ███░████       ███░░███
████████    ██░░████       ██░░░░██
████████    ███░████       ██░████
████████    ████████       ███░░███
```

### 2.2 基础实现

```lua
--- 随机游走算法
--- @param width number 地图宽度
--- @param height number 地图高度
--- @param steps number 总步数
--- @param seed number 随机种子
--- @return table map 二维数组，0=地面 1=墙
function randomWalk(width, height, steps, seed)
    math.randomseed(seed)

    -- 初始化全墙地图
    local map = {}
    for x = 1, width do
        map[x] = {}
        for y = 1, height do
            map[x][y] = 1  -- 1 = 墙
        end
    end

    -- 挖掘者起始位置（地图中心）
    local cx = math.floor(width / 2)
    local cy = math.floor(height / 2)
    map[cx][cy] = 0  -- 0 = 地面

    -- 四方向
    local dirs = {
        { dx = 0, dy = -1 },  -- 上
        { dx = 0, dy =  1 },  -- 下
        { dx = -1, dy = 0 },  -- 左
        { dx =  1, dy = 0 },  -- 右
    }

    -- 开始行走
    for i = 1, steps do
        local dir = dirs[math.random(1, 4)]
        cx = math.max(2, math.min(cx + dir.dx, width - 1))
        cy = math.max(2, math.min(cy + dir.dy, height - 1))
        map[cx][cy] = 0
    end

    return map
end
```

### 2.3 多挖掘者并行

解决单个挖掘者容易生成蛇形单通道的问题：

```lua
--- 多挖掘者随机游走
--- @param width number
--- @param height number
--- @param walkerCount number 挖掘者数量
--- @param stepsPerWalker number 每个挖掘者的步数
--- @param seed number
--- @return table map
function multiWalkerRandomWalk(width, height, walkerCount, stepsPerWalker, seed)
    math.randomseed(seed)

    local map = {}
    for x = 1, width do
        map[x] = {}
        for y = 1, height do
            map[x][y] = 1
        end
    end

    local dirs = {
        { dx = 0, dy = -1 },
        { dx = 0, dy =  1 },
        { dx = -1, dy = 0 },
        { dx =  1, dy = 0 },
    }

    -- 所有挖掘者从中心出发
    local startX = math.floor(width / 2)
    local startY = math.floor(height / 2)

    for w = 1, walkerCount do
        local cx, cy = startX, startY
        map[cx][cy] = 0

        for i = 1, stepsPerWalker do
            local dir = dirs[math.random(1, 4)]
            cx = math.max(2, math.min(cx + dir.dx, width - 1))
            cy = math.max(2, math.min(cy + dir.dy, height - 1))
            map[cx][cy] = 0
        end
    end

    return map
end
```

### 2.4 方向加权

控制挖掘者的行走偏向，生成特定形状：

```lua
--- 加权方向随机游走
--- @param dirWeights table 方向权重 {up, down, left, right}
function weightedRandomWalk(width, height, steps, dirWeights, seed)
    math.randomseed(seed)
    -- ... 初始化同上 ...

    local dirs = {
        { dx = 0, dy = -1, weight = dirWeights.up    or 1 },
        { dx = 0, dy =  1, weight = dirWeights.down  or 1 },
        { dx = -1, dy = 0, weight = dirWeights.left  or 1 },
        { dx =  1, dy = 0, weight = dirWeights.right or 1 },
    }

    local totalWeight = 0
    for _, d in ipairs(dirs) do totalWeight = totalWeight + d.weight end

    for i = 1, steps do
        -- 加权随机选择方向
        local roll = math.random() * totalWeight
        local accumulated = 0
        local chosenDir = dirs[1]
        for _, d in ipairs(dirs) do
            accumulated = accumulated + d.weight
            if roll <= accumulated then
                chosenDir = d
                break
            end
        end

        cx = math.max(2, math.min(cx + chosenDir.dx, width - 1))
        cy = math.max(2, math.min(cy + chosenDir.dy, height - 1))
        map[cx][cy] = 0
    end

    return map
end
```

**典型权重配置**：

| 应用场景 | up | down | left | right | 效果 |
|---------|-----|------|------|-------|------|
| 水平隧道 | 0.1 | 0.1 | 0.4 | 0.4 | 横向为主，偶尔起伏 |
| 垂直矿井 | 0.1 | 0.6 | 0.15 | 0.15 | 向下为主 |
| 斜向矿脉 | 0.1 | 0.3 | 0.3 | 0.3 | 斜向延伸 |
| 均匀洞穴 | 0.25 | 0.25 | 0.25 | 0.25 | 自然扩散 |

### 2.5 空间扩张优化

解决随机游走生成的通道过窄的问题：

```lua
--- 空间扩张：周围地面够多的墙 → 概率变成地面
--- @param map table 地图
--- @param threshold number 周围地面数量阈值 (建议 4-5)
--- @param probability number 转换概率 (建议 0.4-0.6)
--- @param iterations number 迭代次数 (建议 2-3)
function expandSpaces(map, width, height, threshold, probability, iterations)
    for iter = 1, iterations do
        local newMap = deepCopy(map)

        for x = 2, width - 1 do
            for y = 2, height - 1 do
                if map[x][y] == 1 then  -- 当前是墙
                    local floorCount = countNeighborFloors(map, x, y)
                    if floorCount >= threshold and math.random() < probability then
                        newMap[x][y] = 0  -- 变成地面
                    end
                end
            end
        end

        map = newMap
    end

    return map
end

--- 统计 8 邻域中地面的数量
function countNeighborFloors(map, x, y)
    local count = 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            if not (dx == 0 and dy == 0) then
                if map[x + dx] and map[x + dx][y + dy] == 0 then
                    count = count + 1
                end
            end
        end
    end
    return count
end
```

---

## 3. Perlin 噪声地形生成

### 3.1 基础原理

Perlin 噪声生成连续、平滑的随机值（0~1），相邻采样点的值相近，适合表达自然地形的连续性。

### 3.2 简易 Perlin 噪声实现

```lua
--- 简易 2D Perlin 噪声（基于 value noise 的简化版）
--- 适合不依赖外部库的项目
local function fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

--- 基于种子的伪随机哈希
local function hash(x, y, seed)
    local h = seed + x * 374761393 + y * 668265263
    h = (h ~ (h >> 13)) * 1274126177
    h = h ~ (h >> 16)
    return (h % 1000) / 1000  -- 归一化到 0~1
end

--- 2D Value Noise
--- @param x number 采样 X 坐标（通常 = 网格X * scale）
--- @param y number 采样 Y 坐标
--- @param seed number 随机种子
--- @return number 噪声值 0~1
function valueNoise2D(x, y, seed)
    local ix = math.floor(x)
    local iy = math.floor(y)
    local fx = x - ix
    local fy = y - iy

    -- 四个角的随机值
    local v00 = hash(ix, iy, seed)
    local v10 = hash(ix + 1, iy, seed)
    local v01 = hash(ix, iy + 1, seed)
    local v11 = hash(ix + 1, iy + 1, seed)

    -- 平滑插值
    local u = fade(fx)
    local v = fade(fy)

    return lerp(lerp(v00, v10, u), lerp(v01, v11, u), v)
end

--- 多层叠加（分形噪声 / fBm）
--- @param x number
--- @param y number
--- @param octaves number 叠加层数 (建议 3-6)
--- @param persistence number 每层振幅衰减 (建议 0.5)
--- @param seed number
--- @return number 噪声值 0~1
function fractalNoise2D(x, y, octaves, persistence, seed)
    local total = 0
    local amplitude = 1
    local frequency = 1
    local maxValue = 0

    for i = 1, octaves do
        total = total + valueNoise2D(x * frequency, y * frequency, seed + i * 100) * amplitude
        maxValue = maxValue + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * 2
    end

    return total / maxValue  -- 归一化
end
```

### 3.3 噪声生成地形高度图

```lua
--- 用噪声生成 2D 高度图地形
--- @param width number
--- @param height number
--- @param scale number 缩放因子（越大地形越平缓，建议 0.02-0.1）
--- @param threshold number 阈值（大于此值 = 实心，建议 0.45-0.55）
--- @param seed number
function generateTerrainWithNoise(width, height, scale, threshold, seed)
    local map = {}

    for x = 1, width do
        map[x] = {}
        for y = 1, height do
            local noise = fractalNoise2D(x * scale, y * scale, 4, 0.5, seed)

            if noise > threshold then
                map[x][y] = 1  -- 实心（墙/岩石）
            else
                map[x][y] = 0  -- 空腔（地面/通道）
            end
        end
    end

    return map
end
```

### 3.4 多材质分布

用不同种子的噪声叠加，分配不同材质类型：

```lua
--- 用多层噪声分配材质类型
--- @param width number
--- @param height number
--- @param materialDefs table 材质定义表
--- @param seed number
function generateMultiMaterialMap(width, height, materialDefs, seed)
    local map = {}

    for x = 1, width do
        map[x] = {}
        for y = 1, height do
            local bestScore = -1
            local bestType = materialDefs[1].id

            for i, mat in ipairs(materialDefs) do
                local noise = fractalNoise2D(
                    x * mat.scale,
                    y * mat.scale,
                    mat.octaves or 4,
                    0.5,
                    seed + i * 9999
                )
                -- 噪声值 × 该深度的权重 = 得分
                local weight = mat.getWeight(y)  -- 函数：根据深度返回权重
                local score = noise * weight

                if score > bestScore then
                    bestScore = score
                    bestType = mat.id
                end
            end

            map[x][y] = bestType
        end
    end

    return map
end

-- 使用示例
local materials = {
    {
        id = "soil",
        scale = 0.04,
        getWeight = function(depth)
            if depth < 30 then return 0.7
            elseif depth < 60 then return 0.3
            else return 0.05 end
        end,
    },
    {
        id = "granite",
        scale = 0.09,
        getWeight = function(depth)
            if depth < 30 then return 0.02
            elseif depth < 100 then return 0.35
            else return 0.5 end
        end,
    },
}
```

---

## 4. 元胞自动机 (Cellular Automata)

### 4.1 基础原理

1. 随机填充地图（每格 45%~55% 概率为墙）
2. 反复迭代：每格根据周围 8 邻域的墙数量决定自己变成墙还是地面
3. 几轮后自然形成平滑的洞穴形状

### 4.2 实现

```lua
--- 元胞自动机洞穴生成
--- @param width number
--- @param height number
--- @param fillPercent number 初始墙比例 (建议 0.45-0.55)
--- @param iterations number 迭代次数 (建议 4-6)
--- @param seed number
function cellularAutomataCave(width, height, fillPercent, iterations, seed)
    math.randomseed(seed)

    -- 第1步：随机填充
    local map = {}
    for x = 1, width do
        map[x] = {}
        for y = 1, height do
            -- 边界强制为墙
            if x == 1 or x == width or y == 1 or y == height then
                map[x][y] = 1
            else
                map[x][y] = (math.random() < fillPercent) and 1 or 0
            end
        end
    end

    -- 第2步：迭代平滑
    for iter = 1, iterations do
        local newMap = {}
        for x = 1, width do
            newMap[x] = {}
            for y = 1, height do
                local wallCount = countNeighborWalls(map, x, y, width, height)

                -- 4-5 规则：
                -- 周围墙 > 4 → 变成墙
                -- 周围墙 < 4 → 变成地面
                -- 周围墙 = 4 → 保持不变
                if wallCount > 4 then
                    newMap[x][y] = 1
                elseif wallCount < 4 then
                    newMap[x][y] = 0
                else
                    newMap[x][y] = map[x][y]
                end
            end
        end
        map = newMap
    end

    return map
end

function countNeighborWalls(map, x, y, width, height)
    local count = 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx == 0 and dy == 0 then
                -- 跳过自己
            else
                local nx, ny = x + dx, y + dy
                if nx < 1 or nx > width or ny < 1 or ny > height then
                    count = count + 1  -- 边界外视为墙
                elseif map[nx][ny] == 1 then
                    count = count + 1
                end
            end
        end
    end
    return count
end
```

### 4.3 参数调优

| 参数 | 值 | 效果 |
|------|---|------|
| fillPercent = 0.40 | 开阔 | 大面积空腔，少量柱状墙体 |
| fillPercent = 0.45 | 均衡 | 适中的洞穴感（推荐） |
| fillPercent = 0.50 | 密集 | 窄通道为主 |
| fillPercent = 0.55 | 迷宫 | 非常窄的通道，多死角 |
| iterations = 3 | 粗糙 | 边缘不规则 |
| iterations = 5 | 平滑 | 边缘圆润（推荐） |
| iterations = 8 | 过度 | 可能出现大面积连通或完全封闭 |

---

## 5. BSP 树分割 (Binary Space Partitioning)

### 5.1 基础原理

递归地将空间二分为更小的子区域，在每个最小区域内放置一个房间，再用走廊连接。

适合生成传统的"房间+走廊"式地牢，不适合自然洞穴。

### 5.2 实现

```lua
--- BSP 树节点
--- @class BSPNode
--- @field x number
--- @field y number
--- @field w number
--- @field h number
--- @field left BSPNode|nil
--- @field right BSPNode|nil
--- @field room table|nil {x, y, w, h}

--- BSP 地牢生成
--- @param width number
--- @param height number
--- @param minRoomSize number 最小房间尺寸 (建议 5-8)
--- @param seed number
function generateBSPDungeon(width, height, minRoomSize, seed)
    math.randomseed(seed)

    local map = {}
    for x = 1, width do
        map[x] = {}
        for y = 1, height do
            map[x][y] = 1  -- 全墙
        end
    end

    -- 根节点 = 整个地图
    local root = { x = 1, y = 1, w = width, h = height }

    -- 递归分割
    splitNode(root, minRoomSize)

    -- 在叶节点中创建房间
    createRooms(root, map, minRoomSize)

    -- 连接相邻房间
    connectRooms(root, map)

    return map
end

function splitNode(node, minSize)
    local canSplitH = node.h >= minSize * 2 + 2
    local canSplitV = node.w >= minSize * 2 + 2

    if not canSplitH and not canSplitV then return end

    -- 随机选择分割方向
    local splitHorizontally
    if canSplitH and canSplitV then
        splitHorizontally = math.random() < 0.5
    else
        splitHorizontally = canSplitH
    end

    if splitHorizontally then
        local split = math.random(minSize + 1, node.h - minSize)
        node.left  = { x = node.x, y = node.y, w = node.w, h = split }
        node.right = { x = node.x, y = node.y + split, w = node.w, h = node.h - split }
    else
        local split = math.random(minSize + 1, node.w - minSize)
        node.left  = { x = node.x, y = node.y, w = split, h = node.h }
        node.right = { x = node.x + split, y = node.y, w = node.w - split, h = node.h }
    end

    splitNode(node.left, minSize)
    splitNode(node.right, minSize)
end

function createRooms(node, map, minSize)
    if node.left then createRooms(node.left, map, minSize) end
    if node.right then createRooms(node.right, map, minSize) end

    -- 叶节点：创建房间
    if not node.left and not node.right then
        local rw = math.random(minSize, node.w - 2)
        local rh = math.random(minSize, node.h - 2)
        local rx = node.x + math.random(1, node.w - rw - 1)
        local ry = node.y + math.random(1, node.h - rh - 1)

        node.room = { x = rx, y = ry, w = rw, h = rh }

        -- 把房间区域设为地面
        for x = rx, rx + rw - 1 do
            for y = ry, ry + rh - 1 do
                if x >= 1 and x <= #map and y >= 1 and y <= #map[1] then
                    map[x][y] = 0
                end
            end
        end
    end
end
```

---

## 6. 洪水填充与连通性验证

### 6.1 洪水填充 (Flood Fill)

```lua
--- 洪水填充：从起点扩散，标记所有连通的地面格
--- @param map table
--- @param startX number
--- @param startY number
--- @return table visited 被访问的格子集合
--- @return number count 连通区域大小
function floodFill(map, startX, startY, width, height)
    local visited = {}
    local count = 0
    local queue = { { startX, startY } }
    local key = function(x, y) return x .. "," .. y end

    visited[key(startX, startY)] = true

    while #queue > 0 do
        local pos = table.remove(queue, 1)
        local x, y = pos[1], pos[2]
        count = count + 1

        local dirs = { {0,-1}, {0,1}, {-1,0}, {1,0} }
        for _, d in ipairs(dirs) do
            local nx, ny = x + d[1], y + d[2]
            local nk = key(nx, ny)
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height
               and not visited[nk] and map[nx][ny] == 0 then
                visited[nk] = true
                table.insert(queue, { nx, ny })
            end
        end
    end

    return visited, count
end
```

### 6.2 连通性验证与修复

```lua
--- 确保地图中所有地面区域连通
--- 找出所有独立区域，用走廊连接到最大区域
function ensureConnectivity(map, width, height)
    local globalVisited = {}
    local regions = {}
    local key = function(x, y) return x .. "," .. y end

    -- 找出所有独立连通区域
    for x = 1, width do
        for y = 1, height do
            if map[x][y] == 0 and not globalVisited[key(x, y)] then
                local visited, count = floodFill(map, x, y, width, height)
                table.insert(regions, {
                    visited = visited,
                    count = count,
                    startX = x,
                    startY = y,
                })
                -- 合并到全局访问表
                for k, v in pairs(visited) do
                    globalVisited[k] = v
                end
            end
        end
    end

    if #regions <= 1 then return end  -- 已经连通

    -- 按大小排序，最大区域排前面
    table.sort(regions, function(a, b) return a.count > b.count end)

    -- 将所有小区域连接到最大区域
    local mainRegion = regions[1]
    for i = 2, #regions do
        local smallRegion = regions[i]
        -- 在两个区域之间挖一条走廊
        carveCorridor(map, smallRegion.startX, smallRegion.startY,
                      mainRegion.startX, mainRegion.startY)
    end
end

--- 挖走廊：从 (x1,y1) 到 (x2,y2)，L 形路径
function carveCorridor(map, x1, y1, x2, y2)
    local x, y = x1, y1

    -- 先水平走
    while x ~= x2 do
        map[x][y] = 0
        x = x + (x2 > x and 1 or -1)
    end
    -- 再垂直走
    while y ~= y2 do
        map[x][y] = 0
        y = y + (y2 > y and 1 or -1)
    end
end
```

---

## 7. 混合策略与后处理

### 7.1 典型混合流程

```
第1步：用算法 A 生成基础骨架
  ↓
第2步：用算法 B 叠加细节
  ↓
第3步：连通性验证 + 修复
  ↓
第4步：后处理美化
  ↓
第5步：放置内容（道具、敌人、事件）
```

### 7.2 常见混合方案

| 目标 | 骨架算法 | 细节算法 | 效果 |
|------|---------|---------|------|
| 自然矿洞 | 随机游走 | 空间扩张 + 元胞自动机平滑 | 有机、不规则、自然 |
| 地下城 | BSP 房间 | 随机游走连接走廊 | 结构化但不呆板 |
| 地下世界 | Perlin 噪声分层 | 随机游走挖矿脉/溶洞 | 层次分明、特征丰富 |
| 岛屿/大陆 | Perlin 噪声高度图 | 元胞自动机海岸线 | 海岸线自然 |

### 7.3 后处理技术

```lua
--- 移除孤立的小墙块（1-2格的墙体碎片）
function removeSmallWalls(map, width, height, minSize)
    -- 对墙体做洪水填充，小于 minSize 的墙体区域删除
end

--- 移除过小的房间
function removeSmallRooms(map, width, height, minSize)
    -- 对地面做洪水填充，小于 minSize 的区域填回墙体
end

--- 边界墙加厚（防止地图边缘只有1格墙）
function thickenBorders(map, width, height, thickness)
    for t = 1, thickness do
        for x = 1, width do
            map[x][t] = 1
            map[x][height - t + 1] = 1
        end
        for y = 1, height do
            map[t][y] = 1
            map[width - t + 1][y] = 1
        end
    end
end
```

---

## 8. 瓦片地图渲染基础

### 8.1 Auto-Tiling (自动贴图选择)

根据瓦片的 8 邻域状态，自动选择正确的边缘/角落贴图：

```lua
--- 计算 Auto-Tile 索引 (4-bit 简化版)
--- 只看上下左右 4 方向，16 种组合
function getAutoTileIndex(map, x, y)
    local top    = (map[x] and map[x][y-1] == 1) and 1 or 0
    local right  = (map[x+1] and map[x+1][y] == 1) and 1 or 0
    local bottom = (map[x] and map[x][y+1] == 1) and 1 or 0
    local left   = (map[x-1] and map[x-1][y] == 1) and 1 or 0

    -- 4-bit 编码：上右下左
    return top * 8 + right * 4 + bottom * 2 + left * 1
end

-- 使用：
-- index = 0  → 独立方块（四面都是地面）
-- index = 15 → 完全被墙包围（内部实心）
-- index = 3  → 下和左有墙 → 选择左下角贴图
```

### 8.2 贴图变体

避免大面积同种瓦片看起来重复：

```lua
--- 为同种瓦片选择外观变体
function getTileVariant(x, y, variantCount, seed)
    -- 基于位置的伪随机，保证同位置总是同变体
    local h = (x * 374761 + y * 668265 + seed) % variantCount
    return h + 1  -- Lua 索引从 1 开始
end
```

---

## 9. 可破坏地形系统

### 9.1 瓦片耐久度系统

```lua
--- 瓦片数据结构
TileData = {
    type = "stone",      -- 类型
    hp = 100,            -- 当前 HP
    maxHp = 100,         -- 最大 HP
    crackLevel = 0,      -- 裂纹等级 0-3
}

--- 对瓦片施加伤害
--- @return boolean destroyed 是否被破坏
function damageTile(tile, damage)
    tile.hp = math.max(0, tile.hp - damage)

    -- 更新裂纹等级
    local hpPercent = tile.hp / tile.maxHp
    if hpPercent <= 0 then
        tile.crackLevel = 4  -- 已销毁
        return true
    elseif hpPercent <= 0.25 then
        tile.crackLevel = 3
    elseif hpPercent <= 0.50 then
        tile.crackLevel = 2
    elseif hpPercent <= 0.75 then
        tile.crackLevel = 1
    end

    return false
end
```

### 9.2 碎片粒子系统

```lua
--- 简易碎片粒子
--- @class Particle
--- @field x number
--- @field y number
--- @field vx number 水平速度
--- @field vy number 垂直速度
--- @field rotation number 旋转角度
--- @field rotSpeed number 旋转速度
--- @field life number 剩余生命（秒）
--- @field color table {r, g, b, a}
--- @field size number

--- 生成碎片粒子
function spawnDebrisParticles(x, y, tileType, count)
    local particles = {}
    local color = TILE_TYPES[tileType].particleColor

    for i = 1, count do
        table.insert(particles, {
            x = x,
            y = y,
            vx = (math.random() - 0.5) * 200,  -- 水平随机速度
            vy = -math.random() * 150 - 50,     -- 向上弹出
            rotation = math.random() * 360,
            rotSpeed = (math.random() - 0.5) * 720,
            life = 0.3 + math.random() * 0.3,
            color = { color[1], color[2], color[3], 1.0 },
            size = 2 + math.random() * 4,
        })
    end

    return particles
end

--- 更新碎片粒子
function updateParticles(particles, dt, gravity)
    gravity = gravity or 500
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + gravity * dt  -- 重力
        p.rotation = p.rotation + p.rotSpeed * dt
        p.life = p.life - dt
        p.color[4] = math.max(0, p.life / 0.5)  -- 淡出

        if p.life <= 0 then
            table.remove(particles, i)
        else
            i = i + 1
        end
    end
end
```

---

## 10. 性能优化通用策略

### 10.1 分块加载 (Chunk System)

```lua
CHUNK_SIZE = 16  -- 每个 chunk 16x16 瓦片

--- 获取坐标所在的 chunk 索引
function getChunkIndex(x, y)
    return math.floor((x - 1) / CHUNK_SIZE) + 1,
           math.floor((y - 1) / CHUNK_SIZE) + 1
end

--- 只加载摄像机可见范围内的 chunk
function getVisibleChunks(cameraX, cameraY, viewWidth, viewHeight)
    local minCX, minCY = getChunkIndex(cameraX - viewWidth/2, cameraY - viewHeight/2)
    local maxCX, maxCY = getChunkIndex(cameraX + viewWidth/2, cameraY + viewHeight/2)

    -- 加 1 格缓冲
    minCX = minCX - 1
    minCY = minCY - 1
    maxCX = maxCX + 1
    maxCY = maxCY + 1

    return minCX, minCY, maxCX, maxCY
end
```

### 10.2 对象池

```lua
--- 通用对象池
--- @class ObjectPool
ObjectPool = {}

function ObjectPool.new(createFunc, resetFunc, initialSize)
    local pool = {
        objects = {},
        createFunc = createFunc,
        resetFunc = resetFunc,
    }

    -- 预创建
    for i = 1, (initialSize or 20) do
        local obj = createFunc()
        obj._poolActive = false
        table.insert(pool.objects, obj)
    end

    return pool
end

function ObjectPool.get(pool)
    for _, obj in ipairs(pool.objects) do
        if not obj._poolActive then
            obj._poolActive = true
            pool.resetFunc(obj)
            return obj
        end
    end

    -- 池子空了，创建新对象
    local obj = pool.createFunc()
    obj._poolActive = true
    table.insert(pool.objects, obj)
    return obj
end

function ObjectPool.release(pool, obj)
    obj._poolActive = false
end
```

### 10.3 脏标记渲染

```lua
--- 只在瓦片状态变化时更新渲染，不是每帧全部重绘
local dirtyTiles = {}

function markDirty(x, y)
    dirtyTiles[x .. "," .. y] = true
end

function renderDirtyTiles()
    for key, _ in pairs(dirtyTiles) do
        local x, y = key:match("(%d+),(%d+)")
        x, y = tonumber(x), tonumber(y)
        -- 只重绘这个瓦片
        renderTile(x, y)
    end
    dirtyTiles = {}
end
```

---

## 11. 算法选型决策树

```
你要生成什么？
│
├─ 自然洞穴/矿洞？
│   ├─ 需要大型开阔空间？ → 元胞自动机 (fillPercent=0.45)
│   ├─ 需要蜿蜒通道？    → 随机游走 (单挖掘者)
│   └─ 两者都要？        → 随机游走 + 空间扩张 + 元胞自动机平滑
│
├─ 结构化地牢（房间+走廊）？
│   └─ BSP 树分割
│
├─ 大陆/岛屿地形？
│   └─ Perlin 噪声高度图
│
├─ 地下多材质分布？
│   └─ 深度概率表 + Perlin 噪声多层叠加
│
├─ 矿脉/河流等线性结构？
│   └─ 加权随机游走（方向偏向）
│
└─ 以上组合？
    └─ 混合策略（第7章）
```

---

## 12. 完整代码模板

### 12.1 最小可运行：随机游走矿洞

```lua
--[[
    最小可运行的随机游走矿洞生成器
    复制此文件即可运行，无外部依赖
]]

local MAP_WIDTH = 60
local MAP_HEIGHT = 40
local WALKER_COUNT = 5
local STEPS_PER_WALKER = 200
local SEED = os.time()

-- 生成
local map = multiWalkerRandomWalk(MAP_WIDTH, MAP_HEIGHT, WALKER_COUNT, STEPS_PER_WALKER, SEED)

-- 空间扩张
map = expandSpaces(map, MAP_WIDTH, MAP_HEIGHT, 4, 0.5, 2)

-- 连通性验证
ensureConnectivity(map, MAP_WIDTH, MAP_HEIGHT)

-- 放置矿石（在地面格旁的墙上）
placeOres(map, MAP_WIDTH, MAP_HEIGHT, 0.15)  -- 15% 墙格变成矿石

-- 渲染（实际项目中替换为引擎渲染代码）
printMap(map, MAP_WIDTH, MAP_HEIGHT)
```

### 12.2 完整混合生成管线（框架）

```lua
--[[
    完整混合生成管线框架
    按需组合各算法模块
]]

function generateWorld(config)
    local width = config.width
    local height = config.height
    local seed = config.seed or os.time()

    -- 第1步：基础地形（选一个）
    local map
    if config.style == "cave" then
        map = cellularAutomataCave(width, height, 0.45, 5, seed)
    elseif config.style == "dungeon" then
        map = generateBSPDungeon(width, height, 6, seed)
    elseif config.style == "terrain" then
        map = generateTerrainWithNoise(width, height, 0.05, 0.5, seed)
    elseif config.style == "mine" then
        -- 噪声基础 + 随机游走矿道
        map = generateMultiMaterialMap(width, height, config.materials, seed)
        for i = 1, config.tunnelCount or 3 do
            local startY = math.random(1, height)
            weightedRandomWalk(width, height, 100, {up=0.1, down=0.1, left=0.4, right=0.4}, seed + i)
        end
    end

    -- 第2步：后处理
    removeSmallWalls(map, width, height, 3)
    removeSmallRooms(map, width, height, 5)
    thickenBorders(map, width, height, 2)

    -- 第3步：连通性
    ensureConnectivity(map, width, height)

    -- 第4步：放置内容
    placeEntrance(map, width)
    placeExit(map, width, height)
    placeOres(map, width, height, config.orePercent or 0.1)
    placeEvents(map, width, height, config.events or {})

    return map
end
```

---

## 参考资料

- Random Walk / Drunkard's Walk 算法
- Perlin Noise (Ken Perlin, 1983)
- Cellular Automata for cave generation (Johnson L., 2010)
- Binary Space Partitioning for dungeon generation
- 星露谷物语矿洞生成分析
- Spelunky 关卡生成设计
- Noita 可破坏地形实现
