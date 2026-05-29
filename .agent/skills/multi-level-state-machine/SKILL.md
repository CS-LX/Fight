---
name: multi-level-state-machine
description: |
  多关卡游戏的状态机设计与场景完整清理策略，确保切换关卡时无残留对象。
  Use when users need to (1) 实现多关卡/多级别的游戏切换系统, (2) 确保切换关卡时场景完全清理,
  (3) 设计 gameState 状态机（levelselect/playing/gameover）, (4) 关卡参数热切换（宽度/速度/难度）,
  (5) 区分 Reset/Reinit/ClearAll 三种场景操作的使用时机, (6) multi-level state machine,
  (7) 用户反馈"切换关卡时前一关的物体没有消失"类似的残留问题。
---

# 多关卡状态机与场景清理（Multi-Level State Machine）

## 核心问题

多关卡游戏中存在三种不同的"重置"需求，如果混淆会导致：
- 切换关卡后旧地形/物体仍然可见（最常见 bug）
- 重新开始后物理状态残留
- 返回主菜单后内存未释放

## 解决方案：三级操作 + 状态机

### 状态机定义

```
┌──────────────┐    SelectLevel(idx)    ┌──────────┐
│  levelselect │ ───────────────────── → │ playing  │
└──────────────┘                         └──────────┘
       ↑                                      │
       │         BackToLevelSelect()          │
       ├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤
       │                                      ↓
       │         BackToLevelSelect()    ┌──────────┐
       └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤ gameover │
                                        └──────────┘
                                              │
                                    Retry()   │ (同关卡重来)
                                              ↓
                                        ┌──────────┐
                                        │ playing  │
                                        └──────────┘
```

### 三级操作对比

| 操作 | 含义 | 场景节点 | 状态数据 | 使用时机 |
|------|------|----------|----------|----------|
| **Reset** | 软重置 | 保留不动 | 归零 | 同关卡重新开始（Retry） |
| **Reinit** | 重建 | 销毁→重建 | 归零 | 切换到新关卡（SelectLevel） |
| **ClearAll** | 清除 | 销毁→不重建 | 归零 | 返回选关菜单（BackToLevelSelect） |

## 实现模板

### 规则 1：关卡定义表

```lua
-- levels.lua
return {
    {
        name = "初级",
        trackWidth = 28.0,    -- 赛道宽度
        speedMax = 55.0,      -- 最大速度
        speedInit = 12.0,     -- 初始速度
        obsStepBase = 14,     -- 障碍密度（越大越稀）
        lapsRequired = 2,     -- 通关圈数
    },
    {
        name = "中级",
        trackWidth = 24.0,
        speedMax = 75.0,
        speedInit = 16.0,
        obsStepBase = 9,
        lapsRequired = 3,
    },
    -- ...更多关卡
}
```

### 规则 2：SelectLevel 流程（levelselect → playing）

```lua
local function SelectLevel(idx)
    local lv = Levels[idx]

    -- 1. 写入关卡参数到运行时 config
    Config.TRACK_WIDTH = lv.trackWidth
    Config.SPEED_MAX   = lv.speedMax
    Config.SPEED_INIT  = lv.speedInit

    -- 2. 清理所有动态对象（顺序重要！先清对象，再重建赛道）
    Obstacles.ClearAll()   -- 销毁所有障碍物节点
    Coins.ClearAll()       -- 销毁所有金币节点
    Buildings.Reset()      -- 销毁所有建筑装饰
    Vegetation.Reset()     -- 销毁所有植被装饰

    -- 3. 重建赛道（用新参数）
    Track.Reinit()         -- 销毁旧瓦片 → BakeLoop() 重建

    -- 4. 重置玩家/相机/物理
    Player.Reset()
    Camera.Reset()

    -- 5. 重置游戏数据
    State.speed      = Config.SPEED_INIT
    State.score      = 0
    State.lapCount   = 0
    State.durability = 1.0

    -- 6. 切换状态
    State.gameState = "playing"
end
```

### 规则 3：BackToLevelSelect 流程（playing/gameover → levelselect）

```lua
local function BackToLevelSelect()
    -- 关键：使用 ClearAll 而非 DisableAll！
    -- DisableAll 只是 SetEnabled(false)，节点仍在场景中
    -- ClearAll 调用 :Remove()，彻底从场景图中删除

    Obstacles.ClearAll()
    Coins.ClearAll()
    Buildings.Reset()      -- 内部调用 node:Remove()
    Vegetation.Reset()     -- 内部调用 node:Remove()
    Track.ClearAll()       -- 彻底删除所有瓦片节点（不重建！）

    -- 显示选关 UI
    UI.ShowLevelSelect()
    State.gameState = "levelselect"
end
```

### 规则 4：Retry 流程（gameover → playing，同关卡）

```lua
local function Retry()
    -- 只需软重置，不重建赛道
    Obstacles.ClearAll()   -- 清除动态对象
    Coins.ClearAll()

    Track.Reset()          -- 重置索引/圈数，瓦片保留不动！
    Player.Reset()
    Camera.Reset()

    State.speed      = Config.SPEED_INIT
    State.score      = 0
    State.lapCount   = 0
    State.durability = 1.0
    State.gameState  = "playing"
end
```

### 规则 5：每个子系统必须实现三级接口

```lua
-- 以 Track 模块为例
local M = {}

-- Reset: 瓦片保留，只重置索引
function M.Reset()
    currentIdx  = 1
    lapCount    = 0
    prevVisIdx  = -1   -- 强制下帧重算可见性
end

-- Reinit: 销毁旧瓦片 → 用当前参数重建
function M.Reinit()
    for i = 1, N do tiles[i]:Remove() end
    tiles = {}
    BakeLoop()  -- 重新生成
end

-- ClearAll: 销毁所有，不重建（返回菜单用）
function M.ClearAll()
    for i = 1, N do tiles[i]:Remove() end
    tiles = {}
    nodes = {}
    N     = 0
end

return M
```

### 规则 6：装饰系统的 Reset 必须调用 Remove()

```lua
-- buildings.lua / vegetation.lua 的 Reset
function M.Reset()
    for tileIdx, rootNode in pairs(tileRoots) do
        rootNode:Remove()   -- ← 必须 Remove，不能只 SetEnabled(false)！
    end
    tileRoots = {}
end
```

## 设计清单

实现多关卡系统前确认：

- [ ] 每个子系统都有 Reset / Reinit / ClearAll 三个接口
- [ ] BackToLevelSelect 使用 ClearAll（不是 DisableAll）
- [ ] SelectLevel 先清理再重建（顺序：对象 → 赛道 → 玩家）
- [ ] Retry 只用 Reset（保留赛道结构，只清动态对象）
- [ ] 装饰系统 Reset 调用 `:Remove()`（不是 `:SetEnabled(false)`）
- [ ] 状态数据（分数/圈数/耐久）在每次 SelectLevel/Retry 时归零
- [ ] 关卡参数写入 Config 发生在清理之后、重建之前

## 常见陷阱

| 陷阱 | 原因 | 解决 |
|------|------|------|
| 切换关卡后旧地形仍可见 | 用了 `DisableAll`（只隐藏）而非 `ClearAll`（删除） | BackToLevelSelect 必须用 ClearAll |
| 返回菜单后内存不降 | 节点只 SetEnabled(false) 仍占内存 | 调用 `:Remove()` 释放节点 |
| 重建后装饰物位置错乱 | 装饰系统缓存了旧 tileRoots 未清空 | Reset 时清空 `tileRoots = {}` |
| Retry 后赛道消失 | 误用 ClearAll 代替 Reset | Retry 只清动态对象，赛道用 Reset |
| 新关卡宽度没生效 | Config 写入在 Track.Reinit 之后 | 确保先写 Config 再 Reinit |
| 启动后立即触发"完成一圈" | Reset 后 currentIdx 在尾部附近 | 添加 `lapFirstRun` 首圈防抖标志 |

## 状态数据设计

```lua
-- state.lua — 集中管理所有可变状态
local S = {
    gameState    = "levelselect",  -- 核心状态机
    currentLevel = 1,              -- 当前关卡编号

    -- 游戏进程（每次 SelectLevel/Retry 归零）
    speed        = 0,
    score        = 0,
    lapCount     = 0,
    durability   = 1.0,

    -- 通关条件
    lapsRequired = 2,
    isLevelClear = false,
}
return S
```

## 变体

- **线性关卡**（非环形赛道）: 不需要 Reinit，只需 ClearAll + 加载新地图
- **无限模式 + 关卡模式并存**: 增加 `gameMode` 字段区分
- **Boss 关**: 在状态机中增加 `"boss"` 状态，清理逻辑相同
- **存档恢复**: SelectLevel 后额外从存档加载进度数据
