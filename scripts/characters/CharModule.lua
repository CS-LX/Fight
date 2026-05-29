-- ============================================================================
-- characters/CharModule.lua - 角色模块定义格式
-- ============================================================================
-- 角色模块是一个自包含的数据结构，包含：
--   config: 战斗属性（速度、血量、攻击力等）
--   art:    美术资源引用（Spine 路径、动画映射）
--   ai:     AI 行为配置（行为树模板名）

---@class CharModule
---@field id string 唯一标识
---@field name string 显示名称
---@field config CharModuleConfig 战斗配置
---@field art CharModuleArt 美术配置
---@field ai CharModuleAI AI 配置

---@class CharModuleConfig
---@field baseSpeed number 移动速度 m/s
---@field baseHP number 最大血量
---@field attackDamage number 攻击伤害
---@field attackRange number 攻击范围 m
---@field attackCooldown number 攻击冷却 s

---@class CharModuleArt
---@field spineSrc string Spine 骨骼文件路径
---@field pma boolean 预乘 Alpha
---@field anims table<string, string> 状态→动画名映射
---@field renderScale number 渲染缩放系数
---@field tint {r:number, g:number, b:number}|nil RGB 染色 (0~1)
---@field scaleX number|nil 水平体型缩放 (默认1.0)
---@field scaleY number|nil 垂直体型缩放 (默认1.0)
---@field animSpeed number|nil 动画播放速率 (默认1.0)
---@field glowColor {r:number, g:number, b:number}|nil 光环颜色 (nil=无光环)

---@class CharModuleAI
---@field profile string AI 行为模板 ("aggressive"|"balanced"|"defensive")

local M = {}

--- 创建一个默认角色模块
---@param id string
---@param name string
---@return CharModule
function M.CreateDefault(id, name)
    return {
        id = id,
        name = name or "Unnamed",
        config = {
            baseSpeed = 2.5,
            baseHP = 100,
            attackDamage = 10,
            attackRange = 1.2,
            attackCooldown = 0.8,
        },
        art = {
            spineSrc = "spine/build_char_1035_wisdel_game_9/build_char_1035_wisdel_game_9.skel",
            pma = true,
            anims = {
                idle = "Default",
                move = "Move",
                attack = "Interact",
                hit = "Interact",
                die = "Sleep",
                relax = "Relax",
            },
            renderScale = 0.30,
            tint = { r = 1.0, g = 1.0, b = 1.0 },
            scaleX = 1.0,
            scaleY = 1.0,
            animSpeed = 1.0,
            glowColor = nil,
        },
        ai = {
            profile = "aggressive",
        },
    }
end

--- 验证角色模块数据完整性
---@param mod table
---@return boolean valid, string|nil error
function M.Validate(mod)
    if not mod.id or mod.id == "" then return false, "missing id" end
    if not mod.name then return false, "missing name" end
    if not mod.config then return false, "missing config" end
    if not mod.art then return false, "missing art" end
    if not mod.art.spineSrc then return false, "missing art.spineSrc" end
    if not mod.art.anims then return false, "missing art.anims" end
    if not mod.ai then return false, "missing ai" end
    return true, nil
end

--- 序列化为可持久化的 table（纯数据，无函数/元表）
---@param mod CharModule
---@return table
function M.Serialize(mod)
    return {
        id = mod.id,
        name = mod.name,
        config = {
            baseSpeed = mod.config.baseSpeed,
            baseHP = mod.config.baseHP,
            attackDamage = mod.config.attackDamage,
            attackRange = mod.config.attackRange,
            attackCooldown = mod.config.attackCooldown,
        },
        art = {
            spineSrc = mod.art.spineSrc,
            pma = mod.art.pma,
            anims = mod.art.anims,
            renderScale = mod.art.renderScale,
            tint = mod.art.tint,
            scaleX = mod.art.scaleX,
            scaleY = mod.art.scaleY,
            animSpeed = mod.art.animSpeed,
            glowColor = mod.art.glowColor,
        },
        ai = {
            profile = mod.ai.profile,
        },
    }
end

--- 从反序列化数据恢复角色模块（带默认值填充）
---@param data table
---@return CharModule
function M.Deserialize(data)
    local default = M.CreateDefault(data.id or "unknown", data.name)
    -- 合并 config
    if data.config then
        for k, v in pairs(data.config) do
            default.config[k] = v
        end
    end
    -- 合并 art
    if data.art then
        if data.art.spineSrc then default.art.spineSrc = data.art.spineSrc end
        if data.art.pma ~= nil then default.art.pma = data.art.pma end
        if data.art.anims then default.art.anims = data.art.anims end
        if data.art.renderScale then default.art.renderScale = data.art.renderScale end
        if data.art.tint then default.art.tint = data.art.tint end
        if data.art.scaleX then default.art.scaleX = data.art.scaleX end
        if data.art.scaleY then default.art.scaleY = data.art.scaleY end
        if data.art.animSpeed then default.art.animSpeed = data.art.animSpeed end
        if data.art.glowColor then default.art.glowColor = data.art.glowColor end
    end
    -- 合并 ai
    if data.ai then
        if data.ai.profile then default.ai.profile = data.ai.profile end
    end
    return default
end

return M
