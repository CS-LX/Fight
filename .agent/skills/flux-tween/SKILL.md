---
name: flux-tween
description: |
  纯 Lua 缓动/补间动画库（30+ 缓动函数），支持链式调用、延迟、回调、分组，适用于 UI 动画和游戏对象运动。
  Use when users need to (1) UI 元素缓动动画（淡入淡出/滑动/弹跳）, (2) 游戏对象平滑移动/缩放/旋转,
  (3) 补间动画/缓动函数, (4) 连续动画链/序列动画, (5) tween / easing / interpolation,
  (6) 用户提到缓动、补间、tween、easing 或平滑过渡, (7) 需要非物理驱动的数值平滑变化。
---

# flux — 轻量缓动/补间动画库

> **作者**: [rxi](https://github.com/rxi)
> **来源**: https://github.com/rxi/flux
> **许可证**: MIT
> **版本**: 0.1.5
> **体积**: 224 行，零依赖，纯 Lua 5.4 兼容

---

## 概述

flux 是一个极简的 Lua 补间（tween）动画库，专为游戏设计。它支持 30+ 种缓动函数，自动处理属性冲突，支持链式调用和回调。

**核心优势**：
- 30+ 缓动类型（quad/cubic/quart/quint/expo/sine/circ/back/elastic × in/out/inout）
- 自动属性冲突解决（同一对象同一属性只保留最新 tween）
- 链式序列动画（`:after()`）
- 分组管理（`flux.group()`）
- 每帧一次 `flux.update(dt)` 即可驱动所有动画

---

## 安装

将 `src/flux.lua` 复制到项目 `scripts/` 目录：

```
scripts/
├── main.lua
└── libs/
    └── flux.lua
```

```lua
local flux = require "libs.flux"
```

---

## API 参考

### 核心函数

| 函数 | 说明 |
|------|------|
| `flux.to(obj, time, vars)` | 创建补间，将 obj 的属性在 time 秒内变化到 vars 中指定的目标值 |
| `flux.update(dt)` | 驱动所有补间前进 dt 秒（每帧调用一次） |

### Tween 方法（链式调用）

| 方法 | 说明 |
|------|------|
| `:ease(name)` | 设置缓动函数，默认 `"quadout"` |
| `:delay(seconds)` | 延迟 N 秒后开始 |
| `:oncomplete(fn)` | 完成时回调 |
| `:onstart(fn)` | 开始时回调（delay 之后） |
| `:onupdate(fn)` | 每帧更新时回调 |
| `:after(obj, time, vars)` | 当前 tween 完成后创建新 tween（链式序列） |
| `:after(time, vars)` | 同上，复用同一 obj |
| `:stop()` | 立即停止此 tween |

### 分组

```lua
local group = flux.group()
group:to(obj, 1, { x = 100 })
group:update(dt)  -- 只更新此组
```

### 缓动函数列表

每种基础缓动都有 `in`/`out`/`inout` 三个变体：

| 基础名 | 效果 |
|--------|------|
| `linear` | 匀速（无加减速） |
| `quad` | 二次方 |
| `cubic` | 三次方 |
| `quart` | 四次方 |
| `quint` | 五次方 |
| `expo` | 指数 |
| `sine` | 正弦 |
| `circ` | 圆形 |
| `back` | 回弹（超出后回来） |
| `elastic` | 弹性振荡 |

使用方式：`"quadin"`, `"quadout"`, `"quadinout"`, `"backin"`, `"elasticout"` 等。

---

## UrhoX 集成模式

### 基础用法 — UI 动画

```lua
local flux = require "libs.flux"

-- 定义一个可动画的对象（普通 table 即可）
local panel = { x = -200, y = 300, alpha = 0 }

function Start()
    -- 面板从左侧滑入 + 淡入，使用 back 缓动
    flux.to(panel, 0.6, { x = 100, alpha = 1 }):ease("backout")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    flux.update(dt)  -- 每帧驱动所有 tween
end
```

### 序列动画 — 连续动作

```lua
-- 物体先移到 A 点，再移到 B 点，最后淡出
flux.to(obj, 0.5, { x = 100 })
    :ease("cubicout")
    :after(0.5, { y = 200 })
    :ease("sineinout")
    :after(0.3, { alpha = 0 })
    :oncomplete(function()
        print("动画序列完成！")
    end)
```

### 游戏对象运动 — 配合 Node

```lua
-- 将 UrhoX Node 的位置包装为可动画 table
local enemyAnim = { x = 0, y = 5, z = 0 }

-- 敌人从起点移动到终点
flux.to(enemyAnim, 2.0, { x = 10, z = 8 }):ease("sineinout")

-- 在 Update 中同步到 Node
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    flux.update(dt)
    enemyNode.position = Vector3(enemyAnim.x, enemyAnim.y, enemyAnim.z)
end
```

### 相机震动（配合随机偏移）

```lua
local camShake = { offsetX = 0, offsetY = 0 }

function ShakeCamera(intensity)
    camShake.offsetX = (math.random() - 0.5) * intensity
    camShake.offsetY = (math.random() - 0.5) * intensity
    -- 快速衰减回零
    flux.to(camShake, 0.3, { offsetX = 0, offsetY = 0 }):ease("elasticout")
end
```

### 分组管理 — UI 与游戏分离

```lua
local uiTweens = flux.group()    -- UI 动画组（暂停游戏时仍播放）
local gameTweens = flux.group()  -- 游戏动画组（暂停时停止）

-- UI 动画
uiTweens:to(button, 0.2, { scale = 1.1 }):ease("backout")

-- 游戏动画
gameTweens:to(enemy, 1.0, { x = targetX }):ease("linear")

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    uiTweens:update(dt)         -- UI 始终更新
    if not paused then
        gameTweens:update(dt)   -- 游戏暂停时不更新
    end
end
```

---

## 注意事项

1. **只能补间数值属性**：`vars` 中的值必须是 number 类型
2. **对象属性冲突自动解决**：对同一对象同一属性创建新 tween 会自动取消旧的
3. **不要直接修改 UrhoX 组件属性**：flux 只能操作 Lua table，需要在 Update 中手动同步到 Node/Component
4. **`flux.update(dt)` 必须每帧调用**：否则动画不会推进

---

## 文件清单

```
.claude/skills/flux-tween/
├── SKILL.md          # 本文件
├── LICENSE           # MIT 许可证
└── src/
    └── flux.lua      # 源码（224 行）
```
