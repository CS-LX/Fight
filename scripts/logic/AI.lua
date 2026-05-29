-- ============================================================================
-- logic/AI.lua - AI 行为（寻敌 + 移动/攻击决策）
-- ============================================================================
-- 纯逻辑层：只修改角色数据，不触碰 UI

local Config = require("Config")
local Battle = require("logic.Battle")

local M = {}

--- 寻找最近的敌人
---@param char table
---@param characters table[]
---@return table|nil
function M.FindNearestEnemy(char, characters)
    local nearestDist = math.huge
    local nearest = nil
    local mx = char.worldPos.x
    local mz = char.worldPos.z

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

    return nearest
end

--- 更新单个角色AI（纯逻辑：位置+状态+朝向）
---@param char table
---@param characters table[]
---@param dt number
function M.Update(char, characters, dt)
    if char.state == "dead" or char.state == "dying" then return end

    -- 更新攻击冷却
    char.attackCooldown = math.max(0, char.attackCooldown - dt)

    -- 寻找目标
    local target = M.FindNearestEnemy(char, characters)
    if target == nil then return end
    char.target = target

    local mx = char.worldPos.x
    local my = char.worldPos.y
    local mz = char.worldPos.z
    local dx = target.worldPos.x - mx
    local dz = target.worldPos.z - mz
    local dist = math.sqrt(dx * dx + dz * dz)

    if dist <= Config.AttackRange then
        -- 在攻击范围内 → 攻击
        char.state = "attacking"
        char.facingRight = (dx > 0)
        if char.attackCooldown <= 0 then
            Battle.PerformAttack(char, target)
            char.attackCooldown = Config.AttackCooldown
        end
    else
        -- 向目标移动
        char.state = "moving"
        local invDist = 1.0 / dist
        local dirX = dx * invDist
        local dirZ = dz * invDist
        local newX = mx + dirX * char.speed * dt
        local newZ = mz + dirZ * char.speed * dt
        char.worldPos = Vector3(newX, my, newZ)
        char.facingRight = (dirX > 0)
    end
end

return M
