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
---@param params table|nil 节点级自定义参数（来自树数据的 nodeData.params）
---@return table|nil BT.Task instance
function M.Create(name, params)
    local info = M.registry[name]
    if info and info.factory then
        return info.factory(params)
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

                local stopDist = char.stopDistance or (char.attackRange * (ctx.profileParams and ctx.profileParams.attackRangeMul or 1.0))
                if dist <= stopDist then task:success() return end

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

-- ============================================================================
-- 扩展条件节点
-- ============================================================================

M.Register("HPBelow50", {
    category = "condition",
    label = "血量低于50%",
    desc = "生命值低于50%",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                if ctx.char.hp / ctx.char.maxHP < 0.5 then
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

M.Register("EnemyHPLow", {
    category = "condition",
    label = "敌人血量低",
    desc = "当前目标血量低于30%",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                if ctx.enemy and ctx.enemy.hp / ctx.enemy.maxHP < 0.3 then
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

M.Register("EnemyClose", {
    category = "condition",
    label = "敌人过近",
    desc = "敌人距离小于阈值（默认1.5米，可通过params.threshold调整）",
    paramsSchema = {
        { key = "threshold", type = "number", default = 1.5, label = "距离阈值" },
    },
    factory = function(params)
        local threshold = (params and params.threshold) or 1.5
        return BT.Task:new({
            run = function(task, ctx)
                if ctx.enemy and ctx.enemyDist < threshold then
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

M.Register("EnemyFar", {
    category = "condition",
    label = "敌人较远",
    desc = "敌人距离大于4米",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                if ctx.enemy and ctx.enemyDist > 4.0 then
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

M.Register("CooldownReady", {
    category = "condition",
    label = "冷却就绪",
    desc = "攻击冷却已结束",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                if ctx.char.attackCooldown <= 0 then
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

M.Register("IsOutnumbered", {
    category = "condition",
    label = "以少敌多",
    desc = "周围3米内敌人数 > 友军数",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local char = ctx.char
                local enemies, allies = 0, 0
                for _, c in ipairs(ctx.characters) do
                    if c ~= char and c.state ~= "dead" and c.state ~= "dying" then
                        local dx = c.worldPos.x - char.worldPos.x
                        local dz = c.worldPos.z - char.worldPos.z
                        if math.sqrt(dx * dx + dz * dz) < 3.0 then
                            if c.team == char.team then
                                allies = allies + 1
                            else
                                enemies = enemies + 1
                            end
                        end
                    end
                end
                if enemies > allies then task:success() else task:fail() end
            end,
        })
    end,
})

M.Register("HasAllyInRange", {
    category = "condition",
    label = "友军在范围内",
    desc = "3米内有友方存活单位",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local char = ctx.char
                for _, c in ipairs(ctx.characters) do
                    if c ~= char and c.team == char.team and c.state ~= "dead" and c.state ~= "dying" then
                        local dx = c.worldPos.x - char.worldPos.x
                        local dz = c.worldPos.z - char.worldPos.z
                        if math.sqrt(dx * dx + dz * dz) < 3.0 then
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
-- 扩展动作节点
-- ============================================================================

--- 寻找血量最低的敌人作为目标
M.Register("FindWeakestEnemy", {
    category = "action",
    label = "锁定最弱敌人",
    desc = "选择血量百分比最低的敌人作为目标",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local weakest = nil
                local lowestRatio = math.huge
                for _, c in ipairs(ctx.characters) do
                    if c.team ~= ctx.char.team and c.state ~= "dead" and c.state ~= "dying" then
                        local ratio = c.hp / c.maxHP
                        if ratio < lowestRatio then
                            lowestRatio = ratio
                            weakest = c
                        end
                    end
                end
                if weakest then
                    ctx.enemy = weakest
                    local dx = weakest.worldPos.x - ctx.char.worldPos.x
                    local dz = weakest.worldPos.z - ctx.char.worldPos.z
                    ctx.enemyDist = math.sqrt(dx * dx + dz * dz)
                    task:success()
                else
                    task:fail()
                end
            end,
        })
    end,
})

--- 环绕走位（绕目标侧移）
M.Register("Strafe", {
    category = "action",
    label = "环绕走位",
    desc = "围绕目标横向移动（保持距离）",
    factory = function()
        return BT.Task:new({
            start = function(task, ctx)
                -- 随机选择顺时针或逆时针
                task.direction = (math.random() > 0.5) and 1 or -1
                task.timer = 0
                task.duration = 0.8 + math.random() * 0.6  -- 0.8~1.4秒
            end,
            run = function(task, ctx)
                local char = ctx.char
                local enemy = ctx.enemy
                if not enemy then task:fail() return end

                task.timer = task.timer + ctx.dt
                if task.timer >= task.duration then
                    task:success()
                    return
                end

                local dx = enemy.worldPos.x - char.worldPos.x
                local dz = enemy.worldPos.z - char.worldPos.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < 0.01 then task:success() return end

                -- 垂直于朝向敌人方向的移动
                local perpX = -dz / dist * task.direction
                local perpZ = dx / dist * task.direction
                local speed = char.speed * (ctx.profileParams and ctx.profileParams.chaseSpeedMul or 1.0) * 0.7
                local newX = char.worldPos.x + perpX * speed * ctx.dt
                local newZ = char.worldPos.z + perpZ * speed * ctx.dt
                char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
                char.facingRight = (dx > 0)
                char.state = "moving"
                char.animState = "move"
                task:running()
            end,
        })
    end,
})

--- 后撤拉开距离（比 Flee 更短促，只退一点）
M.Register("Retreat", {
    category = "action",
    label = "后撤",
    desc = "后退拉开距离（可配置距离和速度倍率）",
    paramsSchema = {
        { key = "distance", type = "number", default = 1.5, label = "后撤距离" },
        { key = "speedMul", type = "number", default = 1.2, label = "速度倍率" },
    },
    factory = function(params)
        local retreatDist = (params and params.distance) or 1.5
        local speedMul = (params and params.speedMul) or 1.2
        return BT.Task:new({
            start = function(task)
                task.retreated = 0
            end,
            run = function(task, ctx)
                local char = ctx.char
                local enemy = ctx.enemy
                if not enemy then task:fail() return end

                if task.retreated >= retreatDist then
                    task:success()
                    return
                end

                local dx = char.worldPos.x - enemy.worldPos.x
                local dz = char.worldPos.z - enemy.worldPos.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < 0.01 then dist = 0.01 end

                local speed = char.speed * speedMul
                local step = speed * ctx.dt
                local newX = char.worldPos.x + (dx / dist) * step
                local newZ = char.worldPos.z + (dz / dist) * step
                char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
                char.facingRight = (dx < 0)  -- 面朝敌人后退
                char.state = "moving"
                char.animState = "move"
                task.retreated = task.retreated + step
                task:running()
            end,
        })
    end,
})

--- 冲刺突进（快速冲向目标，速度x2）
M.Register("Dash", {
    category = "action",
    label = "冲刺突进",
    desc = "以2倍速冲向目标（持续0.4秒）",
    factory = function()
        return BT.Task:new({
            start = function(task)
                task.timer = 0
            end,
            run = function(task, ctx)
                local char = ctx.char
                local enemy = ctx.enemy
                if not enemy then task:fail() return end

                task.timer = task.timer + ctx.dt
                if task.timer >= 0.4 then
                    task:success()
                    return
                end

                local dx = enemy.worldPos.x - char.worldPos.x
                local dz = enemy.worldPos.z - char.worldPos.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < 0.3 then task:success() return end

                local invDist = 1.0 / dist
                local speed = char.speed * 2.0  -- 2倍速冲刺
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

--- 集结：向最近友军移动
M.Register("Rally", {
    category = "action",
    label = "集结",
    desc = "向最近友军靠拢（抱团）",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                local char = ctx.char
                local nearestAlly = nil
                local nearestDist = math.huge
                for _, c in ipairs(ctx.characters) do
                    if c ~= char and c.team == char.team and c.state ~= "dead" and c.state ~= "dying" then
                        local dx = c.worldPos.x - char.worldPos.x
                        local dz = c.worldPos.z - char.worldPos.z
                        local d = math.sqrt(dx * dx + dz * dz)
                        if d < nearestDist then
                            nearestDist = d
                            nearestAlly = c
                        end
                    end
                end
                if not nearestAlly or nearestDist < 1.0 then
                    char.state = "idle"
                    char.animState = "idle"
                    task:success()
                    return
                end

                local dx = nearestAlly.worldPos.x - char.worldPos.x
                local dz = nearestAlly.worldPos.z - char.worldPos.z
                local dist = nearestDist
                local speed = char.speed * (ctx.profileParams and ctx.profileParams.chaseSpeedMul or 1.0)
                local newX = char.worldPos.x + (dx / dist) * speed * ctx.dt
                local newZ = char.worldPos.z + (dz / dist) * speed * ctx.dt
                char.worldPos = ClampToArena(Vector3(newX, char.worldPos.y, newZ))
                char.facingRight = (dx > 0)
                char.state = "moving"
                char.animState = "move"
                task:running()
            end,
        })
    end,
})

--- 远程攻击（通过 params 配置子弹和特效）
M.Register("RangedAttack", {
    category = "action",
    label = "远程攻击",
    desc = "发射投射物攻击目标（子弹/特效通过 params 配置）",
    paramsSchema = {
        { key = "bulletSpeed", type = "number", default = 10, label = "子弹速度" },
        { key = "bulletEffect", type = "string", default = "", label = "子弹特效" },
        { key = "muzzleEffect", type = "string", default = "", label = "枪口特效" },
        { key = "hitEffect", type = "string", default = "", label = "命中特效" },
        { key = "bulletColor", type = "string", default = "#ffff00", label = "子弹颜色" },
        { key = "damageMultiplier", type = "number", default = 1.0, label = "伤害倍率" },
        { key = "angularSpeed", type = "number", default = 0, label = "子弹角速度(度/秒)" },
    },
    factory = function(params)
        params = params or {}
        local bulletSpeed = params.bulletSpeed or 10
        local bulletEffect = params.bulletEffect or ""
        local muzzleEffect = params.muzzleEffect or ""
        local hitEffect = params.hitEffect or ""
        local bulletColor = params.bulletColor or "#ffff00"
        local damageMul = params.damageMultiplier or 1.0
        local angularSpeed = params.angularSpeed or 0

        return BT.Task:new({
            run = function(task, ctx)
                local char = ctx.char
                local enemy = ctx.enemy
                if not enemy or enemy.state == "dead" or enemy.state == "dying" then
                    task:fail()
                    return
                end

                -- 面朝敌人
                local dx = enemy.worldPos.x - char.worldPos.x
                char.facingRight = (dx > 0)
                char.state = "attacking"
                char.animState = "attack"

                if char.attackCooldown <= 0 then
                    -- 锁定攻击动画（投掷动作持续时间）
                    char.animTimer = 0.5

                    -- 发射投射物（存入角色的 projectiles 列表，由渲染层消费）
                    if not char.projectiles then char.projectiles = {} end
                    char.projectiles[#char.projectiles + 1] = {
                        fromPos = Vector3(char.worldPos.x, char.worldPos.y + 1.0, char.worldPos.z),
                        targetChar = enemy,
                        speed = bulletSpeed,
                        bulletEffect = bulletEffect,
                        muzzleEffect = muzzleEffect,
                        hitEffect = hitEffect,
                        bulletColor = bulletColor,
                        damage = (char.attackDamage or 10) * damageMul,
                        angularSpeed = angularSpeed,
                    }

                    local cooldownMul = ctx.profileParams and ctx.profileParams.cooldownMul or 1.0
                    char.attackCooldown = char.attackCooldownMax * cooldownMul
                end
                task:success()
            end,
        })
    end,
})

--- 等待一段随机时间（用于模拟犹豫/停顿）
M.Register("Wait", {
    category = "action",
    label = "等待",
    desc = "原地等待0.5~1.5秒",
    factory = function()
        return BT.Task:new({
            start = function(task)
                task.timer = 0
                task.duration = 0.5 + math.random() * 1.0
            end,
            run = function(task, ctx)
                task.timer = task.timer + ctx.dt
                ctx.char.state = "idle"
                ctx.char.animState = "idle"
                if task.timer >= task.duration then
                    task:success()
                else
                    task:running()
                end
            end,
        })
    end,
})

--- 追击最弱目标（FindWeakestEnemy + Chase 组合简写）
M.Register("ChaseWeakest", {
    category = "action",
    label = "追击最弱",
    desc = "锁定血量最低的敌人并追击",
    factory = function()
        return BT.Task:new({
            run = function(task, ctx)
                -- 找到最弱敌人
                local weakest = nil
                local lowestRatio = math.huge
                for _, c in ipairs(ctx.characters) do
                    if c.team ~= ctx.char.team and c.state ~= "dead" and c.state ~= "dying" then
                        local ratio = c.hp / c.maxHP
                        if ratio < lowestRatio then
                            lowestRatio = ratio
                            weakest = c
                        end
                    end
                end
                if not weakest then task:fail() return end

                local char = ctx.char
                local dx = weakest.worldPos.x - char.worldPos.x
                local dz = weakest.worldPos.z - char.worldPos.z
                local dist = math.sqrt(dx * dx + dz * dz)

                ctx.enemy = weakest
                ctx.enemyDist = dist

                local stopDist = char.stopDistance or char.attackRange
                if dist <= stopDist then task:success() return end

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

return M
