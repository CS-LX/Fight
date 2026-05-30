-- ============================================================================
-- data/asset_library.lua - 素材库静态索引
-- ============================================================================
-- 列出所有可用的 Spine 文件和精灵素材
-- 编辑器通过此索引展示可选素材，无需动态扫描文件系统

local M = {}

--- Spine 文件列表
M.spines = {
    {
        id = "wisdel",
        name = "Wisdel (默认)",
        src = "spine/build_char_1035_wisdel_game_9/build_char_1035_wisdel_game_9.skel",
        pma = true,
        anims = { "Default", "Move", "Interact", "Sleep", "Relax" },
    },
    {
        id = "originium_slug",
        name = "源石虫",
        src = "spine/originium_slug/originium_slug.skel",
        pma = true,
        anims = { "Idle", "Move_Begin", "Move_End", "Attack", "Die", "Default" },
    },
}

--- 精灵素材分类
--- category: head / body / arm / leg / weapon / accessory / character
M.sprites = {
    -- 角色（图片素材）
    { id = "bunny", name = "Bunny", category = "character", image = "image/Bunny.png", width = 48, height = 48 },
    { id = "kisaki", name = "Kisaki", category = "character", image = "image/Kisaki.png", width = 48, height = 48 },
    { id = "kisaki_nocoke", name = "Kisaki (No Coke)", category = "character", image = "image/Kisaki_NoCoke.png", width = 48, height = 48 },
    -- 投射物
    { id = "coke", name = "Coke Can", category = "projectile", image = "image/Coke.png", width = 24, height = 24 },
    -- 头部
    { id = "head_round",   name = "圆头",     category = "head",   color = {220, 180, 140}, width = 24, height = 24 },
    { id = "head_square",  name = "方头",     category = "head",   color = {200, 160, 120}, width = 22, height = 22 },
    { id = "head_tri",     name = "三角头",   category = "head",   color = {180, 200, 140}, width = 24, height = 20 },
    -- 身体
    { id = "body_rect",    name = "方块身体", category = "body",   color = {100, 130, 200}, width = 28, height = 36 },
    { id = "body_round",   name = "圆形身体", category = "body",   color = {120, 150, 220}, width = 30, height = 30 },
    { id = "body_slim",    name = "纤细身体", category = "body",   color = {90, 120, 180},  width = 20, height = 40 },
    -- 手臂
    { id = "arm_normal",   name = "普通手臂", category = "arm",    color = {220, 180, 140}, width = 10, height = 28 },
    { id = "arm_strong",   name = "粗壮手臂", category = "arm",    color = {200, 160, 120}, width = 14, height = 30 },
    { id = "arm_thin",     name = "细手臂",   category = "arm",    color = {230, 190, 150}, width = 8,  height = 26 },
    -- 腿部
    { id = "leg_normal",   name = "普通腿",   category = "leg",    color = {80, 100, 160},  width = 12, height = 32 },
    { id = "leg_thick",    name = "粗腿",     category = "leg",    color = {70, 90, 150},   width = 16, height = 30 },
    { id = "leg_thin",     name = "细腿",     category = "leg",    color = {90, 110, 170},  width = 10, height = 34 },
    -- 武器
    { id = "wpn_sword",    name = "剑",       category = "weapon", color = {200, 200, 210}, width = 8,  height = 36 },
    { id = "wpn_staff",    name = "法杖",     category = "weapon", color = {160, 100, 200}, width = 6,  height = 40 },
    { id = "wpn_shield",   name = "盾",       category = "weapon", color = {180, 160, 60},  width = 20, height = 24 },
    -- 装饰
    { id = "acc_hat",      name = "帽子",     category = "accessory", color = {200, 60, 60},  width = 26, height = 14 },
    { id = "acc_cape",     name = "披风",     category = "accessory", color = {140, 40, 180}, width = 24, height = 34 },
}

--- 按分类获取素材列表
---@param category string
---@return table[]
function M.GetSpritesByCategory(category)
    local result = {}
    for _, s in ipairs(M.sprites) do
        if s.category == category then
            result[#result + 1] = s
        end
    end
    return result
end

--- 按 ID 获取素材信息
---@param spriteId string
---@return table|nil
function M.GetSprite(spriteId)
    for _, s in ipairs(M.sprites) do
        if s.id == spriteId then return s end
    end
    return nil
end

--- 按 ID 获取 Spine 信息
---@param spineId string
---@return table|nil
function M.GetSpine(spineId)
    for _, s in ipairs(M.spines) do
        if s.id == spineId then return s end
    end
    return nil
end

--- 素材分类列表（用于编辑器 UI）
M.categories = {
    { id = "character", name = "角色" },
    { id = "head",      name = "头部" },
    { id = "body",      name = "身体" },
    { id = "arm",       name = "手臂" },
    { id = "leg",       name = "腿部" },
    { id = "weapon",    name = "武器" },
    { id = "accessory", name = "装饰" },
}

return M
