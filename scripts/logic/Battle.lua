-- ============================================================================
-- logic/Battle.lua - 战斗系统（纯逻辑：伤害计算 + 状态切换 + 动画状态驱动）
-- ============================================================================
-- 不触碰 UI，只修改角色逻辑数据中的 state / animState / hp 等字段
-- 表现层（CharRender）根据 animState 播放对应动画

local Config = require("Config")

local M = {}

-- 死亡动画时长（秒）
M.DEATH_DURATION = 1.2

--- 执行攻击（纯逻辑，伤害从角色模块读取）
---@param attacker table
---@param target table
function M.PerformAttack(attacker, target)
    local damage = attacker.attackDamage or Config.AttackDamage
    target.hp = target.hp - damage

    -- 设置攻击动画状态
    attacker.animState = "attack"
    attacker.animTimer = 0.6

    if target.hp <= 0 then
        target.hp = 0
        target.state = "dying"
        target.deathTimer = M.DEATH_DURATION
        target.animState = "die"
    else
        -- 受击
        target.animState = "hit"
        target.animTimer = 0.3
        target.hitFlag = true  -- 渲染层消费后清除
    end
end

--- 更新角色逻辑状态（每帧调用）
---@param char table
---@param dt number
function M.UpdateState(char, dt)
    if char.state == "dead" then return end

    -- ===== 死亡逻辑 =====
    if char.state == "dying" then
        char.deathTimer = char.deathTimer - dt
        -- 下沉
        local pos = char.worldPos
        char.worldPos = Vector3(pos.x, pos.y - dt * 0.5, pos.z)
        -- 时间到 → 标记死亡
        if char.deathTimer <= 0 then
            char.state = "dead"
        end
        return
    end

    -- ===== 正常状态 =====
    char.animTimer = math.max(0, char.animTimer - dt)

    -- 动画锁定结束后，根据 state 恢复 animState
    if char.animTimer <= 0 then
        if char.state == "moving" then
            char.animState = "move"
        elseif char.state == "attacking" then
            char.animState = "idle"
        end
    end
end

return M
