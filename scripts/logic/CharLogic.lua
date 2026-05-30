-- ============================================================================
-- logic/CharLogic.lua - 角色逻辑层（纯数据，不含任何UI/渲染引用）
-- ============================================================================
-- 职责：创建角色逻辑数据、生成队伍
-- 不依赖：UI、Spine、GameUI
-- 从 CharRegistry 读取角色模块数据

local Config = require("Config")
local CharRegistry = require("characters.CharRegistry")

local M = {}

--- 创建一个角色的逻辑数据
---@param moduleId string 角色模块ID（CharRegistry 中的ID）
---@param team string "red" | "blue"
---@param spawnPos Vector3
---@return table 角色逻辑数据
function M.Create(moduleId, team, spawnPos)
    local mod = CharRegistry.Get(moduleId)
    -- fallback：如果模块不存在则使用全局 Config
    local baseHP = mod and mod.config.baseHP or Config.MaxHP
    local baseSpeed = mod and mod.config.baseSpeed or Config.CharSpeed
    local attackDamage = mod and mod.config.attackDamage or Config.AttackDamage
    local attackRange = mod and mod.config.attackRange or Config.AttackRange
    local attackCooldownMax = mod and mod.config.attackCooldown or Config.AttackCooldown
    local stopDistance = mod and mod.config.stopDistance or 0.6
    local collisionRadius = mod and mod.config.collisionRadius or 0.4
    local aiProfile = mod and mod.ai.profile or "aggressive"

    local char = {
        -- 身份
        moduleId = moduleId,      -- 角色模块ID（新系统）
        defId = moduleId,         -- 兼容旧表现层
        team = team,

        -- 空间
        worldPos = Vector3(spawnPos.x, spawnPos.y, spawnPos.z),
        facingRight = (team == "red"),

        -- 战斗（从模块读取）
        hp = baseHP,
        maxHP = baseHP,
        speed = baseSpeed + math.random() * 0.5,
        attackDamage = attackDamage,
        attackRange = attackRange,
        attackCooldownMax = attackCooldownMax,
        attackCooldown = 0,
        stopDistance = stopDistance,
        collisionRadius = collisionRadius,

        -- AI
        aiProfile = aiProfile,

        -- 状态（供 AI / 状态机驱动）
        state = "moving",       -- "moving" | "attacking" | "dying" | "dead"
        target = nil,
        animState = "idle",     -- 当前期望的动画状态（表现层据此播放动画）
        animTimer = 0,          -- 动画锁定计时器
        deathTimer = 0,
    }

    return char
end

--- 生成两队角色
---@param moduleId string 角色模块ID
---@return table[] 角色逻辑数据列表
function M.SpawnTeams(moduleId)
    local characters = {}
    local halfWidth = Config.ArenaWidth / 2 - 2
    local spacing = (Config.ArenaDepth - 4) / (Config.TeamSize - 1)

    -- 红队（左侧）
    for i = 1, Config.TeamSize do
        local z = -Config.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(-halfWidth, 0, z)
        local char = M.Create(moduleId, "red", spawnPos)
        table.insert(characters, char)
    end

    -- 蓝队（右侧）
    for i = 1, Config.TeamSize do
        local z = -Config.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(halfWidth, 0, z)
        local char = M.Create(moduleId, "blue", spawnPos)
        table.insert(characters, char)
    end

    return characters
end

--- 从部署数据生成角色列表（TABS 部署模式）
---@param placements table[] { moduleId, team, worldX, worldZ, col, row }
---@return table[] 角色逻辑数据列表
function M.SpawnFromDeployment(placements)
    local characters = {}

    for _, p in ipairs(placements) do
        local spawnPos = Vector3(p.worldX, 0, p.worldZ)
        local char = M.Create(p.moduleId, p.team, spawnPos)
        table.insert(characters, char)
    end

    return characters
end

return M
