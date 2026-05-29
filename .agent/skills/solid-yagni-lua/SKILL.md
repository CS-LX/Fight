---
name: solid-yagni-lua
description: |
  UrhoX Lua 游戏项目的架构设计原则：SOLID 面向对象设计 + YAGNI 极简实现策略的平衡指南。
  Use when users need to (1) 重构或优化代码结构, (2) 决定是否拆分模块/引入抽象层,
  (3) 评估当前代码是否过度设计或设计不足, (4) 模块间耦合度过高需要解耦,
  (5) 项目逐渐变大需要架构升级策略, (6) solid yagni 设计原则,
  (7) 用户说"代码太乱了"/"改一个地方到处崩"/"这个以后可能要用到"类似的架构焦虑。
---

# SOLID + YAGNI：UrhoX Lua 架构设计指南

## 核心哲学

> **把路修平、把地留好（SOLID），但别提前盖没人住的楼（YAGNI）。**

在 UrhoX Lua 游戏开发中：
- **SOLID** 确保代码可维护、可扩展——改一个功能不会引发连锁崩溃
- **YAGNI** 确保开发效率——不为假想需求写代码，不为"万一"增加复杂度

## 原则适配：Lua 游戏语境下的 SOLID

Lua 不是严格 OOP 语言，没有 interface/abstract class，但 SOLID 的设计思想完全适用。以下是 UrhoX Lua 项目中的具体映射：

---

### S — 单一职责（Single Responsibility）

> **一个模块文件只管一件事，一个函数只做一个动作。**

#### 🔴 规则 1：模块按职责拆分

| 职责 | 独立模块 | 反例（违反 SRP） |
|------|----------|------------------|
| 赛道生成与管理 | `track.lua` | 把赛道生成和碰撞检测写在 main.lua |
| 玩家物理模拟 | `boatphys.lua` | 在 boat.lua 里同时处理渲染和物理 |
| UI 显示与交互 | `ui.lua` | 在 main.lua 里直接操作 UI 控件 |
| 游戏状态数据 | `state.lua` | 各模块各自维护自己的状态变量 |
| 配置常量 | `config.lua` | 魔法数字散落在各个文件 |

#### 判断标准

问自己：**"这个模块有几个被修改的理由？"**

- 1 个理由 → 职责单一，合格
- 2+ 个理由 → 需要拆分

```lua
-- ❌ 违反 SRP：camera.lua 同时负责相机跟随 + 屏幕震动 + 后处理特效
-- ✅ 合规：camera.lua 只负责相机跟随和视角，震动作为独立行为可以内聚在同文件
--          但后处理特效应该拆到 postprocess.lua
```

#### Lua 特色：函数也是第一对象

```lua
-- 当一个函数超过 50 行时，考虑拆分为多个小函数
-- 当一个文件超过 400 行时，考虑是否混入了不同职责
```

---

### O — 开闭原则（Open-Closed）

> **对扩展开放，对修改关闭：加新关卡/新障碍物不需要改已有代码。**

#### 🔴 规则 2：数据驱动 > 硬编码分支

```lua
-- ❌ 违反 OCP：每次加新障碍物都要改这个函数
function SpawnObstacle(type)
    if type == "buoy" then
        -- 40 行代码...
    elseif type == "log" then
        -- 40 行代码...
    elseif type == "rock" then
        -- 40 行代码...
    end
end

-- ✅ 合规：用配置表 + 通用逻辑
local ObstacleTypes = {
    buoy     = { model = "Models/Buoy.mdl",  scale = 1.0, damage = 0.15 },
    log      = { model = "Models/Log.mdl",   scale = 1.5, damage = 0.20 },
    rock     = { model = "Models/Rock.mdl",  scale = 2.0, damage = 0.30 },
    -- 新增只加一行，SpawnObstacle 逻辑不变
}

function SpawnObstacle(type)
    local cfg = ObstacleTypes[type]
    if not cfg then return end
    local node = scene:CreateChild(type)
    node:SetScale(cfg.scale)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", cfg.model))
    -- 通用逻辑...
end
```

#### 适用场景

| 场景 | OCP 方案 |
|------|----------|
| 多种障碍物/敌人 | 配置表 + 通用生成函数 |
| 多关卡参数 | `levels.lua` 关卡数组 |
| 多种 UI 界面 | 状态机 + 每状态独立渲染函数 |
| 多种音效/特效 | 资源路径表 + 通用播放函数 |

---

### L — 里氏替换（Liskov Substitution）

> **子模块能无缝替换父模块的接口契约。**

在 Lua 中没有继承层级，但等价思想是：**模块间的接口契约必须一致**。

#### 🔴 规则 3：同类模块必须遵守相同接口

```lua
-- 如果 buildings.lua 有 Init/Update/Reset/ClearAll
-- 那么 vegetation.lua 也必须有同样的四个函数
-- 调用方（main.lua）可以统一循环处理，不需要特殊判断

-- ✅ 合规：所有装饰子系统接口一致
local decorSystems = { Buildings, Vegetation, Obstacles, Coins }

function ClearAllDecor()
    for _, sys in ipairs(decorSystems) do
        sys.ClearAll()  -- 每个模块都保证有这个方法
    end
end
```

#### 判断标准

如果你发现调用方代码中出现了 `if module == X then` 的类型判断来区分调用方式，说明接口不统一——违反了 LSP。

---

### I — 接口隔离（Interface Segregation）

> **调用方只看到它需要的函数，不要暴露无关 API。**

#### 🔴 规则 4：模块返回值只暴露必要接口

```lua
-- ❌ 违反 ISP：暴露了所有内部函数
-- boat.lua
return {
    Init = Init,
    Update = Update,
    Steer = Steer,
    Jump = Jump,
    Reset = Reset,
    _internalCalcDrag = calcDrag,      -- 内部函数不应暴露
    _debugNodes = debugNodeList,        -- 调试数据不应暴露
    _physicsState = physState,          -- 内部状态不应暴露
}

-- ✅ 合规：只暴露外部需要的公共 API
local M = {}
M.Init   = Init
M.Update = Update
M.Steer  = Steer
M.Jump   = Jump
M.Reset  = Reset
return M
```

#### Lua 惯用法

```lua
-- 用 local 隐藏内部实现
local function internalHelper()  -- 外部不可见
    -- ...
end

local M = {}
function M.PublicAPI()  -- 外部可见
    internalHelper()
end
return M
```

---

### D — 依赖倒置（Dependency Inversion）

> **高层逻辑不直接依赖底层细节；通过注入/回调解耦。**

#### 🔴 规则 5：模块间通信用回调/事件，不用硬引用

```lua
-- ❌ 违反 DIP：boatphys.lua 直接 require 并调用 ui.lua
-- boatphys.lua
local UI = require "ui"
function OnCollision()
    UI.ShowDamageFlash()  -- 物理模块硬依赖 UI 模块
end

-- ✅ 合规方案 A：回调注入
-- boatphys.lua
local onDamageCallback = nil
function M.SetOnDamage(fn) onDamageCallback = fn end
function OnCollision()
    if onDamageCallback then onDamageCallback("wall") end
end

-- main.lua（组装层）
BoatPhys.SetOnDamage(function(source)
    UI.ShowDamageFlash()
    TakeDurabilityHit(source)
end)

-- ✅ 合规方案 B：通过共享状态解耦
-- boatphys.lua 只写 State
State.lastDamageSource = "wall"
State.lastDamageTime   = time

-- ui.lua 读 State 并响应
if State.lastDamageTime > lastChecked then
    ShowDamageFlash()
end
```

#### UrhoX 项目中的依赖方向

```
main.lua（组装层/胶水层）
  |---> state.lua   （共享数据，无逻辑依赖）
  |---> config.lua  （常量，无逻辑依赖）
  |---> track.lua   （核心逻辑）
  |---> boat.lua    （玩家逻辑）
  |---> ui.lua      （展示逻辑）
  +---> ...

正确依赖方向：main -> 各模块 -> state/config
错误依赖方向：ui -> boatphys（同层模块互相引用）
```

---

## YAGNI：什么时候不该用 SOLID

### 🔴 规则 6：三行法则（Rule of Three）

> **当且仅当同一模式出现三次时，才抽象它。**

```lua
-- 只有 1 种障碍物时：
-- ❌ 过度设计：定义 ObstacleFactory、ObstacleConfig、ObstaclePool...
-- ✅ YAGNI：直接在 obstacles.lua 里写死逻辑

-- 有 3+ 种障碍物时：
-- ✅ 该抽象了：提取配置表 + 通用生成函数
```

### 🔴 规则 7：不为假想需求编码

| 假想 | YAGNI 回应 |
|------|-----------|
| "以后可能需要联网对战" | 先做单机，联网时再按 network-game-guide.md 重构 |
| "以后可能加 100 个关卡" | 先做 3 关，确认关卡表结构没问题即可 |
| "以后可能换物理引擎" | 不要提前抽象 PhysicsInterface |
| "以后可能支持换肤" | 不要现在就建主题系统 |

### 🔴 规则 8：复杂度预算

| 项目阶段 | 代码行数 | 架构级别 |
|----------|----------|----------|
| 原型验证 | < 500 行 | 单文件，无需模块化 |
| 功能完善 | 500-1500 行 | 核心模块拆分（state/config/主逻辑） |
| 持续迭代 | 1500+ 行 | 完整模块化（本项目当前阶段） |
| 大型项目 | 5000+ 行 | 分层架构 + 事件总线 |

---

## 实操决策树

遇到"要不要抽象/拆分/提前设计"的问题时：

```
需要新功能
  |
  +-- 这个功能现在就要用吗？
  |   +-- 否 --> STOP（YAGNI：不写）
  |   +-- 是 |
  |           v
  +-- 已有代码中，这个模式出现了 3 次吗？
  |   +-- 否 --> 直接写，内联实现（YAGNI：不过早抽象）
  |   +-- 是 |
  |           v
  +-- 提取为独立函数/模块
      |
      +-- 这个模块只有一个变化原因吗？（SRP）
      |   +-- 否 --> 继续拆分
      |
      +-- 加新变体时需要改已有代码吗？（OCP）
      |   +-- 是 --> 改为配置表驱动
      |
      +-- 模块间有循环引用吗？（DIP）
      |   +-- 是 --> 引入共享 state 或回调
      |
      +-- 完成
```

---

## 本项目架构评估

以当前海河竞速项目为例，评估 SOLID 合规度：

| 原则 | 状态 | 说明 |
|------|------|------|
| SRP | 合格 | 20+ 模块各司其职（track/boat/camera/ui 等） |
| OCP | 合格 | 关卡用 levels.lua 配置表驱动 |
| LSP | 合格 | 装饰系统（buildings/vegetation）接口统一 |
| ISP | 合格 | 各模块只暴露 Init/Update/Reset 公共 API |
| DIP | 注意 | TakeDurabilityHit 全局函数是隐式依赖 |
| YAGNI | 合格 | 没有过度抽象，没有未使用的"扩展框架" |

---

## 重构信号

当你看到以下症状时，说明需要应用 SOLID 进行重构：

| 症状 | 违反原则 | 处方 |
|------|----------|------|
| "改一个功能，三个文件跟着崩" | DIP 违反 | 引入共享 state/回调解耦 |
| "加新种类要改 5 个 if-else" | OCP 违反 | 改为配置表驱动 |
| "这个文件 2000 行了" | SRP 违反 | 按职责拆分为 3-5 个文件 |
| "同样的代码复制了三处" | 缺少抽象 | 提取为公共函数 |
| "接口太多，大部分用不到" | ISP 违反 | 拆分为更小的接口表 |

## 反重构信号（YAGNI 守护）

当你感到"应该提前抽象"时，问自己：

| 问题 | 如果答案是"否" |
|------|---------------|
| 这个抽象现在就能减少代码量吗？ | 不抽象 |
| 去掉这个抽象，当前功能会受影响吗？ | 不抽象 |
| 一周内会有第三个使用者吗？ | 不抽象 |
| 不做这个，改起来真的很难吗？ | 不抽象 |

---

## 设计清单

在每次较大的重构或新模块设计前确认：

- [ ] 新模块是否只有**一个**被修改的理由（SRP）
- [ ] 新增变体/类型时是否只需加配置不改逻辑（OCP）
- [ ] 同类模块的公共接口是否一致（LSP）
- [ ] 模块是否只暴露了调用方需要的函数（ISP）
- [ ] 模块间是否通过 state/回调通信而非直接引用（DIP）
- [ ] 这个抽象是**现在需要**还是**以后可能需要**（YAGNI）
- [ ] 代码行数是否在当前阶段的合理范围内（复杂度预算）

## 一句话总结

**写能跑的最简代码（YAGNI），但让它的结构天然支持变化（SOLID）。不多做一步，也不少想一层。**
