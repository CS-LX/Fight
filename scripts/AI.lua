-- ============================================================================
-- AI.lua - AI 行为（寻敌 + 移动/攻击决策）
-- ============================================================================

local Config = require("Config")
local Battle = require("Battle")

local M = {}

--- 寻找最近的敌人
---@param char table
---@param characters table[]
---@return table|nil
function M.FindNearestEnemy(char, characters)
    local nearestDist = math.huge
    local nearest = nil
    local myPos = char.node.position

    for _, other in ipairs(characters) do
        if other.team ~= char.team and other.state ~= "dead" and other.state ~= "dying" then
            local dist = (other.node.position - myPos):Length()
            if dist < nearestDist then
                nearestDist = dist
                nearest = other
            end
        end
    end

    return nearest
end

--- 更新单个角色AI
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

    local myPos = char.node.position
    local targetPos = target.node.position
    local diff = targetPos - myPos
    local dist = diff:Length()

    if dist <= Config.AttackRange then
        -- 在攻击范围内 → 攻击
        char.state = "attacking"
        if char.attackCooldown <= 0 then
            Battle.PerformAttack(char, target)
            char.attackCooldown = Config.AttackCooldown
        end
    else
        -- 向目标移动
        char.state = "moving"
        local dir = diff:Normalized()
        local moveVec = dir * char.speed * dt
        char.node.position = myPos + moveVec

        -- 面向目标（绕Y轴旋转）
        local angle = math.atan(dir.x, dir.z)
        char.node.rotation = Quaternion(math.deg(angle), Vector3.UP)
    end
end

return M
