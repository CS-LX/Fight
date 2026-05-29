-- ============================================================================
-- logic/CharLogic.lua - 角色逻辑层（纯数据，不含任何UI/渲染引用）
-- ============================================================================
-- 职责：创建角色逻辑数据、生成队伍
-- 不依赖：UI、Spine、GameUI

local Config = require("Config")

local M = {}

--- 创建一个角色的逻辑数据
---@param defId string 角色定义ID（对应 defs/ 中的文件）
---@param team string "red" | "blue"
---@param spawnPos Vector3
---@return table 角色逻辑数据
function M.Create(defId, team, spawnPos)
    local char = {
        -- 身份
        defId = defId,            -- 角色定义ID，表现层据此查找外观
        team = team,

        -- 空间
        worldPos = Vector3(spawnPos.x, spawnPos.y, spawnPos.z),
        facingRight = (team == "red"),

        -- 战斗
        hp = Config.MaxHP,
        maxHP = Config.MaxHP,
        speed = Config.CharSpeed + math.random() * 0.5,
        attackCooldown = 0,

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
---@param defId string 角色定义ID
---@return table[] 角色逻辑数据列表
function M.SpawnTeams(defId)
    local characters = {}
    local halfWidth = Config.ArenaWidth / 2 - 2
    local spacing = (Config.ArenaDepth - 4) / (Config.TeamSize - 1)

    -- 红队（左侧）
    for i = 1, Config.TeamSize do
        local z = -Config.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(-halfWidth, 0, z)
        local char = M.Create(defId, "red", spawnPos)
        table.insert(characters, char)
    end

    -- 蓝队（右侧）
    for i = 1, Config.TeamSize do
        local z = -Config.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(halfWidth, 0, z)
        local char = M.Create(defId, "blue", spawnPos)
        table.insert(characters, char)
    end

    return characters
end

return M
