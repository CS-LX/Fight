-- ============================================================================
-- economy/Ranked.lua - 排位系统（段位/积分/AI难度匹配）
-- ============================================================================
-- Phase 2: 排位对战模式
-- 玩家通过排位赛积累积分，段位提升后 AI 对手更强（数量多/属性高）
-- 排位奖励 ×1.5 高于普通 AI 对战

local Economy = require("economy.Economy")
local Config = require("Config")

local M = {}

-- ============================================================================
-- 段位配置
-- ============================================================================

--- 段位表（从低到高）
M.Tiers = {
    { id = "bronze",   name = "青铜", minScore = 0,    color = {180, 130, 70, 255} },
    { id = "silver",   name = "白银", minScore = 100,  color = {192, 192, 210, 255} },
    { id = "gold",     name = "黄金", minScore = 300,  color = {255, 215, 0, 255} },
    { id = "platinum", name = "铂金", minScore = 600,  color = {120, 220, 220, 255} },
    { id = "diamond",  name = "钻石", minScore = 1000, color = {100, 180, 255, 255} },
    { id = "master",   name = "大师", minScore = 1500, color = {200, 100, 255, 255} },
}

--- 排位配置
M.Config = {
    -- 胜利获得积分
    WIN_SCORE = 25,
    -- 失败扣除积分（不低于 0）
    LOSE_SCORE = 10,
    -- 排位奖励倍数（相对于普通 AI 对战）
    REWARD_MULTIPLIER = 1.5,
    -- 排位部署成本倍数
    COST_MULTIPLIER = 1.0,
    -- AI 基础队伍人数（段位递增）
    AI_BASE_TEAM_SIZE = 3,
    -- 每段位增加的 AI 人数
    AI_PER_TIER = 0,
    -- AI 属性倍数基础（段位递增）
    AI_STAT_BASE = 1.0,
    -- 每段位增加的 AI 属性倍率
    AI_STAT_PER_TIER = 0.1,
}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 当前积分
local score_ = 0

--- 总排位赛次数
local totalMatches_ = 0
--- 胜利次数
local wins_ = 0

--- 存储路径
local SAVE_DIR = "economy"
local SAVE_FILE = SAVE_DIR .. "/ranked.json"

--- 是否已初始化
local initialized_ = false

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化排位系统
function M.Init()
    if initialized_ then return end
    initialized_ = true

    local loaded = M.Load()
    if not loaded then
        score_ = 0
        totalMatches_ = 0
        wins_ = 0
        M.Save()
        print("[Ranked] New player, score: 0 (Bronze)")
    else
        print("[Ranked] Loaded score: " .. score_ .. " (" .. M.GetTierName() .. ")")
    end
end

--- 获取当前积分
---@return number
function M.GetScore()
    return score_
end

--- 获取当前段位索引（1-based）
---@return number tierIndex
function M.GetTierIndex()
    local idx = 1
    for i, tier in ipairs(M.Tiers) do
        if score_ >= tier.minScore then
            idx = i
        else
            break
        end
    end
    return idx
end

--- 获取当前段位信息
---@return {id: string, name: string, minScore: number, color: table}
function M.GetTier()
    return M.Tiers[M.GetTierIndex()]
end

--- 获取当前段位名称
---@return string
function M.GetTierName()
    return M.GetTier().name
end

--- 获取下一段位所需积分（已满级返回 nil）
---@return number|nil
function M.GetNextTierScore()
    local idx = M.GetTierIndex()
    if idx >= #M.Tiers then return nil end
    return M.Tiers[idx + 1].minScore
end

--- 获取当前段位进度（0~1）
---@return number
function M.GetTierProgress()
    local idx = M.GetTierIndex()
    local current = M.Tiers[idx].minScore
    local next = idx < #M.Tiers and M.Tiers[idx + 1].minScore or current
    if next == current then return 1.0 end
    return (score_ - current) / (next - current)
end

--- 获取总场次
---@return number
function M.GetTotalMatches()
    return totalMatches_
end

--- 获取胜率
---@return number 0~1
function M.GetWinRate()
    if totalMatches_ == 0 then return 0 end
    return wins_ / totalMatches_
end

--- 记录一场排位赛结果
---@param won boolean 是否胜利
---@return number scoreChange 积分变化（正=涨，负=跌）
function M.RecordMatch(won)
    totalMatches_ = totalMatches_ + 1
    local change = 0
    if won then
        wins_ = wins_ + 1
        change = M.Config.WIN_SCORE
        score_ = score_ + change
    else
        change = -M.Config.LOSE_SCORE
        score_ = math.max(0, score_ + change)
    end
    M.Save()
    print(string.format("[Ranked] %s → score %d (%s), change %+d",
        won and "WIN" or "LOSE", score_, M.GetTierName(), change))
    return change
end

--- 计算排位赛奖励金额
---@param won boolean
---@param enemyCount number
---@return number
function M.CalcReward(won, enemyCount)
    local base = Economy.CalcBattleReward(won, enemyCount)
    return math.floor(base * M.Config.REWARD_MULTIPLIER)
end

--- 计算排位赛部署费用
---@param unitCount number
---@return number
function M.CalcDeployCost(unitCount)
    local base = Economy.CalcDeployCost(unitCount)
    return math.floor(base * M.Config.COST_MULTIPLIER)
end

--- 获取当前段位对应的 AI 配置
---@return {teamSize: number, statMultiplier: number}
function M.GetAIConfig()
    local tierIdx = M.GetTierIndex()
    return {
        teamSize = M.Config.AI_BASE_TEAM_SIZE + (tierIdx - 1) * M.Config.AI_PER_TIER,
        statMultiplier = M.Config.AI_STAT_BASE + (tierIdx - 1) * M.Config.AI_STAT_PER_TIER,
    }
end

-- ============================================================================
-- 持久化
-- ============================================================================

function M.Save()
    if not fileSystem:DirExists(SAVE_DIR) then
        fileSystem:CreateDir(SAVE_DIR)
    end
    local data = {
        score = score_,
        totalMatches = totalMatches_,
        wins = wins_,
        savedAt = os.time(),
    }
    local json = cjson.encode(data)
    local file = File(SAVE_FILE, FILE_WRITE)
    if file then
        file:WriteLine(json)
        file:Close()
    end
end

function M.Load()
    if not fileSystem:FileExists(SAVE_FILE) then
        return false
    end
    local file = File(SAVE_FILE, FILE_READ)
    if not file then return false end
    local json = file:ReadLine()
    file:Close()
    if not json or json == "" then return false end
    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then return false end

    score_ = data.score or 0
    totalMatches_ = data.totalMatches or 0
    wins_ = data.wins or 0
    return true
end

--- 重置排位数据（调试）
function M.Reset()
    score_ = 0
    totalMatches_ = 0
    wins_ = 0
    M.Save()
    print("[Ranked] Reset to 0")
end

return M
