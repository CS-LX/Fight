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
    { id = "kite",       name = "游击 (打了就跑)" },
    { id = "assassin",   name = "刺客 (斩杀最弱)" },
    { id = "tank",       name = "坦克 (抱团集结)" },
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

--- 游击预设：攻击后立即后撤，保持距离再突进，打了就跑风筝战术
M.kite = {
    rootId = "root",
    nodes = {
        root   = { id = "root",   type = "ActivePriority", name = "抢占优先级", x = 60, y = 200 },
        -- 优先级1：血低逃跑
        seq_flee = { id = "seq_flee", type = "Sequence", name = "逃跑序列", x = 300, y = 40 },
        c_hplow  = { id = "c_hplow",  type = "Task", name = "血量低", taskName = "HPLow", x = 560, y = 20 },
        a_flee   = { id = "a_flee",   type = "Task", name = "逃跑", taskName = "Flee", x = 560, y = 60 },
        -- 优先级2：在攻击范围内 → 攻击 + 后撤
        seq_hit  = { id = "seq_hit",  type = "Sequence", name = "打撤序列", x = 300, y = 160 },
        c_enemy1 = { id = "c_enemy1", type = "Task", name = "有敌人", taskName = "HasEnemy", x = 560, y = 120 },
        c_range  = { id = "c_range",  type = "Task", name = "在攻击范围", taskName = "InAttackRange", x = 560, y = 160 },
        a_atk    = { id = "a_atk",    type = "Task", name = "攻击", taskName = "Attack", x = 560, y = 200 },
        a_retreat= { id = "a_retreat", type = "Task", name = "后撤", taskName = "Retreat", x = 560, y = 240 },
        -- 优先级3：敌人远 → 冲刺突进
        seq_dash = { id = "seq_dash", type = "Sequence", name = "突进序列", x = 300, y = 320 },
        c_enemy2 = { id = "c_enemy2", type = "Task", name = "有敌人", taskName = "HasEnemy", x = 560, y = 300 },
        c_far    = { id = "c_far",    type = "Task", name = "敌人较远", taskName = "EnemyFar", x = 560, y = 340 },
        a_dash   = { id = "a_dash",   type = "Task", name = "冲刺突进", taskName = "Dash", x = 560, y = 380 },
        -- 优先级4：普通追击
        seq_chase= { id = "seq_chase", type = "Sequence", name = "追击序列", x = 300, y = 460 },
        c_enemy3 = { id = "c_enemy3", type = "Task", name = "有敌人", taskName = "HasEnemy", x = 560, y = 440 },
        a_chase  = { id = "a_chase",  type = "Task", name = "追击", taskName = "Chase", x = 560, y = 480 },
        -- 优先级5：环绕走位
        a_strafe = { id = "a_strafe", type = "Task", name = "环绕走位", taskName = "Strafe", x = 300, y = 560 },
    },
    edges = {
        { from = "root", to = "seq_flee", order = 1 },
        { from = "root", to = "seq_hit", order = 2 },
        { from = "root", to = "seq_dash", order = 3 },
        { from = "root", to = "seq_chase", order = 4 },
        { from = "root", to = "a_strafe", order = 5 },
        { from = "seq_flee", to = "c_hplow", order = 1 },
        { from = "seq_flee", to = "a_flee", order = 2 },
        { from = "seq_hit", to = "c_enemy1", order = 1 },
        { from = "seq_hit", to = "c_range", order = 2 },
        { from = "seq_hit", to = "a_atk", order = 3 },
        { from = "seq_hit", to = "a_retreat", order = 4 },
        { from = "seq_dash", to = "c_enemy2", order = 1 },
        { from = "seq_dash", to = "c_far", order = 2 },
        { from = "seq_dash", to = "a_dash", order = 3 },
        { from = "seq_chase", to = "c_enemy3", order = 1 },
        { from = "seq_chase", to = "a_chase", order = 2 },
    },
}

--- 刺客预设：优先锁定并斩杀血量最低的目标
M.assassin = {
    rootId = "root",
    nodes = {
        root     = { id = "root",     type = "ActivePriority", name = "抢占优先级", x = 60, y = 200 },
        -- 优先级1：目标血低 → 冲刺+攻击（斩杀）
        seq_exec = { id = "seq_exec", type = "Sequence", name = "斩杀序列", x = 300, y = 60 },
        a_find   = { id = "a_find",   type = "Task", name = "锁定最弱", taskName = "FindWeakestEnemy", x = 560, y = 20 },
        c_elow   = { id = "c_elow",   type = "Task", name = "敌人血低", taskName = "EnemyHPLow", x = 560, y = 60 },
        a_dash   = { id = "a_dash",   type = "Task", name = "冲刺突进", taskName = "Dash", x = 560, y = 100 },
        a_atk1   = { id = "a_atk1",   type = "Task", name = "攻击", taskName = "Attack", x = 560, y = 140 },
        -- 优先级2：正常攻击范围 → 打
        seq_atk  = { id = "seq_atk",  type = "Sequence", name = "攻击序列", x = 300, y = 220 },
        c_enemy  = { id = "c_enemy",  type = "Task", name = "有敌人", taskName = "HasEnemy", x = 560, y = 200 },
        c_range  = { id = "c_range",  type = "Task", name = "在攻击范围", taskName = "InAttackRange", x = 560, y = 240 },
        a_atk2   = { id = "a_atk2",   type = "Task", name = "攻击", taskName = "Attack", x = 560, y = 280 },
        -- 优先级3：追击最弱
        a_chweak = { id = "a_chweak", type = "Task", name = "追击最弱", taskName = "ChaseWeakest", x = 300, y = 360 },
        -- 优先级4：巡逻
        a_patrol = { id = "a_patrol", type = "Task", name = "巡逻", taskName = "Patrol", x = 300, y = 460 },
    },
    edges = {
        { from = "root", to = "seq_exec", order = 1 },
        { from = "root", to = "seq_atk", order = 2 },
        { from = "root", to = "a_chweak", order = 3 },
        { from = "root", to = "a_patrol", order = 4 },
        { from = "seq_exec", to = "a_find", order = 1 },
        { from = "seq_exec", to = "c_elow", order = 2 },
        { from = "seq_exec", to = "a_dash", order = 3 },
        { from = "seq_exec", to = "a_atk1", order = 4 },
        { from = "seq_atk", to = "c_enemy", order = 1 },
        { from = "seq_atk", to = "c_range", order = 2 },
        { from = "seq_atk", to = "a_atk2", order = 3 },
    },
}

--- 坦克预设：抱团集结 + 被围就打 + 以少敌多时逃
M.tank = {
    rootId = "root",
    nodes = {
        root     = { id = "root",     type = "ActivePriority", name = "抢占优先级", x = 60, y = 200 },
        -- 优先级1：以少敌多 → 集结
        seq_out  = { id = "seq_out",  type = "Sequence", name = "被围集结", x = 300, y = 60 },
        c_outnum = { id = "c_outnum", type = "Task", name = "以少敌多", taskName = "IsOutnumbered", x = 560, y = 40 },
        a_rally  = { id = "a_rally",  type = "Task", name = "集结", taskName = "Rally", x = 560, y = 80 },
        -- 优先级2：范围内 → 攻击
        seq_atk  = { id = "seq_atk",  type = "Sequence", name = "攻击序列", x = 300, y = 200 },
        c_enemy  = { id = "c_enemy",  type = "Task", name = "有敌人", taskName = "HasEnemy", x = 560, y = 180 },
        c_range  = { id = "c_range",  type = "Task", name = "在攻击范围", taskName = "InAttackRange", x = 560, y = 220 },
        a_atk    = { id = "a_atk",    type = "Task", name = "攻击", taskName = "Attack", x = 560, y = 260 },
        -- 优先级3：有友军 → 追击（抱团进攻）
        seq_push = { id = "seq_push", type = "Sequence", name = "抱团推进", x = 300, y = 340 },
        c_ally   = { id = "c_ally",   type = "Task", name = "友军在范围内", taskName = "HasAllyInRange", x = 560, y = 320 },
        c_enemy2 = { id = "c_enemy2", type = "Task", name = "有敌人", taskName = "HasEnemy", x = 560, y = 360 },
        a_chase  = { id = "a_chase",  type = "Task", name = "追击", taskName = "Chase", x = 560, y = 400 },
        -- 优先级4：无友军 → 集结
        a_rally2 = { id = "a_rally2", type = "Task", name = "集结", taskName = "Rally", x = 300, y = 480 },
    },
    edges = {
        { from = "root", to = "seq_out", order = 1 },
        { from = "root", to = "seq_atk", order = 2 },
        { from = "root", to = "seq_push", order = 3 },
        { from = "root", to = "a_rally2", order = 4 },
        { from = "seq_out", to = "c_outnum", order = 1 },
        { from = "seq_out", to = "a_rally", order = 2 },
        { from = "seq_atk", to = "c_enemy", order = 1 },
        { from = "seq_atk", to = "c_range", order = 2 },
        { from = "seq_atk", to = "a_atk", order = 3 },
        { from = "seq_push", to = "c_ally", order = 1 },
        { from = "seq_push", to = "c_enemy2", order = 2 },
        { from = "seq_push", to = "a_chase", order = 3 },
    },
}

--- 根据 id 获取预设数据
---@param presetId string
---@return table|nil
function M.Get(presetId)
    return M[presetId]
end

return M
