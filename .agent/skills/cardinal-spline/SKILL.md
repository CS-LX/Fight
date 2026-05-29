---
name: cardinal-spline
description: Cardinal Spline 曲线插值模块，用于生成平滑曲线路径。Use when users need to (1) 生成平滑曲线/路径, (2) 相机沿路径移动, (3) NPC巡逻路线平滑化, (4) 赛道/轨道曲线生成, (5) 粒子/弹幕轨迹, (6) 2D/3D 样条插值, (7) smooth path / spline / curve interpolation, (8) 用户提到 cardinal spline 或 catmull-rom。
---

# Cardinal Spline 曲线插值

基于 [brookesi/6593166](https://gist.github.com/brookesi/6593166) 的 Cardinal Spline 算法，修复 bug 并适配 UrhoX。

## 与引擎内置功能的关系

> **引擎已内置 `Spline` 类和 `SplinePath` 组件**，覆盖大部分 3D 路径需求。
> 本模块定位为**补充方案**，用于引擎原生不便处理的场景。

### 选型指南

| 需求 | 推荐方案 |
|------|---------|
| 3D 节点沿路径移动（相机、NPC） | **引擎原生 `SplinePath`**（最简单，自动驱动） |
| 3D 取曲线上某点坐标 | **引擎原生 `Spline:GetPoint(t)`** |
| NanoVG 绘制 2D 平滑曲线 | **本模块 `getCurvePoints2D`**（引擎无此功能） |
| 需要自定义 tension 参数 | **本模块**（引擎 Catmull-Rom 固定 tension=0.5） |
| 纯数学计算、不想创建场景节点 | **本模块**（轻量，无场景依赖） |
| 批量预生成路径点数组 | **本模块 `getCurvePoints3D`**（一次生成全部点） |

### 引擎原生用法速查

```lua
-- 方式1: SplinePath 组件（最高层，自动驱动节点）
local pathComp = pathNode:CreateComponent("SplinePath")
pathComp.interpolationMode = CATMULL_ROM_CURVE
pathComp:AddControlPoint(point1Node)
pathComp:AddControlPoint(point2Node)
pathComp:AddControlPoint(point3Node)
pathComp.speed = 5.0
pathComp.controlledNode = cameraNode
-- 每帧调用 Move 即可
pathComp:Move(dt)

-- 方式2: Spline 类（底层，取点）
local spline = Spline.new(CATMULL_ROM_CURVE)
spline:AddKnot(Variant(Vector3(0,0,0)))
spline:AddKnot(Variant(Vector3(10,5,5)))
spline:AddKnot(Variant(Vector3(20,0,10)))
local pos = spline:GetPoint(0.5):GetVector3()  -- 取中点
```

---

## 本模块的独特价值

### 1. NanoVG 2D 曲线绘制（引擎无此功能）

引擎 `Spline`/`SplinePath` 面向 3D 场景节点，无法直接输出 flat array 供 NanoVG 使用。本模块的 `getCurvePoints2D` 专为此设计。

### 2. 可调 tension 参数

引擎内置 Catmull-Rom 等价于 tension=0.5，无法调整。本模块支持 0-1 范围自定义。

### 3. 无场景依赖的纯数学计算

不需要创建 Node、不需要挂组件，适合程序化生成、离线计算等场景。

---

## API

参考实现位于 `references/spline-module.lua`，包含三个核心函数：

| 函数 | 用途 | 输入 | 输出 |
|------|------|------|------|
| `getCurvePoints2D(points, tension, segments)` | 2D 曲线（NanoVG 专用） | flat array `{x1,y1,x2,y2,...}` | flat array |
| `getCurvePoints3D(points, tension, segments)` | 3D 曲线（批量预生成） | `{{x,y,z}, ...}` | `{{x,y,z}, ...}` |
| `getPointAt3D(points, t, tension)` | 取曲线上单点 | 控制点 + t(0-1) | `{x,y,z}` |

参数说明：
- **tension** (0-1): 张力。0=折线，0.5=平滑(默认)，1=非常圆滑
- **segments** (整数): 每段细分数，越大越平滑(默认 16)

## 使用方式

将 `references/spline-module.lua` 复制到用户 `scripts/` 目录，然后 require 使用。

### 核心场景：NanoVG 绘制平滑曲线

```lua
local CardinalSpline = require "CardinalSpline"

local controlPoints = {100,300, 200,100, 400,250, 600,80, 750,300}
local curve = CardinalSpline.getCurvePoints2D(controlPoints, 0.5, 20)

-- NanoVG 绘制
nvgBeginPath(vg)
nvgMoveTo(vg, curve[1], curve[2])
for i = 3, #curve, 2 do
    nvgLineTo(vg, curve[i], curve[i+1])
end
nvgStroke(vg)
```

### 辅助场景：3D 路径（不想用场景节点时）

> 如果可以使用场景节点，优先用引擎原生 `SplinePath` 组件。

```lua
local CardinalSpline = require "CardinalSpline"

local waypoints = {
    {x=0, y=2, z=0},
    {x=10, y=3, z=5},
    {x=20, y=1, z=15},
    {x=30, y=4, z=10},
}

-- 按参数 t 实时取点
local progress = 0
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    progress = math.min(progress + dt * 0.1, 1.0)
    local pos = CardinalSpline.getPointAt3D(waypoints, progress, 0.5)
    node.position = Vector3(pos.x, pos.y, pos.z)
end
```

## 原始代码 Bug 修复记录

原始 Gist 存在以下问题（已修复）：

1. **数组未克隆**: 引用赋值导致原始数组被修改
2. **table.insert 参数顺序错误**: value 和 position 写反
3. **循环边界错误**: padding 后索引计算不正确
4. **class() 语法错误**: 多余的 `end`

## 源代码

- 原始代码: `references/original-source.lua`
- 修复版模块: `references/spline-module.lua`
