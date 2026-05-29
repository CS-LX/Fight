-- ============================================================================
-- logic/BTTaskLibrary.lua - 行为树预制叶子节点注册表
-- ============================================================================
-- 供行为树编辑器使用：玩家选择 Task 节点时从此库中选取
-- 每个节点是一个工厂函数，返回 BT.Task 实例

local BT = require("lib.behaviourtree")
local Config = require("Config")
local Battle = require("logic.Battle")

local M = {}

-- 注册表: { name -> { factory, category, label, desc } }
M.registry = {}

--- 注册一个预制 Task 节点
---@param name string 唯一标识
---@param info table { category, label, desc, factory }
function M.Register(name, info)
    M.registry[name] = info
end

--- 获取所有已注册的节点信息列表
---@return table[] { name, category, label, desc }
function M.GetAll()
    local list = {}
    for name, info in pairs(M.registry) do
        list[#list + 1] = {
            name = name,
            category = info.category,
            label = info.label,
            desc = info.desc,
        }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

--- 根据名称创建一个 Task 实例
---@param name string
---@return table|nil BT.Task instance
function M.Create(name)
    local info = M.registry[name]
    if info and info.factory then
        return info.factory()
    end
    return nil
end

-- ============================================================================
-- 辅助函数 (供节点使用)
-- ============================================================================

--- 寻找最近的存活敌人
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
local function ClampToArena(pos)
    local halfW = Config.ArenaWidth * 0.5 - 0.5
    local halfD = Config.ArenaDepth * 0.5 - 0.5
    local x = math.max(-halfW, math.min(halfW, pos.x))
    local z = math.max(-halfD, math.min(halfD, pos.z))
    return Vector3(x, pos.y, z)
end

-- ============================================================================
-- 条件节点
-- ============================================================================

M.Register("HasEnemy", {
    category = "condition",
    label = "有敌人",
    desc = "检测是否有存活的敌方单位",
    factory = function()
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
    end,
})

M.Register("InAttackRange", {
    category = "condition",
    label = "在攻击范围",
    desc = "敌人是否在攻击范围内",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local range = ctx.char.attackRange * (ctx.profileParams and ctx.profileParams.attackRangeMul or 1.0)
                if ctx.enemy and ctx.enemyDist <= range then
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

M.Register("HPLow", {
    category = "condition",
    label = "血量低",
    desc = "生命值低于30%",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                if ctx.char.hp / ctx.char.maxHP < 0.3 then
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

M.Register("HPHigh", {
    category = "condition",
    label = "血量高",
    desc = "生命值高于70%",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                if ctx.char.hp / ctx.char.maxHP > 0.7 then
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

M.Register("EnemyCountHigh", {
    category = "condition",
    label = "敌人数量多",
    desc = "存活敌人数量 >= 3",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local count = 0
                for _, c in ipairs(ctx.characters) do
                    if c.team ~= ctx.char.team and c.state ~= "dead" and c.state ~= "dying" then
                        count = count + 1
                    end
                end
                if count >= 3 then task:success() else task:fail() end
            end,
        })
    end,
})

M.Register("AllyNearby", {
    category = "condition",
    label = "附近有友军",
    desc = "2米内有友方单位",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local char = ctx.char
                for _, c in ipairs(ctx.characters) do
                    if c ~= char and c.team == char.team and c.state ~= "dead" and c.state ~= "dying" then
                        local dx = c.worldPos.x - char.worldPos.x
                        local dz = c.worldPos.z - char.worldPos.z
                        if math.sqrt(dx * dx + dz * dz) < 2.0 then
                            task:success()
                            return
                        end
                    end
                end
                task:fail()
            end,
        })
    end,
})

-- ============================================================================
-- 动作节点
-- ============================================================================

M.Register("Attack", {
    category = "action",
    label = "攻击",
    desc = "对当前目标执行攻击",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local char = ctx.char
                local enemy = ctx.enemy
                if not enemy or enemy.state == "dead" or enemy.state == "dying" then
                    task:fail()
                    return
                end
                local dx = enemy.worldPos.x - char.worldPos.x
                char.facingRight = (dx > 0)
                char.state = "attacking"
                char.animState = "attack"
                if char.attackCooldown <= 0 then
                    Battle.PerformAttack(char, enemy)
                    local cooldownMul = ctx.profileParams and ctx.profileParams.cooldownMul or 1.0
                    char.attackCooldown = char.attackCooldownMax * cooldownMul
                end
                task:success()
            end,
        })
    end,
})

M.Register("Chase", {
    category = "action",
    label = "追击",
    desc = "向最近敌人移动",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local char = ctx.char
                local enemy = ctx.enemy
                if not enemy then task:fail() return end

                local dx = enemy.worldPos.x - char.worldPos.x
                local dz = enemy.worldPos.z - char.worldPos.z
                local dist = math.sqrt(dx * dx + dz * dz)

                local range = char.attackRange * (ctx.profileParams and ctx.profileParams.attackRangeMul or 1.0)
                if dist <= range then task:success() return end

                local invDist = 1.0 / dist
                local speed = char.speed * (ctx.profileParams and ctx.profileParams.chaseSpeedMul or 1.0)
                local newX = char.worldPos.x + dx * invDist * speed * ctx.dt
                local newZ = char.worldPos.z + dz * invDist * speed * ctx.dt
                char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
                char.facingRight = (dx > 0)
                char.state = "moving"
                char.animState = "move"
                task:running()
            end,
        })
    end,
})

M.Register("Patrol", {
    category = "action",
    label = "巡逻",
    desc = "随机走动巡逻",
    factory = function()
        return BT.Task:new({
            start = function(task, ctx)
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
                    char.state = "idle"
                    char.animState = "idle"
                    task:success()
                    return
                end
                local invDist = 1.0 / dist
                local speed = char.speed * (ctx.profileParams and ctx.profileParams.patrolSpeedMul or 0.5)
                local newX = char.worldPos.x + dx * invDist * speed * ctx.dt
                local newZ = char.worldPos.z + dz * invDist * speed * ctx.dt
                char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
                char.facingRight = (dx > 0)
                char.state = "moving"
                char.animState = "move"
                task:running()
            end,
        })
    end,
})

M.Register("Flee", {
    category = "action",
    label = "逃跑",
    desc = "远离最近敌人",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local char = ctx.char
                local enemy = ctx.enemy
                if not enemy then task:fail() return end

                local dx = char.worldPos.x - enemy.worldPos.x
                local dz = char.worldPos.z - enemy.worldPos.z
                local dist = math.sqrt(dx * dx + dz * dz)

                if dist > 5.0 then
                    char.state = "idle"
                    char.animState = "idle"
                    task:success()
                    return
                end

                local invDist = 1.0 / math.max(dist, 0.01)
                local speed = char.speed * (ctx.profileParams and ctx.profileParams.chaseSpeedMul or 1.0)
                local newX = char.worldPos.x + dx * invDist * speed * ctx.dt
                local newZ = char.worldPos.z + dz * invDist * speed * ctx.dt
                char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
                char.facingRight = (dx > 0)
                char.state = "moving"
                char.animState = "move"
                task:running()
            end,
        })
    end,
})

M.Register("Guard", {
    category = "action",
    label = "防守",
    desc = "原地站立待命",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                ctx.char.state = "idle"
                ctx.char.animState = "idle"
                task:success()
            end,
        })
    end,
})

return M
