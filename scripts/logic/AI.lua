-- ============================================================================
-- logic/AI.lua - AI 行为树驱动（ActivePriority 抢占式决策）
-- ============================================================================
-- 使用 behaviour-tree 库实现角色 AI：
--   优先级从高到低：逃跑(低血) → 攻击(范围内) → 追击(有敌人) → 巡逻(无敌人)
-- 纯逻辑层：只修改角色数据，不触碰 UI

local BT = require("lib.behaviourtree")
local Config = require("Config")
local Battle = require("logic.Battle")

local M = {}

-- 每个角色对应一棵行为树实例 (char → tree)
local trees_ = {}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 寻找最近的存活敌人
---@param char table
---@param characters table[]
---@return table|nil enemy, number distance
local function FindNearestEnemy(char, characters)
    local nearestDist = math.huge
    local nearest = nil
    local mx, mz = char.worldPos.x, char.worldPos.z

    for _, other in ipairs(characters) do
        if other.team ~= char.team and other.state ~= "dead" and other.state ~= "dying" then
            local dx = other.worldPos.x - mx
            local dz = other.worldPos.z - mz
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist < nearestDist then
                nearestDist = dist
                nearest = other
            end
        end
    end

    return nearest, nearestDist
end

--- 将角色限制在竞技场边界内
---@param pos Vector3
---@return Vector3
local function ClampToArena(pos)
    local halfW = Config.ArenaWidth * 0.5 - 0.5
    local halfD = Config.ArenaDepth * 0.5 - 0.5
    local x = math.max(-halfW, math.min(halfW, pos.x))
    local z = math.max(-halfD, math.min(halfD, pos.z))
    return Vector3(x, pos.y, z)
end

-- ============================================================================
-- 行为节点定义
-- ============================================================================

--- 条件：有敌人存在
local function HasEnemy()
    return BT.Task:new({
        run = function(task, ctx)
            local enemy, dist = FindNearestEnemy(ctx.char, ctx.characters)
            if enemy then
                ctx.enemy = enemy
                ctx.enemyDist = dist
                task:success()
            else
                task:fail()
            end
        end,
    })
end

--- 条件：敌人在攻击范围内
local function InAttackRange()
    return BT.Task:new({
        run = function(task, ctx)
            if ctx.enemy and ctx.enemyDist <= Config.AttackRange then
                task:success()
            else
                task:fail()
            end
        end,
    })
end

--- 动作：攻击当前目标
local function Attack()
    return BT.Task:new({
        run = function(task, ctx)
            local char = ctx.char
            local enemy = ctx.enemy

            if not enemy or enemy.state == "dead" or enemy.state == "dying" then
                task:fail()
                return
            end

            -- 面向敌人
            local dx = enemy.worldPos.x - char.worldPos.x
            char.facingRight = (dx > 0)
            char.state = "attacking"
            char.animState = "attack"

            -- 检查冷却
            if char.attackCooldown <= 0 then
                Battle.PerformAttack(char, enemy)
                char.attackCooldown = Config.AttackCooldown
            end

            task:success()  -- 攻击是瞬时动作，完成后重新评估
        end,
    })
end

--- 动作：追击目标
local function Chase()
    return BT.Task:new({
        run = function(task, ctx)
            local char = ctx.char
            local enemy = ctx.enemy

            if not enemy then
                task:fail()
                return
            end

            local dx = enemy.worldPos.x - char.worldPos.x
            local dz = enemy.worldPos.z - char.worldPos.z
            local dist = math.sqrt(dx * dx + dz * dz)

            if dist <= Config.AttackRange then
                task:success()  -- 已经到达攻击范围
                return
            end

            local invDist = 1.0 / dist
            local dirX = dx * invDist
            local dirZ = dz * invDist

            local newX = char.worldPos.x + dirX * char.speed * ctx.dt
            local newZ = char.worldPos.z + dirZ * char.speed * ctx.dt
            char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
            char.facingRight = (dirX > 0)
            char.state = "moving"
            char.animState = "move"

            task:running()  -- 继续追击
        end,
    })
end

--- 动作：随机巡逻（无敌人时闲逛）
local function Patrol()
    return BT.Task:new({
        start = function(task, ctx)
            -- 选择一个随机巡逻目标点
            local char = ctx.char
            local halfW = Config.ArenaWidth * 0.5 - 1
            local halfD = Config.ArenaDepth * 0.5 - 1
            task.patrolTarget = Vector3(
                math.random() * halfW * 2 - halfW,
                char.worldPos.y,
                math.random() * halfD * 2 - halfD
            )
        end,
        run = function(task, ctx)
            local char = ctx.char
            local target = task.patrolTarget

            local dx = target.x - char.worldPos.x
            local dz = target.z - char.worldPos.z
            local dist = math.sqrt(dx * dx + dz * dz)

            if dist < 0.5 then
                -- 到达巡逻点
                char.state = "idle"
                char.animState = "idle"
                task:success()
                return
            end

            local invDist = 1.0 / dist
            local dirX = dx * invDist
            local dirZ = dz * invDist

            local speed = char.speed * 0.5  -- 巡逻走慢一点
            local newX = char.worldPos.x + dirX * speed * ctx.dt
            local newZ = char.worldPos.z + dirZ * speed * ctx.dt
            char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
            char.facingRight = (dirX > 0)
            char.state = "moving"
            char.animState = "move"

            task:running()
        end,
    })
end

-- ============================================================================
-- 构建行为树（每个角色一棵独立实例）
-- ============================================================================

--- 为角色创建行为树
---@param char table
---@return table BehaviourTree instance
local function CreateTree(char)
    --[[
        ActivePriority (高优先级可抢占低优先级 running 状态)
        ├── Sequence: 逃跑 [血量低?] → [有敌人?] → [逃跑动作]
        ├── Sequence: 攻击 [有敌人?] → [在攻击范围?] → [攻击动作]
        ├── Sequence: 追击 [有敌人?] → [追击动作]
        └── 巡逻 [随机走动]
    ]]
    local tree = BT:new({
        tree = BT.ActivePriority:new({
            nodes = {
                -- 1) 攻击（最高优先级）
                BT.Sequence:new({
                    nodes = {
                        HasEnemy(),
                        InAttackRange(),
                        Attack(),
                    },
                }),
                -- 2) 追击
                BT.Sequence:new({
                    nodes = {
                        HasEnemy(),
                        Chase(),
                    },
                }),
                -- 3) 巡逻（最低优先级）
                Patrol(),
            },
        }),
        object = { char = char, characters = {}, dt = 0, enemy = nil, enemyDist = 0 },
    })

    return tree
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 更新单个角色 AI（由 Battle 每帧调用）
---@param char table
---@param characters table[]
---@param dt number
function M.Update(char, characters, dt)
    if char.state == "dead" or char.state == "dying" then return end

    -- 更新攻击冷却
    char.attackCooldown = math.max(0, char.attackCooldown - dt)

    -- 懒创建行为树
    if not trees_[char] then
        trees_[char] = CreateTree(char)
    end

    -- 更新上下文（blackboard）
    local tree = trees_[char]
    local ctx = tree.object
    ctx.char = char
    ctx.characters = characters
    ctx.dt = dt
    ctx.enemy = nil
    ctx.enemyDist = 0

    -- Tick 行为树
    tree:run()
end

--- 清除所有行为树（战斗结束时调用）
function M.Clear()
    trees_ = {}
end

--- 兼容：供外部调用寻敌
M.FindNearestEnemy = FindNearestEnemy

return M
