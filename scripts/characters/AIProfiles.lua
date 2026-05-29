-- ============================================================================
-- characters/AIProfiles.lua - AI 行为模板（profile → 行为树参数）
-- ============================================================================
-- 每个 profile 定义行为树的参数差异：
--   aggressive: 高攻击欲，低巡逻概率，追击更快
--   balanced:   均衡行为
--   defensive:  保守，走位多，攻击冷却更长

local M = {}

---@class AIProfileParams
---@field chaseSpeedMul number 追击速度倍率
---@field patrolSpeedMul number 巡逻速度倍率
---@field attackRangeMul number 攻击范围倍率
---@field cooldownMul number 攻击冷却倍率
---@field retreatAfterAttack boolean 攻击后后撤

--- 预定义行为模板
---@type table<string, AIProfileParams>
M.Profiles = {
    aggressive = {
        chaseSpeedMul = 1.2,      -- 追击更快
        patrolSpeedMul = 0.6,     -- 巡逻慢（不爱巡逻，更爱打）
        attackRangeMul = 1.0,     -- 标准攻击范围
        cooldownMul = 0.8,        -- 冷却更短（出手更频繁）
        retreatAfterAttack = false,
    },
    balanced = {
        chaseSpeedMul = 1.0,
        patrolSpeedMul = 0.5,
        attackRangeMul = 1.0,
        cooldownMul = 1.0,
        retreatAfterAttack = false,
    },
    defensive = {
        chaseSpeedMul = 0.8,      -- 追击慢（不急着上）
        patrolSpeedMul = 0.7,     -- 巡逻多
        attackRangeMul = 0.9,     -- 攻击范围略短（更保守）
        cooldownMul = 1.3,        -- 冷却更长
        retreatAfterAttack = true, -- 打完后撤
    },
}

--- 获取 profile 参数（不存在则返回 balanced）
---@param profileName string
---@return AIProfileParams
function M.Get(profileName)
    return M.Profiles[profileName] or M.Profiles.balanced
end

--- 获取所有可用 profile 名称
---@return string[]
function M.GetNames()
    local names = {}
    for name, _ in pairs(M.Profiles) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return M
