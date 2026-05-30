-- ============================================================================
-- logic/AI.lua - AI 行为树驱动（ActivePriority 抢占式决策）
-- ============================================================================
-- 使用 behaviour-tree 库实现角色 AI：
--   优先级从高到低：逃跑(低血) → 攻击(范围内) → 追击(有敌人) → 巡逻(无敌人)
-- 纯逻辑层：只修改角色数据，不触碰 UI

local BT = require("lib.behaviourtree")
local Config = require("Config")
local Battle = require("logic.Battle")
local AIProfiles = require("characters.AIProfiles")
local BTCompiler = require("logic.BTCompiler")
local BTPresets = require("data.bt_presets")
local DefaultBTData = BTPresets.aggressive  -- 默认使用激进预设

local M = {}

-- 每个角色对应一棵行为树实例 (char → tree)
local trees_ = {}

-- 自定义行为树数据（来自编辑器保存），设置后新生成的角色将使用此树
---@type table|nil
local customTreeData_ = nil

-- 已编译的自定义树模板（缓存，避免每次 spawn 都重新编译）
---@type table|nil
local compiledCustomTree_ = nil

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

--- 条件：敌人在攻击范围内（使用角色自身 attackRange × profile 倍率）
local function InAttackRange()
    return BT.Task:new({
        run = function(task, ctx)
            local range = ctx.char.attackRange * ctx.profileParams.attackRangeMul
            if ctx.enemy and ctx.enemyDist <= range then
                task:success()
            else
                task:fail()
            end
        end,
    })
end

--- 动作：攻击当前目标（使用角色自身属性）
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

            -- 检查冷却（使用角色自身属性 × profile 倍率）
            if char.attackCooldown <= 0 then
                Battle.PerformAttack(char, enemy)
                char.attackCooldown = char.attackCooldownMax * ctx.profileParams.cooldownMul
            end

            task:success()  -- 攻击是瞬时动作，完成后重新评估
        end,
    })
end

--- 动作：追击目标（速度受 profile 倍率影响）
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

            local stopDist = char.stopDistance or (char.attackRange * ctx.profileParams.attackRangeMul)
            if dist <= stopDist then
                task:success()  -- 已经到达停止距离
                return
            end

            local invDist = 1.0 / dist
            local dirX = dx * invDist
            local dirZ = dz * invDist

            local speed = char.speed * ctx.profileParams.chaseSpeedMul
            local newX = char.worldPos.x + dirX * speed * ctx.dt
            local newZ = char.worldPos.z + dirZ * speed * ctx.dt
            char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
            char.facingRight = (dirX > 0)
            char.state = "moving"
            char.animState = "move"

            task:running()  -- 继续追击
        end,
    })
end

--- 动作：随机巡逻（无敌人时闲逛，速度受 profile 倍率影响）
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

            local speed = char.speed * ctx.profileParams.patrolSpeedMul
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

--- 为角色创建默认行为树（数据驱动，从 default_bt.lua 编译）
---@param char table
---@return table BehaviourTree instance
local function CreateTree(char)
    local tree, err = BTCompiler.Compile(DefaultBTData)
    if not tree then
        print("[AI] Failed to compile default tree: " .. tostring(err))
        -- Fallback：最简单的追击+攻击
        tree = BT:new({
            tree = BT.ActivePriority:new({
                nodes = {
                    BT.Sequence:new({ nodes = { HasEnemy(), InAttackRange(), Attack() } }),
                    BT.Sequence:new({ nodes = { HasEnemy(), Chase() } }),
                    Patrol(),
                },
            }),
            object = { char = char, characters = {}, dt = 0, enemy = nil, enemyDist = 0, profileParams = {} },
        })
        return tree
    end

    tree.object = { char = char, characters = {}, dt = 0, enemy = nil, enemyDist = 0, profileParams = {} }
    return tree
end

--- 为角色创建自定义行为树实例（每次调用编译新实例）
---@param char table
---@return table|nil BehaviourTree
local function CreateCustomTree(char)
    if not customTreeData_ then return nil end

    local tree, err = BTCompiler.Compile(customTreeData_)
    if not tree then
        print("[AI] Failed to create custom tree for char: " .. tostring(err))
        return nil
    end

    -- 设置初始上下文
    tree.object = { char = char, characters = {}, dt = 0, enemy = nil, enemyDist = 0, profileParams = {} }
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

    -- 动画锁定期间（受击/攻击）跳过行为树，避免覆盖 animState
    if char.animTimer and char.animTimer > 0 then return end

    -- 懒创建行为树（优先使用自定义树）
    if not trees_[char] then
        if customTreeData_ then
            trees_[char] = CreateCustomTree(char) or CreateTree(char)
        else
            trees_[char] = CreateTree(char)
        end
    end

    -- 获取 AI profile 参数
    local profileParams = AIProfiles.Get(char.aiProfile or "aggressive")

    -- 更新上下文（blackboard）
    local tree = trees_[char]
    local ctx = tree.object
    ctx.char = char
    ctx.characters = characters
    ctx.dt = dt
    ctx.enemy = nil
    ctx.enemyDist = 0
    ctx.profileParams = profileParams

    -- Tick 行为树
    tree:run()
end

--- 清除所有行为树（战斗结束时调用）
function M.Clear()
    trees_ = {}
end

-- ============================================================================
-- 自定义行为树支持
-- ============================================================================

--- 设置自定义行为树数据（来自编辑器）
--- 设置后，后续 spawn 的角色将使用此树（需 Clear + 重新生成）
---@param treeData table|nil 编辑器输出的 { rootId, nodes, edges }，nil 表示恢复默认
---@return boolean success, string|nil error
function M.SetCustomTree(treeData)
    if not treeData then
        customTreeData_ = nil
        compiledCustomTree_ = nil
        print("[AI] Custom tree cleared, using default AI")
        return true, nil
    end

    -- 验证
    local ok, err = BTCompiler.Validate(treeData)
    if not ok then
        print("[AI] Custom tree validation failed: " .. tostring(err))
        return false, err
    end

    -- 试编译一次确认可用
    local tree, compileErr = BTCompiler.Compile(treeData)
    if not tree then
        print("[AI] Custom tree compile failed: " .. tostring(compileErr))
        return false, compileErr
    end

    customTreeData_ = treeData
    compiledCustomTree_ = nil  -- 清除缓存，每个角色需独立实例
    print("[AI] Custom tree set successfully")
    return true, nil
end

--- 获取当前自定义树数据
---@return table|nil
function M.GetCustomTreeData()
    return customTreeData_
end

--- 获取默认行为树数据（用于编辑器显示）
---@return table
function M.GetDefaultTreeData()
    return DefaultBTData
end

--- 检查是否有自定义树
---@return boolean
function M.HasCustomTree()
    return customTreeData_ ~= nil
end

--- 兼容：供外部调用寻敌
M.FindNearestEnemy = FindNearestEnemy

return M
