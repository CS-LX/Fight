# RxLua - Reactive Extensions for Lua

> **来源**: [bjornbytes/RxLua](https://github.com/bjornbytes/RxLua)
> **作者**: Bjorn Swenson
> **协议**: MIT License
> **适用**: Lua 5.1+ (含 UrhoX Lua 5.4)

---

## LICENSE (MIT)

```
Copyright (c) 2015 Bjorn Swenson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 源码文件

本 skill 目录已包含 RxLua 完整源码，无需额外下载：

```
.claude/skills/rxlua/
├── SKILL.md      # 本文档（API 参考 + 游戏开发模式）
└── rx.lua        # RxLua v0.0.3 完整源码（2317 行，MIT 协议）
```

### 使用方式

将 `rx.lua` 复制到项目的 `scripts/` 目录即可使用：

```bash
cp .claude/skills/rxlua/rx.lua scripts/rx.lua
```

然后在游戏代码中：

```lua
local rx = require 'rx'

local obs = rx.Observable.of(1, 2, 3)
obs:map(function(x) return x * 2 end)
   :subscribe(print)
-- 输出: 2, 4, 6
```

> **注意**: AI 助手在用户需要 RxLua 时，应自动将 `rx.lua` 复制到 `scripts/` 目录，
> 用户无需手动操作。

---

## 概述

RxLua 是 ReactiveX (Rx) 的 Lua 实现，提供可组合的事件流处理能力。核心抽象：

| 概念 | 说明 |
|------|------|
| **Observable** | 可观察的数据/事件流，惰性求值 |
| **Observer** | 订阅者，接收 onNext / onError / onCompleted 回调 |
| **Subject** | 既是 Observable 又是 Observer，可手动 push 值 |
| **Scheduler** | 调度器，控制执行时机（同步/协程/定时器） |
| **Subscription** | 订阅句柄，调用 unsubscribe() 取消 |

---

## 何时使用此 Skill

当用户需要以下场景时触发：

1. 事件流组合/变换（多输入合并、节流防抖）
2. 响应式数据管道（map/filter/reduce 链）
3. 异步流控制（重试、超时、取消）
4. 游戏中复杂的事件编排（连击检测、combo 系统、输入缓冲）
5. 用户明确提到 "Rx"、"RxLua"、"Observable"、"响应式" 等关键词

---

## 核心 API

### 1. Observable 创建

```lua
local rx = require 'rx'

-- 从值创建
rx.Observable.of(1, 2, 3)

-- 从范围创建 (类似 for i = initial, limit, step)
rx.Observable.fromRange(1, 10)
rx.Observable.fromRange(0, 1, 0.1)

-- 从表创建
rx.Observable.fromTable({10, 20, 30}, ipairs)
rx.Observable.fromTable({a=1, b=2}, pairs, true) -- keys=true 同时发射 key

-- 从协程创建
rx.Observable.fromCoroutine(function()
    coroutine.yield(1)
    coroutine.yield(2)
    coroutine.yield(3)
end)

-- 自定义创建（最灵活）
rx.Observable.create(function(observer)
    observer:onNext('hello')
    observer:onNext('world')
    observer:onCompleted()
end)

-- 空/永不/错误
rx.Observable.empty()          -- 立即 complete
rx.Observable.never()          -- 永不产生值
rx.Observable.throw('oops')    -- 立即 error

-- defer: 每次订阅时重新创建
rx.Observable.defer(function()
    return rx.Observable.of(os.time())
end)

-- replicate: 重复值
rx.Observable.replicate('x', 5) -- 发射 5 次 'x'
```

### 2. 订阅 (subscribe)

```lua
local subscription = observable:subscribe(
    function(value) print('Next:', value) end,        -- onNext
    function(err) print('Error:', err) end,           -- onError (可选)
    function() print('Completed') end                 -- onCompleted (可选)
)

-- 取消订阅
subscription:unsubscribe()

-- 快捷调试
observable:dump('myStream')  -- 打印所有事件
```

### 3. 变换操作符 (Transformation)

```lua
-- map: 映射每个值
obs:map(function(x) return x * 2 end)

-- flatMap: 映射为 Observable 后展平（合并所有内部流）
obs:flatMap(function(x)
    return rx.Observable.of(x, x * 10)
end)

-- flatMapLatest: 只保留最近一次映射的内部流
obs:flatMapLatest(function(x)
    return someAsyncObservable(x)
end)

-- scan: 累积（每步都输出中间值）
obs:scan(function(acc, x) return acc + x end, 0)
-- 输入 1,2,3 输出 1,3,6

-- reduce: 累积（只输出最终值）
obs:reduce(function(acc, x) return acc + x end, 0)
-- 输入 1,2,3 输出 6

-- pack: 将多返回值打包为表
obs:pack()

-- unpack: 将表展开为多返回值
obs:unpack()

-- pluck: 提取表中的字段
obs:pluck('name')
-- {name='A'},{name='B'} -> 'A','B'

-- flatten: 展平嵌套 Observable
obs:flatten()

-- buffer: 收集 N 个值为一组
obs:buffer(3)
-- 1,2,3,4,5,6 -> {1,2,3},{4,5,6}

-- window: 类似 buffer 但输出子 Observable
obs:window(3)
```

### 4. 过滤操作符 (Filtering)

```lua
-- filter: 条件过滤
obs:filter(function(x) return x > 5 end)

-- reject: 反向过滤（排除匹配项）
obs:reject(function(x) return x > 5 end)

-- distinct: 去重
obs:distinct()

-- distinctUntilChanged: 连续去重（相邻相同才去除）
obs:distinctUntilChanged()

-- first / last: 只取首个/末尾值
obs:first()
obs:last()

-- take / takeLast: 取前 N / 后 N 个
obs:take(3)
obs:takeLast(2)

-- skip / skipLast: 跳过前 N / 后 N 个
obs:skip(2)
obs:skipLast(1)

-- takeWhile / skipWhile: 条件截取/跳过
obs:takeWhile(function(x) return x < 10 end)
obs:skipWhile(function(x) return x < 5 end)

-- takeUntil / skipUntil: 直到另一个 Observable 发射时截取/开始
obs:takeUntil(stopSignal)
obs:skipUntil(startSignal)

-- elementAt: 只取第 N 个元素
obs:elementAt(3)

-- find: 取第一个满足条件的值
obs:find(function(x) return x > 10 end)

-- contains: 判断流中是否包含某值（返回 true/false）
obs:contains(42)

-- compact: 移除 nil 值
obs:compact()

-- defaultIfEmpty: 空流时发射默认值
obs:defaultIfEmpty(0)

-- ignoreElements: 忽略所有值，只传递 error/completed
obs:ignoreElements()

-- sample: 按另一个 Observable 的节奏采样
obs:sample(timerObs)

-- debounce: 防抖 - 值发射后等待一段时间，无新值才输出
obs:debounce(200, scheduler)

-- delay: 延迟发射
obs:delay(100, scheduler)
```

### 5. 组合操作符 (Combination)

```lua
-- merge: 合并多个流（交错输出）
obs1:merge(obs2, obs3)
rx.Observable.merge(obs1, obs2)

-- concat: 串联多个流（顺序输出）
obs1:concat(obs2)

-- combineLatest: 任一流更新时，用所有流的最新值组合
obs1:combineLatest(obs2, function(a, b)
    return a + b
end)

-- zip: 按顺序一一配对
obs1:zip(obs2, function(a, b)
    return {a, b}
end)

-- amb: 取最先发射的流，忽略其余
obs1:amb(obs2, obs3)

-- startWith: 在流前插入值
obs:startWith(0)

-- with: 附加静态值
obs:with(extraValue1, extraValue2)

-- switch: 将 Observable-of-Observables 切换为只输出最新内部流
obs:switch()
```

### 6. 聚合操作符 (Aggregate)

```lua
-- count: 计数
obs:count()
obs:count(function(x) return x > 5 end) -- 满足条件的计数

-- sum / average / min / max
obs:sum()
obs:average()
obs:min()
obs:max()

-- all: 是否全部满足条件
obs:all(function(x) return x > 0 end)

-- partition: 按条件分为两个 Observable
local evens, odds = obs:partition(function(x) return x % 2 == 0 end)
```

### 7. 错误处理

```lua
-- catch: 捕获错误，切换到备用流
obs:catch(function(err)
    return rx.Observable.of('fallback')
end)

-- retry: 出错时重新订阅（重试 N 次）
obs:retry(3)
```

### 8. 副作用

```lua
-- tap: 不改变流，仅执行副作用（调试/日志）
obs:tap(function(x) print('DEBUG:', x) end)
   :map(function(x) return x * 2 end)
   :subscribe(print)
```

---

## Subject（主题）

Subject 既是 Observable（可被订阅），又是 Observer（可被推值）。

### Subject 类型

| 类型 | 行为 |
|------|------|
| Subject | 基础：只广播订阅后的新值 |
| BehaviorSubject | 缓存最新值：新订阅者立即收到最新值 |
| ReplaySubject | 缓存历史：新订阅者收到最近 N 个历史值 |
| AsyncSubject | 只在 complete 时发射最后一个值 |

```lua
-- Subject: 事件总线
local subject = rx.Subject.create()
subject:subscribe(function(v) print(v) end)
subject:onNext('hello')  -- 输出: hello
subject:onNext('world')  -- 输出: world

-- BehaviorSubject: 状态容器（类似 React state）
local hp = rx.BehaviorSubject.create(100)
hp:subscribe(function(v) print('HP:', v) end) -- 立即输出: HP: 100
hp:onNext(80)   -- 输出: HP: 80
hp:getValue()   -- 返回 80

-- ReplaySubject: 聊天记录/回放
local chat = rx.ReplaySubject.create(10) -- 缓存最近 10 条
chat:onNext('msg1')
chat:onNext('msg2')
chat:subscribe(function(v) print(v) end) -- 输出: msg1, msg2（收到历史）
```

---

## Scheduler（调度器）

### ImmediateScheduler（默认）

同步立即执行，无延迟。

```lua
local scheduler = rx.ImmediateScheduler.create()
scheduler:schedule(function() print('now\!') end)
```

### CooperativeScheduler（游戏常用）

基于虚拟时钟的协程调度器，需要手动调用 update(dt) 推进时间。

```lua
local scheduler = rx.CooperativeScheduler.create()

-- 安排延迟任务
scheduler:schedule(function() print('after 1s') end, 1.0)
scheduler:schedule(function() print('after 2s') end, 2.0)

-- 在游戏循环中推进时间
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    scheduler:update(dt)
end

-- 配合 debounce / delay 等时间操作符
obs:debounce(0.5, scheduler)  -- 0.5 秒防抖
obs:delay(1.0, scheduler)     -- 延迟 1 秒
```

---

## UrhoX 游戏开发实战模式

### 模式 1: 输入事件流

```lua
local rx = require 'rx'
local scheduler = rx.CooperativeScheduler.create()

-- 用 Subject 包装引擎事件
local touchSubject = rx.Subject.create()
local updateSubject = rx.Subject.create()

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    updateSubject:onNext(dt)
    scheduler:update(dt)
end

function HandleTouchBegin(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    touchSubject:onNext({x = x, y = y, time = os.clock()})
end

-- 双击检测：buffer 收集 2 个点击，判断时间间隔
local doubleClick = touchSubject
    :buffer(2)
    :filter(function(clicks)
        return (clicks[2].time - clicks[1].time) < 0.5
    end)

doubleClick:subscribe(function(clicks)
    print('Double click detected\!')
end)
```

### 模式 2: 状态管理 (BehaviorSubject)

```lua
local rx = require 'rx'

-- 游戏状态
local score$ = rx.BehaviorSubject.create(0)
local hp$ = rx.BehaviorSubject.create(100)
local combo$ = rx.BehaviorSubject.create(0)

-- 分数变化时更新 UI
score$:subscribe(function(score)
    scoreLabel:SetText("Score: " .. score)
end)

-- HP 变化联动效果
hp$:map(function(v) return v / 100 end)
   :distinctUntilChanged()
   :subscribe(function(ratio)
       hpBar:SetWidth(ratio * barMaxWidth)
       if ratio < 0.3 then
           StartLowHPEffect()
       end
   end)

-- 推送新值
function AddScore(points)
    local current = score$:getValue()
    score$:onNext(current + points)
end
```

### 模式 3: 连击系统 (Combo)

```lua
local rx = require 'rx'
local scheduler = rx.CooperativeScheduler.create()

local hitSubject = rx.Subject.create()

-- 2 秒内无新命中则 combo 重置
local comboReset = hitSubject:debounce(2.0, scheduler)

local comboCount = 0

hitSubject:subscribe(function()
    comboCount = comboCount + 1
    UpdateComboUI(comboCount)
end)

comboReset:subscribe(function()
    comboCount = 0
    UpdateComboUI(0)
end)

-- 游戏循环中推进调度器
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    scheduler:update(dt)
end

-- 命中时触发
function OnEnemyHit()
    hitSubject:onNext(true)
end
```

### 模式 4: 冷却时间 / 技能系统

```lua
local rx = require 'rx'
local scheduler = rx.CooperativeScheduler.create()

local skillSubject = rx.Subject.create()
local canCast = true

skillSubject
    :filter(function() return canCast end)
    :subscribe(function(skillId)
        canCast = false
        CastSkill(skillId)
        -- 3 秒后恢复
        scheduler:schedule(function()
            canCast = true
        end, 3.0)
    end)

function OnSkillButtonPressed(skillId)
    skillSubject:onNext(skillId)
end
```

### 模式 5: 组合多数据源

```lua
local rx = require 'rx'

local playerPos$ = rx.BehaviorSubject.create(Vector3.ZERO)
local cameraYaw$ = rx.BehaviorSubject.create(0)
local speed$ = rx.BehaviorSubject.create(5.0)

-- 当任意一个改变时，重新计算移动方向
rx.Observable.combineLatest(playerPos$, cameraYaw$, speed$,
    function(pos, yaw, speed)
        return { pos = pos, yaw = yaw, speed = speed }
    end)
    :distinctUntilChanged()
    :subscribe(function(state)
        UpdateCharacterMovement(state)
    end)
```

### 模式 6: 事件流清理

```lua
-- 保存所有订阅，统一清理
local subscriptions = {}

function Start()
    table.insert(subscriptions,
        score$:subscribe(function(s) UpdateScoreUI(s) end)
    )
    table.insert(subscriptions,
        hp$:subscribe(function(h) UpdateHPUI(h) end)
    )
end

function Stop()
    for _, sub in ipairs(subscriptions) do
        sub:unsubscribe()
    end
    subscriptions = {}
end
```

---

## 操作符速查表

### 创建类

| 操作符 | 说明 |
|--------|------|
| create(fn) | 自定义创建 |
| of(...) | 从参数创建 |
| fromRange(a,b,step) | 范围 |
| fromTable(t,iter,keys) | 从表 |
| fromCoroutine(fn) | 从协程 |
| empty() | 空流 |
| never() | 永不完成 |
| throw(msg) | 立即错误 |
| defer(factory) | 延迟创建 |
| replicate(val,n) | 重复值 |

### 变换类

| 操作符 | 说明 |
|--------|------|
| map(fn) | 映射 |
| flatMap(fn) | 映射+展平 |
| flatMapLatest(fn) | 映射+只保留最新 |
| scan(fn,seed) | 累积（输出中间值） |
| reduce(fn,seed) | 累积（只输出最终值） |
| buffer(n) | 缓冲为组 |
| window(n) | 缓冲为子流 |
| pluck(key) | 提取字段 |
| pack() | 多值打包为表 |
| unpack() | 表展开为多值 |
| unwrap() | 解包装 |
| flatten() | 展平嵌套 |

### 过滤类

| 操作符 | 说明 |
|--------|------|
| filter(fn) | 条件保留 |
| reject(fn) | 条件排除 |
| distinct() | 全局去重 |
| distinctUntilChanged() | 连续去重 |
| first() / last() | 首/末值 |
| take(n) / takeLast(n) | 取前/后 N 个 |
| skip(n) / skipLast(n) | 跳前/后 N 个 |
| takeWhile(fn) / skipWhile(fn) | 条件截取/跳过 |
| takeUntil(obs) / skipUntil(obs) | 信号截取/跳过 |
| elementAt(n) | 第 N 个 |
| find(fn) | 首个匹配 |
| contains(val) | 包含判断 |
| compact() | 移除 nil |
| defaultIfEmpty(val) | 空流默认值 |
| debounce(t,sched) | 防抖 |
| delay(t,sched) | 延迟 |
| sample(obs) | 采样 |

### 组合类

| 操作符 | 说明 |
|--------|------|
| merge(...) | 合并（交错） |
| concat(...) | 串联（顺序） |
| combineLatest(...,fn) | 最新值组合 |
| zip(...,fn) | 一一配对 |
| amb(...) | 竞速（取最快） |
| startWith(...) | 前置值 |
| with(...) | 附加值 |
| switch() | 切换最新内部流 |

### 聚合类

| 操作符 | 说明 |
|--------|------|
| count(fn?) | 计数 |
| sum() / average() | 求和/平均 |
| min() / max() | 最值 |
| all(fn) | 全部满足 |
| partition(fn) | 分区为两流 |

### 错误/副作用

| 操作符 | 说明 |
|--------|------|
| catch(fn) | 错误恢复 |
| retry(n) | 重试 |
| tap(fn) | 副作用（不改变流） |

---

## 注意事项

1. **RxLua 是纯 Lua 库**，无 C 依赖，可直接放入 scripts/ 使用
2. **CooperativeScheduler 需手动 update**：在 HandleUpdate 中调用 scheduler:update(dt)
3. **内存管理**：长期运行的订阅必须在适当时机 unsubscribe()，避免内存泄漏
4. **Subject 不是万能的**：优先用 Observable 工厂函数，只在需要外部 push 时用 Subject
5. **链式调用**：所有操作符返回新 Observable，原始流不变（不可变数据流）
6. **冷 Observable vs 热 Observable**：
   - 冷（Cold）：每次订阅重新执行（如 fromRange）
   - 热（Hot）：所有订阅者共享（如 Subject）

---

## 参考链接

- 源码仓库: https://github.com/bjornbytes/RxLua
- ReactiveX 官方: http://reactivex.io/
- 操作符可视化: https://rxmarbles.com/
