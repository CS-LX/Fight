-- ============================================================================
-- data/bt_presets.lua - 行为树预设集合
-- ============================================================================
-- 每个预设包含完整的 { rootId, nodes, edges } 数据
-- 用途：CharacterMaker 预设选择 + 导出时嵌入角色配置

local M = {}

--- 预设列表（有序）
M.list = {
    { id = "aggressive", name = "激进 (攻击优先)" },
    { id = "defensive",  name = "防守 (血量优先)" },
    { id = "patrol",     name = "巡逻 (只巡逻)" },
}

--- 激进预设：攻击 > 追击 > 巡逻
M.aggressive = {
    rootId = "node_1",
    nodes = {
        node_1 = { id = "node_1", type = "ActivePriority", name = "抢占优先级", x = 60, y = 200 },
        node_2 = { id = "node_2", type = "Sequence", name = "攻击序列", x = 320, y = 60 },
        node_3 = { id = "node_3", type = "Task", name = "有敌人", x = 580, y = 20, taskName = "HasEnemy" },
        node_4 = { id = "node_4", type = "Task", name = "在攻击范围", x = 580, y = 80, taskName = "InAttackRange" },
        node_5 = { id = "node_5", type = "Task", name = "攻击", x = 580, y = 140, taskName = "Attack" },
        node_6 = { id = "node_6", type = "Sequence", name = "追击序列", x = 320, y = 240 },
        node_7 = { id = "node_7", type = "Task", name = "有敌人", x = 580, y = 220, taskName = "HasEnemy" },
        node_8 = { id = "node_8", type = "Task", name = "追击", x = 580, y = 280, taskName = "Chase" },
        node_9 = { id = "node_9", type = "Task", name = "巡逻", x = 320, y = 400, taskName = "Patrol" },
    },
    edges = {
        { from = "node_1", to = "node_2", order = 1 },
        { from = "node_1", to = "node_6", order = 2 },
        { from = "node_1", to = "node_9", order = 3 },
        { from = "node_2", to = "node_3", order = 1 },
        { from = "node_2", to = "node_4", order = 2 },
        { from = "node_2", to = "node_5", order = 3 },
        { from = "node_6", to = "node_7", order = 1 },
        { from = "node_6", to = "node_8", order = 2 },
    },
}

--- 防守预设：血低逃跑 > 近身才打 > 原地守卫
M.defensive = {
    rootId = "node_1",
    nodes = {
        node_1 = { id = "node_1", type = "ActivePriority", name = "抢占优先级", x = 60, y = 200 },
        -- 逃跑序列（最高优先级）
        node_2 = { id = "node_2", type = "Sequence", name = "逃跑序列", x = 320, y = 60 },
        node_3 = { id = "node_3", type = "Task", name = "血量低", x = 580, y = 30, taskName = "HPLow" },
        node_4 = { id = "node_4", type = "Task", name = "逃跑", x = 580, y = 90, taskName = "Flee" },
        -- 反击序列（被近身才打）
        node_5 = { id = "node_5", type = "Sequence", name = "反击序列", x = 320, y = 220 },
        node_6 = { id = "node_6", type = "Task", name = "有敌人", x = 580, y = 190, taskName = "HasEnemy" },
        node_7 = { id = "node_7", type = "Task", name = "在攻击范围", x = 580, y = 250, taskName = "InAttackRange" },
        node_8 = { id = "node_8", type = "Task", name = "攻击", x = 580, y = 310, taskName = "Attack" },
        -- 原地守卫
        node_9 = { id = "node_9", type = "Task", name = "守卫", x = 320, y = 380, taskName = "Guard" },
    },
    edges = {
        { from = "node_1", to = "node_2", order = 1 },
        { from = "node_1", to = "node_5", order = 2 },
        { from = "node_1", to = "node_9", order = 3 },
        { from = "node_2", to = "node_3", order = 1 },
        { from = "node_2", to = "node_4", order = 2 },
        { from = "node_5", to = "node_6", order = 1 },
        { from = "node_5", to = "node_7", order = 2 },
        { from = "node_5", to = "node_8", order = 3 },
    },
}

--- 纯巡逻预设：只巡逻不打架
M.patrol = {
    rootId = "node_1",
    nodes = {
        node_1 = { id = "node_1", type = "Sequence", name = "巡逻循环", x = 60, y = 200 },
        node_2 = { id = "node_2", type = "Task", name = "巡逻", x = 320, y = 200, taskName = "Patrol" },
    },
    edges = {
        { from = "node_1", to = "node_2", order = 1 },
    },
}

--- 根据 id 获取预设数据
---@param presetId string
---@return table|nil
function M.Get(presetId)
    return M[presetId]
end

return M
