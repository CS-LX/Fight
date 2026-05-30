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
---@field mode "spine"|"sprite_bone" 渲染模式
---@field spineSrc string Spine 骨骼文件路径 (spine模式)
---@field pma boolean 预乘 Alpha (spine模式)
---@field anims table<string, string> 状态→动画名映射 (spine模式)
---@field renderScale number 渲染缩放系数
---@field tint {r:number, g:number, b:number}|nil RGB 染色 (0~1)
---@field scaleX number|nil 水平体型缩放 (默认1.0)
---@field scaleY number|nil 垂直体型缩放 (默认1.0)
---@field animSpeed number|nil 动画播放速率 (默认1.0)
---@field glowColor {r:number, g:number, b:number}|nil 光环颜色 (nil=无光环)
---@field frames table<string, SpritePhaseData>|nil 各阶段骨骼帧数据 (sprite_bone模式)

---@class SpritePhaseData
---@field duration number 动画总时长(秒)
---@field bones SpriteBone[] 骨骼列表(含层级)
---@field keyframes table<number, table<string, BoneKeyframe>> 时间点→骨骼ID→变换

---@class SpriteBone
---@field id string 骨骼标识
---@field sprite string 素材ID (对应asset_library中的sprite id)
---@field parent string|nil 父骨骼ID (nil=根骨骼)
---@field pivotX number|nil 锚点X偏移 (默认0)
---@field pivotY number|nil 锚点Y偏移 (默认0)

---@class BoneKeyframe
---@field x number X偏移
---@field y number Y偏移
---@field rot number 旋转角度(度)
---@field scaleX number|nil X缩放 (默认1)
---@field scaleY number|nil Y缩放 (默认1)

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
            mode = "spine",
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
            frames = nil, -- sprite_bone模式才使用
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
    if not mod.ai then return false, "missing ai" end

    local mode = mod.art.mode or "spine"
    if mode == "spine" then
        if not mod.art.spineSrc then return false, "missing art.spineSrc" end
        if not mod.art.anims then return false, "missing art.anims" end
    elseif mode == "sprite_bone" then
        if not mod.art.frames then return false, "missing art.frames" end
        -- 至少有idle阶段
        if not mod.art.frames.idle then return false, "missing art.frames.idle" end
    else
        return false, "unknown art.mode: " .. tostring(mode)
    end
    return true, nil
end

--- 序列化为可持久化的 table（纯数据，无函数/元表）
---@param mod CharModule
---@return table
function M.Serialize(mod)
    local artData = {
        mode = mod.art.mode or "spine",
        avatar = mod.art.avatar,
        renderScale = mod.art.renderScale,
        tint = mod.art.tint,
        scaleX = mod.art.scaleX,
        scaleY = mod.art.scaleY,
        animSpeed = mod.art.animSpeed,
        glowColor = mod.art.glowColor,
    }

    if artData.mode == "spine" then
        artData.spineSrc = mod.art.spineSrc
        artData.pma = mod.art.pma
        artData.anims = mod.art.anims
    elseif artData.mode == "sprite_bone" then
        artData.frames = mod.art.frames
    end

    local aiData = {
        profile = mod.ai.profile,
    }
    if mod.ai.behaviourTree then
        aiData.behaviourTree = mod.ai.behaviourTree
    end

    return {
        id = mod.id,
        name = mod.name,
        config = {
            baseSpeed = mod.config.baseSpeed,
            baseHP = mod.config.baseHP,
            attackDamage = mod.config.attackDamage,
            attackRange = mod.config.attackRange,
            attackCooldown = mod.config.attackCooldown,
            stopDistance = mod.config.stopDistance,
            collisionRadius = mod.config.collisionRadius,
        },
        art = artData,
        ai = aiData,
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
        default.art.mode = data.art.mode or "spine"
        -- 通用字段
        if data.art.avatar then default.art.avatar = data.art.avatar end
        if data.art.renderScale then default.art.renderScale = data.art.renderScale end
        if data.art.tint then default.art.tint = data.art.tint end
        if data.art.scaleX then default.art.scaleX = data.art.scaleX end
        if data.art.scaleY then default.art.scaleY = data.art.scaleY end
        if data.art.animSpeed then default.art.animSpeed = data.art.animSpeed end
        if data.art.glowColor then default.art.glowColor = data.art.glowColor end
        -- spine模式专属
        if data.art.spineSrc then default.art.spineSrc = data.art.spineSrc end
        if data.art.pma ~= nil then default.art.pma = data.art.pma end
        if data.art.anims then default.art.anims = data.art.anims end
        -- sprite_bone模式专属
        if data.art.frames then default.art.frames = data.art.frames end
    end
    -- 合并 ai
    if data.ai then
        if data.ai.profile then default.ai.profile = data.ai.profile end
        if data.ai.behaviourTree then default.ai.behaviourTree = data.ai.behaviourTree end
    end
    return default
end

--- 创建默认的 sprite_bone 阶段数据
---@param phase string 阶段名 (idle/move/attack/hit/die/relax)
---@return SpritePhaseData
function M.CreateDefaultPhase(phase)
    return {
        duration = 1.0,
        bones = {
            { id = "body", sprite = "body_rect", parent = nil, pivotX = 0, pivotY = 0 },
            { id = "head", sprite = "head_round", parent = "body", pivotX = 0, pivotY = -30 },
            { id = "arm_l", sprite = "arm_normal", parent = "body", pivotX = -16, pivotY = -4 },
            { id = "arm_r", sprite = "arm_normal", parent = "body", pivotX = 16, pivotY = -4 },
            { id = "leg_l", sprite = "leg_normal", parent = "body", pivotX = -6, pivotY = 36 },
            { id = "leg_r", sprite = "leg_normal", parent = "body", pivotX = 6, pivotY = 36 },
        },
        keyframes = {
            [0.0] = {
                body = { x = 0, y = 0, rot = 0 },
                head = { x = 0, y = 0, rot = 0 },
                arm_l = { x = 0, y = 0, rot = 0 },
                arm_r = { x = 0, y = 0, rot = 0 },
                leg_l = { x = 0, y = 0, rot = 0 },
                leg_r = { x = 0, y = 0, rot = 0 },
            },
        },
    }
end

--- 创建完整的 sprite_bone 默认帧集（所有阶段）
---@return table<string, SpritePhaseData>
function M.CreateDefaultFrames()
    local phases = { "idle", "move", "attack", "hit", "die", "relax" }
    local frames = {}
    for _, phase in ipairs(phases) do
        frames[phase] = M.CreateDefaultPhase(phase)
    end
    return frames
end

--- 动画阶段列表
M.PHASES = { "idle", "move", "attack", "hit", "die", "relax" }

--- 阶段中文名映射
M.PHASE_NAMES = {
    idle = "待机",
    move = "移动",
    attack = "攻击",
    hit = "受击",
    die = "死亡",
    relax = "放松",
}

return M
