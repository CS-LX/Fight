-- ============================================================================
-- data/default_bt.lua - 默认行为树数据（数据驱动）
-- ============================================================================
-- 对应 AI 逻辑：ActivePriority → [攻击序列, 追击序列, 巡逻]
-- 此文件同时被 AI.lua（运行时）和 CharacterMaker（编辑器可视化）使用

return {
    rootId = "node_1",
    nodes = {
        -- 根节点：抢占优先级（最左侧）
        node_1 = { id = "node_1", type = "ActivePriority", name = "抢占优先级", x = 60, y = 200 },
        -- 攻击序列（中间层，上方）
        node_2 = { id = "node_2", type = "Sequence", name = "攻击序列", x = 320, y = 60 },
        node_3 = { id = "node_3", type = "Task", name = "有敌人", x = 580, y = 20, taskName = "HasEnemy" },
        node_4 = { id = "node_4", type = "Task", name = "在攻击范围", x = 580, y = 80, taskName = "InAttackRange" },
        node_5 = { id = "node_5", type = "Task", name = "攻击", x = 580, y = 140, taskName = "Attack" },
        -- 追击序列（中间层，中间）
        node_6 = { id = "node_6", type = "Sequence", name = "追击序列", x = 320, y = 240 },
        node_7 = { id = "node_7", type = "Task", name = "有敌人", x = 580, y = 220, taskName = "HasEnemy" },
        node_8 = { id = "node_8", type = "Task", name = "追击", x = 580, y = 280, taskName = "Chase" },
        -- 巡逻（中间层，下方）
        node_9 = { id = "node_9", type = "Task", name = "巡逻", x = 320, y = 400, taskName = "Patrol" },
    },
    edges = {
        -- 根 → 三个子分支（order 决定优先级）
        { from = "node_1", to = "node_2", order = 1 },  -- 攻击（最高优先级）
        { from = "node_1", to = "node_6", order = 2 },  -- 追击
        { from = "node_1", to = "node_9", order = 3 },  -- 巡逻（最低）
        -- 攻击序列的子节点
        { from = "node_2", to = "node_3", order = 1 },
        { from = "node_2", to = "node_4", order = 2 },
        { from = "node_2", to = "node_5", order = 3 },
        -- 追击序列的子节点
        { from = "node_6", to = "node_7", order = 1 },
        { from = "node_6", to = "node_8", order = 2 },
    },
}
