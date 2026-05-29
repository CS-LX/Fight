---
name: tick-timer
description: |
  纯 Lua 定时器/调度器库，支持延迟执行、循环定时、链式调度，适用于游戏中的倒计时、技能冷却、波次生成。
  Use when users need to (1) 延迟执行/定时回调, (2) 技能冷却/CD 计时, (3) 波次生成/定时刷怪,
  (4) 倒计时/计时器, (5) 循环定时任务, (6) timer / scheduler / delay / cooldown,
  (7) 用户提到定时器、延迟执行、冷却时间或调度。
---

# tick — 轻量定时器/调度器库

> **作者**: [rxi](https://github.com/rxi)
> **来源**: https://github.com/rxi/tick
> **许可证**: MIT
> **版本**: 0.1.1
> **体积**: 166 行，零依赖，纯 Lua 5.4 兼容

---

## 概述

tick 是一个极简的 Lua 定时器库，专为游戏的帧驱动模型设计。支持一次性延迟、循环定时、链式调度，并自动处理时间误差累积。

**核心优势**：
- 一次性延迟（`delay`）和循环定时（`recur`）
- 链式调度（`:after()`）— 上一个完成后自动触发下一个
- 自动时间误差补偿 — 不会因帧率波动丢失精度
- 分组管理（`tick.group()`）— 暂停/恢复不同组
- 每帧一次 `tick.update(dt)` 驱动

---

## 安装

将 `src/tick.lua` 复制到项目 `scripts/` 目录：

```
scripts/
├── main.lua
└── libs/
    └── tick.lua
```

```lua
local tick = require "libs.tick"
```

---

## API 参考

### 核心函数

| 函数 | 说明 |
|------|------|
| `tick.delay(fn, seconds)` | 延迟 N 秒后执行 fn（一次性） |
| `tick.recur(fn, seconds)` | 每隔 N 秒执行 fn（循环） |
| `tick.update(dt)` | 驱动所有定时器前进 dt 秒（每帧调用） |
| `tick.group()` | 创建独立定时器组 |

### Event 方法

| 方法 | 说明 |
|------|------|
| `event:after(fn, seconds)` | 当前事件触发后，再延迟 N 秒执行 fn |
| `event:stop()` | 停止/取消此定时器 |

### 分组

```lua
local group = tick.group()
group:delay(fn, 2.0)
group:recur(fn, 0.5)
group:update(dt)
```

---

## UrhoX 集成模式

### 基础用法 — 延迟与循环

```lua
local tick = require "libs.tick"

function Start()
    -- 3 秒后显示提示
    tick.delay(function()
        print("3 秒已到！")
    end, 3.0)

    -- 每 2 秒刷一波敌人
    tick.recur(function()
        SpawnEnemyWave()
    end, 2.0)
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    tick.update(dt)
end
```

### 链式调度 — 序列事件

```lua
-- 开场动画序列：等 1 秒 → 显示标题 → 等 2 秒 → 显示按钮
tick.delay(function()
    ShowTitle()
end, 1.0)
:after(function()
    ShowPlayButton()
end, 2.0)
:after(function()
    EnableInput()
end, 0.5)
```

### 技能冷却系统

```lua
local tick = require "libs.tick"

local skills = {}
local cooldowns = {}

function UseSkill(name, cooldownTime)
    if cooldowns[name] then return end  -- 冷却中

    -- 执行技能
    print(name .. " 释放！")
    cooldowns[name] = true

    -- 冷却结束后解锁
    tick.delay(function()
        cooldowns[name] = nil
        print(name .. " 冷却完毕")
    end, cooldownTime)
end
```

### 波次生成器

```lua
local tick = require "libs.tick"
local waveTimer = nil
local waveNum = 0

function StartWaves()
    waveTimer = tick.recur(function()
        waveNum = waveNum + 1
        local count = 3 + waveNum * 2
        for i = 1, count do
            -- 每个敌人延迟一点出现，形成「涌入」效果
            tick.delay(function()
                SpawnEnemy(waveNum)
            end, i * 0.2)
        end
    end, 5.0)
end

function StopWaves()
    if waveTimer then
        waveTimer:stop()
        waveTimer = nil
    end
end
```

### 分组管理 — 暂停支持

```lua
local tick = require "libs.tick"
local gameTimers = tick.group()   -- 游戏逻辑定时器
local uiTimers = tick.group()     -- UI 定时器（暂停时仍运行）

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    uiTimers:update(dt)           -- UI 始终更新
    if not paused then
        gameTimers:update(dt)     -- 游戏暂停时冻结
    end
end

-- 游戏逻辑用 gameTimers
gameTimers:recur(function() SpawnEnemy() end, 2.0)

-- UI 动画用 uiTimers
uiTimers:delay(function() ShowNotification() end, 1.0)
```

### 倒计时 UI

```lua
local tick = require "libs.tick"
local countdown = { seconds = 60 }

function StartCountdown(totalSeconds, onFinish)
    countdown.seconds = totalSeconds
    tick.recur(function()
        countdown.seconds = countdown.seconds - 1
        UpdateCountdownUI(countdown.seconds)
        if countdown.seconds <= 0 then
            onFinish()
        end
    end, 1.0)
end
```

---

## 注意事项

1. **`tick.update(dt)` 必须每帧调用**：否则定时器不会推进
2. **循环事件不能链式 `:after()`**：只有一次性 `delay` 事件支持 `:after()` 链
3. **回调中可以安全创建新定时器**：tick 内部处理了嵌套调用
4. **时间误差自动补偿**：如果帧率低导致某次 dt 很大，tick 会正确触发期间所有到期事件
5. **`:stop()` 立即生效**：停止后的事件不会再被触发

---

## 文件清单

```
.claude/skills/tick-timer/
├── SKILL.md          # 本文件
├── LICENSE           # MIT 许可证
└── src/
    └── tick.lua      # 源码（166 行）
```
