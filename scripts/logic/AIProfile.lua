-- ============================================================================
-- logic/AIProfile.lua - AI Profile 数据模块
-- ============================================================================
-- 职责：为 AI 对手分配个性化信息（头像、昵称、等级描述）
-- 按子力/难度分层匹配合适的 Profile
-- ============================================================================

local M = {}

-- ============================================================================
-- 头像资源池（对应 assets/profiles/ 下的图片）
-- ============================================================================
-- 分为4个类别，每类有对应的头像列表

local AVATAR_POOLS = {
    anime = {}, -- anime_01 ~ anime_30
    pet   = {}, -- pet_01 ~ pet_20
    meme  = {}, -- meme_01 ~ meme_25
    art   = {}, -- art_01 ~ art_25
}

-- 自动填充头像路径
for i = 1, 30 do
    AVATAR_POOLS.anime[i] = string.format("profiles/anime_%02d.png", i)
end
for i = 1, 20 do
    AVATAR_POOLS.pet[i] = string.format("profiles/pet_%02d.png", i)
end
for i = 1, 25 do
    AVATAR_POOLS.meme[i] = string.format("profiles/meme_%02d.png", i)
end
for i = 1, 25 do
    AVATAR_POOLS.art[i] = string.format("profiles/art_%02d.png", i)
end

-- ============================================================================
-- 昵称池（按难度/风格分层）
-- ============================================================================

--- 萌新级昵称（低子力 AI）
local NAMES_NEWBIE = {
    "小白兔", "萌新上路", "打酱油的", "刚学会走路",
    "菜鸟出击", "随便玩玩", "佛系对战", "咸鱼躺平",
    "试试水", "摸鱼中", "新手保护", "慢慢来",
    "不太会玩", "划水大师", "第一次上阵", "我是路人",
}

--- 普通级昵称（中等子力 AI）
local NAMES_NORMAL = {
    "街头霸王", "角斗士", "战场老兵", "无名剑客",
    "暗影猎手", "铁壁军团", "风暴骑士", "赏金猎人",
    "不败战将", "破阵者", "红莲骑士", "狂怒之拳",
    "战术大师", "迷途旅人", "星辰守卫", "雷霆一击",
    "御风行者", "苍穹之翼", "极光使者", "裂空者",
}

--- 高手级昵称（高子力 AI）
local NAMES_EXPERT = {
    "至尊王者", "不可战胜", "绝世强者", "终极审判",
    "碾压一切", "无敌战神", "深渊领主", "毁灭之锤",
    "万军之上", "天罚执行者", "诸神黄昏", "永恒统治",
    "灭世龙王", "虚空支配者", "寂灭之主", "穹顶君临",
}

-- ============================================================================
-- 难度分层（基于子力值 pieceValue）
-- ============================================================================
-- 子力范围参考：
--   单角色默认约 50~80 PV
--   3人队伍约 150~240 总PV
--   5人队伍约 250~400 总PV
--   8人队伍约 400~640 总PV

---@class AITier
---@field id string 层级ID
---@field name string 显示名称
---@field minPV number 最低子力（含）
---@field maxPV number 最高子力（不含）
---@field avatarCategories string[] 该层级偏好的头像类别
---@field namePool string[] 该层级使用的昵称池

---@type AITier[]
local TIERS = {
    {
        id = "newbie",
        name = "萌新",
        minPV = 0,
        maxPV = 200,
        avatarCategories = { "pet", "meme" },
        namePool = NAMES_NEWBIE,
    },
    {
        id = "normal",
        name = "战士",
        minPV = 200,
        maxPV = 400,
        avatarCategories = { "anime", "art" },
        namePool = NAMES_NORMAL,
    },
    {
        id = "expert",
        name = "强者",
        minPV = 400,
        maxPV = math.huge,
        avatarCategories = { "anime", "art" },
        namePool = NAMES_EXPERT,
    },
}

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 根据子力值获取对应的难度层级
---@param totalPV number AI 队伍总子力
---@return AITier
local function GetTierByPV(totalPV)
    for _, tier in ipairs(TIERS) do
        if totalPV >= tier.minPV and totalPV < tier.maxPV then
            return tier
        end
    end
    return TIERS[#TIERS] -- fallback 到最高层
end

--- 从列表中随机选一个
---@param list table
---@return any
local function RandomPick(list)
    if #list == 0 then return nil end
    return list[math.random(1, #list)]
end

--- 为 AI 生成一个 Profile（基于子力值匹配）
---@param totalPV number AI 队伍总子力值
---@param seed? number 可选随机种子（用于确定性选择）
---@return table profile { name: string, avatar: string, tier: string, tierName: string }
function M.GenerateProfile(totalPV, seed)
    if seed then
        math.randomseed(seed)
    end

    local tier = GetTierByPV(totalPV)

    -- 从该层级偏好的头像类别中随机选取
    local category = RandomPick(tier.avatarCategories)
    local avatarPool = AVATAR_POOLS[category] or AVATAR_POOLS.anime
    local avatar = RandomPick(avatarPool)

    -- 从该层级的昵称池中随机选取
    local name = RandomPick(tier.namePool)

    return {
        name = name,
        avatar = avatar,
        tier = tier.id,
        tierName = tier.name,
    }
end

-- ============================================================================
-- 玩家 Profile（TapTap 昵称异步加载）
-- ============================================================================

--- 缓存的 TapTap 昵称（异步加载后填入）
local cachedPlayerNickname_ = nil

--- 初始化玩家昵称（异步获取 TapTap 昵称，应在 Start 时调用一次）
function M.FetchPlayerNickname()
    if cachedPlayerNickname_ then return end -- 已有缓存，跳过

    ---@diagnostic disable: undefined-global
    local userId = nil
    if clientCloud and clientCloud.userId then
        userId = clientCloud.userId
    elseif lobby and lobby.GetMyUserId then
        userId = lobby:GetMyUserId()
    end
    ---@diagnostic enable: undefined-global

    if not userId or userId == 0 then
        print("[AIProfile] No userId available, using default nickname")
        return
    end

    GetUserNickname({
        userIds = { userId },
        onSuccess = function(nicknames)
            if nicknames and #nicknames > 0 and nicknames[1].nickname and nicknames[1].nickname ~= "" then
                cachedPlayerNickname_ = nicknames[1].nickname
                print("[AIProfile] TapTap nickname loaded: " .. cachedPlayerNickname_)
            end
        end,
        onError = function(errCode)
            print("[AIProfile] GetUserNickname failed: " .. tostring(errCode))
        end,
    })
end

-- 玩家头像池（从5个角色icon中随机选）
local PLAYER_AVATAR_POOL = {
    "image/edited_wisdel_avatar_20260529105147.png",
    "image/Kisaki.png",
    "image/doro_final.png",
    "image/originium_slug_icon.png",
    "image/Bunny.png",
}

--- 缓存的玩家头像（每次启动随机一个，整局不变）
local cachedPlayerAvatar_ = nil

--- 获取玩家 Profile
---@return table profile { name: string, avatar: string, tier: string, tierName: string }
function M.GetPlayerProfile()
    if not cachedPlayerAvatar_ then
        cachedPlayerAvatar_ = PLAYER_AVATAR_POOL[math.random(1, #PLAYER_AVATAR_POOL)]
    end
    return {
        name = cachedPlayerNickname_ or "我",
        avatar = cachedPlayerAvatar_,
        tier = "player",
        tierName = "指挥官",
    }
end

--- 获取所有层级信息（供 UI 展示）
---@return AITier[]
function M.GetTiers()
    return TIERS
end

return M
