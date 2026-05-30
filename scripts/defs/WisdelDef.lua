-- ============================================================================
-- defs/WisdelDef.lua - 角色定义：Wisdel（当前唯一角色类型）
-- ============================================================================
-- 角色定义包含：外观资源、动画映射、元数据
-- 逻辑层和表现层各自读取需要的字段

---@class CharDef
---@field id string 角色类型ID
---@field name string 角色显示名
---@field spineSrc string Spine 资源路径
---@field anims table<string, string> 状态→动画名映射
---@field renderScale number 角色渲染缩放（相对于屏幕高度的比例）
---@field pma boolean 预乘Alpha

local M = {
    id = "wisdel",
    name = "维维美",

    -- Spine 资源
    spineSrc = "spine/build_char_1035_wisdel_game_9/build_char_1035_wisdel_game_9.skel",
    pma = true,

    -- 动画映射：逻辑状态 → Spine 动画名
    anims = {
        idle    = "Default",
        move    = "Move",
        attack  = "Interact",
        hit     = "Interact",
        die     = "Sleep",
        relax   = "Relax",
    },

    -- 元数据
    renderScale = 0.30,    -- 直接 Spine 缩放系数

    -- 逻辑属性默认值（可被全局 Config 覆盖）
    baseSpeed = 2.5,
    baseHP = 100,
}

return M
