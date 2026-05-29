-- ============================================================================
-- Battle.lua - 战斗系统（攻击执行 + 动画更新 + 死亡动画）
-- ============================================================================

local Config = require("Config")

local M = {}

-- 死亡动画时长（秒）
local DEATH_DURATION = 1.0

--- 执行攻击
---@param attacker table
---@param target table
function M.PerformAttack(attacker, target)
    target.hp = target.hp - Config.AttackDamage

    -- 攻击动画：设置计时器
    attacker.animTimer = 0.3

    if target.hp <= 0 then
        target.hp = 0
        target.state = "dying"
        target.deathTimer = DEATH_DURATION
    end
end

--- 更新角色动画（含死亡动画）
---@param char table
---@param dt number
function M.UpdateAnimation(char, dt)
    if char.state == "dead" then return end

    -- ===== 死亡动画 =====
    if char.state == "dying" then
        char.deathTimer = char.deathTimer - dt

        -- 动画进度 0→1
        local progress = 1.0 - math.max(0, char.deathTimer / DEATH_DURATION)

        -- 向后倒下（绕X轴旋转至90度）
        local fallAngle = progress * 90
        char.node.rotation = char.node.rotation * Quaternion(fallAngle * dt * 3, Vector3.RIGHT)

        -- 缩小
        local shrink = 1.0 - progress * 0.6
        char.node.scale = Vector3(shrink, shrink, shrink)

        -- 下沉到地面以下
        local pos = char.node.position
        char.node.position = Vector3(pos.x, pos.y - dt * 0.8, pos.z)

        -- 动画结束 → 彻底消失
        if char.deathTimer <= 0 then
            char.state = "dead"
            char.node:SetEnabled(false)
        end
        return
    end

    -- ===== 正常动画 =====
    char.animTimer = math.max(0, char.animTimer - dt)

    local bodyNode = char.node:GetChild("Body")
    local weaponNode = char.node:GetChild("Weapon")

    if char.animTimer > 0 then
        -- 攻击动画：武器挥动
        local t = char.animTimer / 0.3
        weaponNode.rotation = Quaternion(-60 * t, Vector3.RIGHT)
    else
        -- 待机/走路轻微摆动
        if char.state == "moving" then
            local bobAmount = math.sin(time.elapsedTime * 8 + char.speed * 100) * 0.05
            bodyNode.position = Vector3(0, 0.5 + bobAmount, 0)
        else
            bodyNode.position = Vector3(0, 0.5, 0)
            weaponNode.rotation = Quaternion(0, 0, 0)
        end
    end
end

return M
