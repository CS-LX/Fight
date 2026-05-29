-- ============================================================================
-- Battle.lua - 战斗系统（攻击执行 + Spine动画切换 + 死亡动画）
-- ============================================================================

local Config = require("Config")
local Character = require("Character")

local M = {}

-- 死亡动画时长（秒）
local DEATH_DURATION = 1.2

--- 设置 Spine 动画（避免重复设置同一动画）
---@param char table
---@param animName string
---@param loop boolean
local function SetAnim(char, animName, loop)
    if char.currentAnim == animName then return end
    if char.spine then
        char.spine:SetAnimation(animName, loop)
        char.currentAnim = animName
    end
end

--- 执行攻击
---@param attacker table
---@param target table
function M.PerformAttack(attacker, target)
    target.hp = target.hp - Config.AttackDamage

    -- 攻击动画
    SetAnim(attacker, Character.Anim.Attack, false)
    attacker.animTimer = 0.6

    if target.hp <= 0 then
        target.hp = 0
        target.state = "dying"
        target.deathTimer = DEATH_DURATION
        -- 播放死亡动画
        SetAnim(target, Character.Anim.Die, false)
    else
        -- 受击反馈
        SetAnim(target, Character.Anim.Hit, false)
        target.animTimer = 0.3
    end
end

--- 更新角色动画状态
---@param char table
---@param dt number
function M.UpdateAnimation(char, dt)
    if char.state == "dead" then return end

    -- ===== 死亡动画 =====
    if char.state == "dying" then
        char.deathTimer = char.deathTimer - dt

        -- 淡出效果：通过透明度
        local progress = 1.0 - math.max(0, char.deathTimer / DEATH_DURATION)
        if char.spine then
            local alpha = 1.0 - progress * 0.8
            char.spine:SetColor(1, 1, 1, alpha)
        end

        -- 下沉（整体赋值 Vector3）
        local pos = char.worldPos
        char.worldPos = Vector3(pos.x, pos.y - dt * 0.5, pos.z)

        -- 动画结束 → 彻底消失
        if char.deathTimer <= 0 then
            char.state = "dead"
            if char.spine then
                char.spine:SetVisible(false)
            end
        end
        return
    end

    -- ===== 正常动画 =====
    char.animTimer = math.max(0, char.animTimer - dt)

    -- 攻击/受击动画结束后恢复
    if char.animTimer <= 0 then
        if char.state == "moving" then
            SetAnim(char, Character.Anim.Move, true)
        elseif char.state == "attacking" then
            SetAnim(char, Character.Anim.Idle, true)
        end
    end

    -- 更新朝向（直接修改 props.flipX，渲染时会读取）
    if char.spine then
        char.spine.props.flipX = not char.facingRight
    end
end

return M
