-- ============================================================================
-- characters/CharRegistry.lua - 角色注册表（管理所有角色模块）
-- ============================================================================
-- 职责：加载预设角色、注册自定义角色、按ID查询角色模块
-- 支持：内置预设 + 用户自定义持久化角色

local CharModule = require("characters.CharModule")
local CharPersist = require("characters.CharPersist")

local M = {}

--- 已注册的角色模块 (id → CharModule)
---@type table<string, CharModule>
local registry_ = {}

--- 内置预设ID列表
local presetIds_ = {}

-- ============================================================================
-- 内置预设
-- ============================================================================

--- Wisdel 预设（默认角色）
local function CreateWisdelPreset()
    return {
        id = "wisdel",
        name = "Wisdel",
        config = {
            baseSpeed = 3.0,       -- 高速突进
            baseHP = 80,           -- 脆皮
            attackDamage = 15,     -- 高伤害
            attackRange = 1.0,     -- 近战刺客
            attackCooldown = 0.6,  -- 攻速快
            stopDistance = 0.5,    -- 贴脸输出
            collisionRadius = 0.3, -- 体型小巧灵活
        },
        art = {
            avatar = "image/edited_wisdel_avatar_20260529105147.png",
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
        },
        ai = {
            profile = "aggressive",
        },
    }
end

--- Bloody Wolf 预设（sprite_bone 团子角色）
local function CreateBloodyWolfPreset()
    return {
        id = "bloody_wolf",
        name = "Bloody Wolf",
        config = {
            baseSpeed = 1.8,       -- 缓慢笨重
            baseHP = 180,          -- 肉盾
            attackDamage = 12,     -- 稳定伤害
            attackRange = 1.4,     -- 体型大攻击范围广
            attackCooldown = 1.0,  -- 攻速慢
            stopDistance = 0.6,    -- 维持安全距离
            collisionRadius = 0.45,-- 体型大，推挤效果强
        },
        art = {
            mode = "sprite_bone",
            avatar = "image/Bunny.png",
            renderScale = 1.25,
            frames = {
                -- 待机：团子呼吸鼓涌（横向微胀+纵向微缩，交替）
                idle = {
                    duration = 1.2,
                    bones = { { id = "body", sprite = "bunny", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0, y = 0, rot = 0, scaleX = 1.0,  scaleY = 0.92 } },
                        ["0.3"] = { body = { x = 0, y = -2, rot = 0, scaleX = 0.95, scaleY = 1.05 } },
                        ["0.6"] = { body = { x = 0, y = 0, rot = 0, scaleX = 1.02, scaleY = 0.94 } },
                        ["0.9"] = { body = { x = 0, y = -1, rot = 0, scaleX = 0.97, scaleY = 1.02 } },
                        ["1.2"] = { body = { x = 0, y = 0, rot = 0, scaleX = 1.0,  scaleY = 0.92 } },
                    },
                },
                -- 移动：团子蹦跳前进（上下弹跳+落地压扁+微摇摆）
                move = {
                    duration = 0.5,
                    bones = { { id = "body", sprite = "bunny", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]    = { body = { x = 0, y = 0,   rot = -5,  scaleX = 1.1,  scaleY = 0.8 } },
                        ["0.15"] = { body = { x = 0, y = -8,  rot = 5,   scaleX = 0.9,  scaleY = 1.15 } },
                        ["0.3"]  = { body = { x = 0, y = 0,   rot = 5,   scaleX = 1.12, scaleY = 0.78 } },
                        ["0.4"]  = { body = { x = 0, y = -6,  rot = -3,  scaleX = 0.92, scaleY = 1.1 } },
                        ["0.5"]  = { body = { x = 0, y = 0,   rot = -5,  scaleX = 1.1,  scaleY = 0.8 } },
                    },
                },
                -- 攻击：用头猛撞（先蓄力后仰，再猛冲前顶）
                attack = {
                    duration = 0.6,
                    bones = { { id = "body", sprite = "bunny", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0,   y = 0,  rot = 0,   scaleX = 1.0,  scaleY = 1.0 } },
                        ["0.15"]= { body = { x = -4,  y = 2,  rot = -10, scaleX = 1.1,  scaleY = 0.85 } },
                        ["0.3"] = { body = { x = 10,  y = -2, rot = 15,  scaleX = 0.85, scaleY = 1.15 } },
                        ["0.45"]= { body = { x = 6,   y = 0,  rot = 5,   scaleX = 1.05, scaleY = 0.95 } },
                        ["0.6"] = { body = { x = 0,   y = 0,  rot = 0,   scaleX = 1.0,  scaleY = 1.0 } },
                    },
                },
                -- 受击：被撞后晃动
                hit = {
                    duration = 0.4,
                    bones = { { id = "body", sprite = "bunny", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0,  y = 0, rot = 0,   scaleX = 1.0,  scaleY = 1.0 } },
                        ["0.1"] = { body = { x = -5, y = 0, rot = -12, scaleX = 1.1,  scaleY = 0.9 } },
                        ["0.2"] = { body = { x = 3,  y = 0, rot = 8,   scaleX = 0.95, scaleY = 1.05 } },
                        ["0.3"] = { body = { x = -1, y = 0, rot = -3,  scaleX = 1.02, scaleY = 0.98 } },
                        ["0.4"] = { body = { x = 0,  y = 0, rot = 0,   scaleX = 1.0,  scaleY = 1.0 } },
                    },
                },
                -- 死亡：压扁倒地
                die = {
                    duration = 0.8,
                    bones = { { id = "body", sprite = "bunny", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0, y = 0,  rot = 0,   scaleX = 1.0, scaleY = 1.0 } },
                        ["0.3"] = { body = { x = 0, y = 2,  rot = 30,  scaleX = 1.2, scaleY = 0.7 } },
                        ["0.6"] = { body = { x = 2, y = 4,  rot = 70,  scaleX = 1.4, scaleY = 0.5 } },
                        ["0.8"] = { body = { x = 3, y = 5,  rot = 90,  scaleX = 1.5, scaleY = 0.4 } },
                    },
                },
                -- 放松：悠闲晃动
                relax = {
                    duration = 2.0,
                    bones = { { id = "body", sprite = "bunny", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                        ["0.5"] = { body = { x = 0, y = -1, rot = 3,  scaleX = 0.98, scaleY = 1.02 } },
                        ["1.0"] = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                        ["1.5"] = { body = { x = 0, y = -1, rot = -3, scaleX = 1.02, scaleY = 0.98 } },
                        ["2.0"] = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                    },
                },
            },
        },
        ai = {
            profile = "defensive",
            behaviourTree = {
                rootId = "node_1",
                nodes = {
                    node_1 = { id = "node_1", type = "ActivePriority", name = "抢占优先级", x = 60, y = 200 },
                    node_2 = { id = "node_2", type = "Sequence", name = "攻击序列", x = 319, y = 84 },
                    node_3 = { id = "node_3", type = "Task", name = "有敌人", taskName = "HasEnemy", x = 580, y = 20 },
                    node_4 = { id = "node_4", type = "Task", name = "在攻击范围", taskName = "InAttackRange", x = 580, y = 80 },
                    node_5 = { id = "node_5", type = "Task", name = "攻击", taskName = "Attack", x = 580, y = 140 },
                    node_6 = { id = "node_6", type = "Sequence", name = "追击序列", x = 320, y = 240 },
                    node_7 = { id = "node_7", type = "Task", name = "有敌人", taskName = "HasEnemy", x = 580, y = 220 },
                    node_8 = { id = "node_8", type = "Task", name = "追击", taskName = "Chase", x = 580, y = 280 },
                    node_9 = { id = "node_9", type = "Task", name = "驻守", taskName = "Guard", x = 320, y = 400 },
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
            },
        },
    }
end

--- Kisaki 预设（远程投掷手 - 扔可乐罐）
local function CreateKisakiPreset()
    return {
        id = "kisaki",
        name = "Kisaki",
        config = {
            baseSpeed = 2.2,       -- 中等偏慢（需要保持距离，不需要太快）
            baseHP = 100,          -- 中等血量（比刺客厚但不算肉）
            attackDamage = 10,     -- 单次伤害偏低（远程安全输出补偿）
            attackRange = 3.5,     -- 远程攻击距离
            attackCooldown = 1.2,  -- 冷却较长（投掷需要准备动作）
            stopDistance = 2.8,    -- 保持安全距离不贴脸
            collisionRadius = 0.3, -- 小体型
        },
        art = {
            mode = "sprite_bone",
            avatar = "image/Kisaki.png",
            renderScale = 1.6,
            frames = {
                -- 待机：小人抱着可乐罐轻微晃动
                idle = {
                    duration = 1.6,
                    bones = { { id = "body", sprite = "kisaki", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                        ["0.4"] = { body = { x = 0, y = -2, rot = 2,  scaleX = 1.0,  scaleY = 1.02 } },
                        ["0.8"] = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                        ["1.2"] = { body = { x = 0, y = -2, rot = -2, scaleX = 1.0,  scaleY = 1.02 } },
                        ["1.6"] = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                    },
                },
                -- 移动：小碎步跑动（轻盈弹跳）
                move = {
                    duration = 0.45,
                    bones = { { id = "body", sprite = "kisaki", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]    = { body = { x = 0, y = 0,   rot = -3, scaleX = 1.02, scaleY = 0.95 } },
                        ["0.12"] = { body = { x = 0, y = -6,  rot = 3,  scaleX = 0.95, scaleY = 1.08 } },
                        ["0.22"] = { body = { x = 0, y = 0,   rot = 3,  scaleX = 1.04, scaleY = 0.92 } },
                        ["0.34"] = { body = { x = 0, y = -5,  rot = -2, scaleX = 0.96, scaleY = 1.06 } },
                        ["0.45"] = { body = { x = 0, y = 0,   rot = -3, scaleX = 1.02, scaleY = 0.95 } },
                    },
                },
                -- 攻击：投掷动作（后仰蓄力 → 前倾甩出）
                attack = {
                    duration = 0.7,
                    bones = { { id = "body", sprite = "kisaki", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0,  y = 0,  rot = 0,   scaleX = 1.0,  scaleY = 1.0 } },
                        ["0.2"] = { body = { x = -6, y = -2, rot = -15, scaleX = 1.05, scaleY = 0.92 } },
                        ["0.35"]= { body = { x = 8,  y = -4, rot = 20,  scaleX = 0.9,  scaleY = 1.1 } },
                        ["0.5"] = { body = { x = 4,  y = 0,  rot = 8,   scaleX = 1.02, scaleY = 0.98 } },
                        ["0.7"] = { body = { x = 0,  y = 0,  rot = 0,   scaleX = 1.0,  scaleY = 1.0 } },
                    },
                },
                -- 受击：向后弹开晃动
                hit = {
                    duration = 0.4,
                    bones = { { id = "body", sprite = "kisaki", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0,  y = 0, rot = 0,   scaleX = 1.0,  scaleY = 1.0 } },
                        ["0.1"] = { body = { x = -6, y = 0, rot = -10, scaleX = 1.08, scaleY = 0.92 } },
                        ["0.2"] = { body = { x = 3,  y = 0, rot = 6,   scaleX = 0.96, scaleY = 1.04 } },
                        ["0.3"] = { body = { x = -1, y = 0, rot = -2,  scaleX = 1.02, scaleY = 0.98 } },
                        ["0.4"] = { body = { x = 0,  y = 0, rot = 0,   scaleX = 1.0,  scaleY = 1.0 } },
                    },
                },
                -- 死亡：向后倒下
                die = {
                    duration = 0.8,
                    bones = { { id = "body", sprite = "kisaki", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0, y = 0, rot = 0,   scaleX = 1.0, scaleY = 1.0 } },
                        ["0.3"] = { body = { x = -2, y = 2, rot = -25, scaleX = 1.1, scaleY = 0.85 } },
                        ["0.6"] = { body = { x = -4, y = 4, rot = -60, scaleX = 1.3, scaleY = 0.6 } },
                        ["0.8"] = { body = { x = -5, y = 5, rot = -80, scaleX = 1.4, scaleY = 0.5 } },
                    },
                },
                -- 放松：左右摇晃哼歌
                relax = {
                    duration = 2.0,
                    bones = { { id = "body", sprite = "kisaki", pivotX = 0, pivotY = 0 } },
                    keyframes = {
                        ["0"]   = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                        ["0.5"] = { body = { x = 2, y = -1, rot = 4,  scaleX = 1.0,  scaleY = 1.01 } },
                        ["1.0"] = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                        ["1.5"] = { body = { x = -2, y = -1, rot = -4, scaleX = 1.0,  scaleY = 1.01 } },
                        ["2.0"] = { body = { x = 0, y = 0,  rot = 0,  scaleX = 1.0,  scaleY = 1.0 } },
                    },
                },
            },
        },
        ai = {
            profile = "balanced",
            behaviourTree = {
                rootId = "node_1",
                nodes = {
                    node_1 = { id = "node_1", type = "ActivePriority", name = "根优先级" },
                    -- 优先级1: 敌人太近时快速逃跑（远程角色需要大范围感知 + 高速撤退）
                    node_2 = { id = "node_2", type = "Sequence", name = "快速逃跑序列" },
                    node_2a = { id = "node_2a", type = "Task", taskName = "HasEnemy" },
                    node_2b = { id = "node_2b", type = "Task", taskName = "EnemyClose",
                        params = { threshold = 2.5 },  -- 远程角色警戒距离更大
                    },
                    node_2c = { id = "node_2c", type = "Task", taskName = "Retreat",
                        params = { distance = 3.0, speedMul = 1.8 },  -- 大幅后撤 + 加速逃跑
                    },
                    -- 优先级2: 在射程内远程攻击
                    node_3 = { id = "node_3", type = "Sequence", name = "远程攻击序列" },
                    node_3a = { id = "node_3a", type = "Task", taskName = "HasEnemy" },
                    node_3b = { id = "node_3b", type = "Task", taskName = "InAttackRange" },
                    node_3c = { id = "node_3c", type = "Task", taskName = "RangedAttack",
                        params = {
                            bulletSpeed = 14,
                            bulletEffect = "image/Coke.png",
                            hitEffect = "",
                            muzzleEffect = "",
                            bulletColor = "#1a5276",
                            damageMultiplier = 1.0,
                            angularSpeed = 540,
                        },
                    },
                    -- 优先级3: 追击到射程
                    node_4 = { id = "node_4", type = "Sequence", name = "追击序列" },
                    node_4a = { id = "node_4a", type = "Task", taskName = "HasEnemy" },
                    node_4b = { id = "node_4b", type = "Task", taskName = "Chase" },
                    -- 优先级4: 无事巡逻
                    node_5 = { id = "node_5", type = "Task", taskName = "Patrol" },
                },
                edges = {
                    { from = "node_1", to = "node_2", order = 1 },
                    { from = "node_1", to = "node_3", order = 2 },
                    { from = "node_1", to = "node_4", order = 3 },
                    { from = "node_1", to = "node_5", order = 4 },
                    { from = "node_2", to = "node_2a", order = 1 },
                    { from = "node_2", to = "node_2b", order = 2 },
                    { from = "node_2", to = "node_2c", order = 3 },
                    { from = "node_3", to = "node_3a", order = 1 },
                    { from = "node_3", to = "node_3b", order = 2 },
                    { from = "node_3", to = "node_3c", order = 3 },
                    { from = "node_4", to = "node_4a", order = 1 },
                    { from = "node_4", to = "node_4b", order = 2 },
                },
            },
        },
    }
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化注册表（加载预设 + 恢复持久化角色）
function M.Init()
    registry_ = {}
    presetIds_ = {}

    -- 注册内置预设
    local wisdel = CreateWisdelPreset()
    M.Register(wisdel, true)

    local bloodyWolf = CreateBloodyWolfPreset()
    M.Register(bloodyWolf, true)

    local kisaki = CreateKisakiPreset()
    M.Register(kisaki, true)

    -- 恢复持久化的自定义角色
    local saved = CharPersist.LoadAll()
    for _, mod in ipairs(saved) do
        local valid, err = CharModule.Validate(mod)
        if valid then
            registry_[mod.id] = mod
            print("[CharRegistry] Loaded custom: " .. mod.id)
        else
            print("[CharRegistry] Skip invalid saved module: " .. (err or "unknown"))
        end
    end

    print("[CharRegistry] Init complete. Total: " .. M.GetCount() .. " characters")
end

--- 注册一个角色模块
---@param mod CharModule
---@param isPreset boolean|nil 是否为内置预设
---@return boolean success, string|nil error
function M.Register(mod, isPreset)
    local valid, err = CharModule.Validate(mod)
    if not valid then
        return false, err
    end
    registry_[mod.id] = mod
    if isPreset then
        table.insert(presetIds_, mod.id)
    end
    return true, nil
end

--- 注销角色模块（不能删除预设）
---@param id string
---@return boolean
function M.Unregister(id)
    if not registry_[id] then return false end
    -- 检查是否预设
    for _, pid in ipairs(presetIds_) do
        if pid == id then
            print("[CharRegistry] Cannot unregister preset: " .. id)
            return false
        end
    end
    registry_[id] = nil
    CharPersist.Delete(id)
    return true
end

--- 获取角色模块
---@param id string
---@return CharModule|nil
function M.Get(id)
    return registry_[id]
end

--- 获取所有角色ID列表
---@return string[]
function M.GetAllIds()
    local ids = {}
    for id, _ in pairs(registry_) do
        table.insert(ids, id)
    end
    table.sort(ids)
    return ids
end

--- 获取预设角色ID列表
---@return string[]
function M.GetPresetIds()
    return presetIds_
end

--- 获取自定义角色ID列表
---@return string[]
function M.GetCustomIds()
    local ids = {}
    for id, _ in pairs(registry_) do
        local isPreset = false
        for _, pid in ipairs(presetIds_) do
            if pid == id then isPreset = true; break end
        end
        if not isPreset then
            table.insert(ids, id)
        end
    end
    table.sort(ids)
    return ids
end

--- 判断是否为预设角色
---@param id string
---@return boolean
function M.IsPreset(id)
    for _, pid in ipairs(presetIds_) do
        if pid == id then return true end
    end
    return false
end

--- 获取注册数量
---@return number
function M.GetCount()
    local count = 0
    for _ in pairs(registry_) do count = count + 1 end
    return count
end

--- 保存自定义角色（注册 + 持久化）
---@param mod CharModule
---@return boolean success, string|nil error
function M.SaveCustom(mod, isPreset)
    local ok, err = M.Register(mod, false)
    if not ok then return false, err end
    CharPersist.Save(mod)
    return true, nil
end

--- 当前使用的角色 ID（外部可设置，默认返回第一个自定义角色或首个预设）
---@type string|nil
local currentId_ = nil

--- 设置当前使用的角色 ID
---@param id string
function M.SetCurrentId(id)
    currentId_ = id
end

--- 获取当前使用的角色 ID
---@return string|nil
function M.GetCurrentId()
    if currentId_ and registry_[currentId_] then
        return currentId_
    end
    -- 优先返回第一个自定义角色
    local customIds = M.GetCustomIds()
    if #customIds > 0 then return customIds[1] end
    -- 否则返回第一个预设
    if #presetIds_ > 0 then return presetIds_[1] end
    return nil
end

return M
