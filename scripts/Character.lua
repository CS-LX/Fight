-- ============================================================================
-- Character.lua - Spine 角色创建与生成
-- ============================================================================

local Config = require("Config")

local M = {}

-- Spine 资源路径
M.SPINE_SRC = "spine/build_char_1035_wisdel_game_9/build_char_1035_wisdel_game_9.skel"

-- 动画名映射
M.Anim = {
    Idle    = "Default",
    Move    = "Move",
    Attack  = "Special",
    Hit     = "Interact",
    Die     = "Sleep",
    Relax   = "Relax",
}

-- Spine 显示尺寸（像素）
M.SPINE_WIDTH  = 120
M.SPINE_HEIGHT = 120

--- 创建一个 Spine 角色数据（不含 UI 控件，由 GameUI 统一管理）
---@param team string "red" | "blue"
---@param spawnPos Vector3
---@return table 角色数据
function M.Create(team, spawnPos)
    local char = {
        team = team,
        worldPos = Vector3(spawnPos.x, spawnPos.y, spawnPos.z),
        hp = Config.MaxHP,
        maxHP = Config.MaxHP,
        speed = Config.CharSpeed + math.random() * 0.5,
        attackCooldown = 0,
        state = "moving",       -- "moving" | "attacking" | "dying" | "dead"
        target = nil,
        animTimer = 0,
        deathTimer = 0,
        currentAnim = "",       -- 当前播放的动画名
        facingRight = (team == "red"),  -- 红队初始朝右，蓝队初始朝左
        spine = nil,            -- UI.Spine 控件引用（由 GameUI 赋值）
    }

    return char
end

--- 生成两队角色
---@return table[] 角色数据列表
function M.SpawnTeams()
    local characters = {}
    local halfWidth = Config.ArenaWidth / 2 - 2
    local spacing = (Config.ArenaDepth - 4) / (Config.TeamSize - 1)

    -- 红队从左侧进入
    for i = 1, Config.TeamSize do
        local z = -Config.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(-halfWidth, 0, z)
        local char = M.Create("red", spawnPos)
        table.insert(characters, char)
    end

    -- 蓝队从右侧进入
    for i = 1, Config.TeamSize do
        local z = -Config.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(halfWidth, 0, z)
        local char = M.Create("blue", spawnPos)
        table.insert(characters, char)
    end

    print("Spawned " .. Config.TeamSize .. " red and " .. Config.TeamSize .. " blue characters")
    return characters
end

return M
