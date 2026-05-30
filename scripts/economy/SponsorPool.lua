-- ============================================================================
-- economy/SponsorPool.lua - 赞助池系统（观战下注汇入池，对战选手分成）
-- ============================================================================
-- Phase 2: 赞助池与对战分成联动
-- 观战模式的押注金额汇入赞助池，对战选手（普通/排位）从池中获得额外分成。
-- 单机模式下 AI 观众自动投注充实赞助池。

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================

M.Config = {
    -- 赞助池分配比例
    WINNER_SPONSOR_SHARE = 0.70,   -- 70% → 胜方赞助商（观战模式中的玩家/AI）
    FIGHTER_WINNER_SHARE = 0.15,   -- 15% → 胜方对战选手
    FIGHTER_LOSER_SHARE  = 0.05,   -- 5%  → 败方对战选手
    SYSTEM_CUT           = 0.10,   -- 10% → 系统回收（经济调控）

    -- AI 观众自动投注（模拟多人赞助）
    AI_SPECTATOR_COUNT_MIN = 2,    -- 每场最少 AI 观众数
    AI_SPECTATOR_COUNT_MAX = 5,    -- 每场最多 AI 观众数
    AI_BET_MIN = 15,               -- AI 单次投注最小
    AI_BET_MAX = 60,               -- AI 单次投注最大
    AI_CORRECT_RATE = 0.5,         -- AI 猜对概率（0.5 = 随机）

    -- 赞助池持久化上限（防止无限膨胀）
    POOL_MAX = 5000,
}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 当前赞助池余额（跨场次累积的系统池）
local pool_ = 0

--- 本场赞助信息
---@type {redTotal: number, blueTotal: number, bets: table[]}
local currentMatch_ = nil

--- 存储路径
local SAVE_DIR = "economy"
local SAVE_FILE = SAVE_DIR .. "/sponsor_pool.json"

local initialized_ = false

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化
function M.Init()
    if initialized_ then return end
    initialized_ = true
    M.Load()
    print("[SponsorPool] Loaded pool: " .. pool_ .. "G")
end

--- 获取当前池余额
---@return number
function M.GetPool()
    return pool_
end

--- 开始新一场比赛的赞助收集
function M.BeginMatch()
    currentMatch_ = {
        redTotal = 0,
        blueTotal = 0,
        bets = {},
    }
end

--- 添加一笔押注到当前比赛
---@param amount number 金额
---@param team string "red"|"blue"
---@param source string "player"|"ai"
function M.AddBet(amount, team, source)
    if not currentMatch_ then return end
    if team == "red" then
        currentMatch_.redTotal = currentMatch_.redTotal + amount
    else
        currentMatch_.blueTotal = currentMatch_.blueTotal + amount
    end
    table.insert(currentMatch_.bets, {
        amount = amount,
        team = team,
        source = source,
    })
end

--- 模拟 AI 观众投注（在比赛开始前调用）
---@param redStrength number 红方总战力（可用 HP 总和近似）
---@param blueStrength number 蓝方总战力
function M.SimulateAIBets(redStrength, blueStrength)
    if not currentMatch_ then M.BeginMatch() end

    local spectatorCount = math.random(
        M.Config.AI_SPECTATOR_COUNT_MIN,
        M.Config.AI_SPECTATOR_COUNT_MAX
    )

    -- 根据实力计算 AI 偏好（强队更容易被 AI 押注）
    local total = redStrength + blueStrength
    local redProb = total > 0 and (redStrength / total) or 0.5

    for i = 1, spectatorCount do
        local betAmount = math.random(M.Config.AI_BET_MIN, M.Config.AI_BET_MAX)
        -- AI 以实力比例为概率选边（加入随机噪声）
        local noise = (math.random() - 0.5) * 0.3
        local pickRed = (math.random() < (redProb + noise))
        local team = pickRed and "red" or "blue"
        M.AddBet(betAmount, team, "ai")
    end

    print(string.format("[SponsorPool] AI bets: %d spectators, red=%dG blue=%dG",
        spectatorCount, currentMatch_.redTotal, currentMatch_.blueTotal))
end

--- 结算当前比赛的赞助池
--- 返回对战选手的分成金额
---@param winTeam string "red"|"blue"
---@return {winnerShare: number, loserShare: number, poolTotal: number}
function M.SettleMatch(winTeam)
    if not currentMatch_ then
        return { winnerShare = 0, loserShare = 0, poolTotal = 0 }
    end

    local matchPool = currentMatch_.redTotal + currentMatch_.blueTotal

    -- 本场押注全部汇入总池
    pool_ = pool_ + matchPool

    -- 从总池中分配
    local totalDistribute = math.min(pool_, matchPool) -- 分配不超过本场贡献

    local winnerFighterShare = math.floor(totalDistribute * M.Config.FIGHTER_WINNER_SHARE)
    local loserFighterShare = math.floor(totalDistribute * M.Config.FIGHTER_LOSER_SHARE)
    local systemCut = math.floor(totalDistribute * M.Config.SYSTEM_CUT)
    local sponsorPayout = math.floor(totalDistribute * M.Config.WINNER_SPONSOR_SHARE)

    -- 从池中扣除分出去的部分（胜方赞助商+对战选手+系统回收）
    local totalOut = winnerFighterShare + loserFighterShare + systemCut + sponsorPayout
    pool_ = math.max(0, pool_ - totalOut)

    -- 限制池上限
    if pool_ > M.Config.POOL_MAX then
        pool_ = M.Config.POOL_MAX
    end

    M.Save()

    -- 清除本场数据
    local winBets = (winTeam == "red") and currentMatch_.redTotal or currentMatch_.blueTotal
    local result = {
        winnerShare = winnerFighterShare,
        loserShare = loserFighterShare,
        poolTotal = matchPool,
        sponsorPayout = sponsorPayout,   -- 胜方赞助商总奖金
        winBets = winBets,               -- 胜方总投注额（用于计算个人分成比例）
    }
    currentMatch_ = nil

    print(string.format("[SponsorPool] Settle: pool_in=%dG, fighter_win=%dG, fighter_lose=%dG, sys=%dG, remaining=%dG",
        matchPool, winnerFighterShare, loserFighterShare, systemCut, pool_))

    return result
end

--- 获取当前比赛的总押注额
---@return number
function M.GetCurrentMatchTotal()
    if not currentMatch_ then return 0 end
    return currentMatch_.redTotal + currentMatch_.blueTotal
end

--- 获取当前比赛各方押注
---@return number redTotal, number blueTotal
function M.GetCurrentMatchBets()
    if not currentMatch_ then return 0, 0 end
    return currentMatch_.redTotal, currentMatch_.blueTotal
end

-- ============================================================================
-- 持久化
-- ============================================================================

function M.Save()
    if not fileSystem:DirExists(SAVE_DIR) then
        fileSystem:CreateDir(SAVE_DIR)
    end
    local data = { pool = pool_, savedAt = os.time() }
    local json = cjson.encode(data)
    local file = File(SAVE_FILE, FILE_WRITE)
    if file then
        file:WriteLine(json)
        file:Close()
    end
end

function M.Load()
    if not fileSystem:FileExists(SAVE_FILE) then
        pool_ = 0
        return
    end
    local file = File(SAVE_FILE, FILE_READ)
    if not file then pool_ = 0; return end
    local json = file:ReadLine()
    file:Close()
    if not json or json == "" then pool_ = 0; return end
    local ok, data = pcall(cjson.decode, json)
    if ok and data then
        pool_ = data.pool or 0
    else
        pool_ = 0
    end
end

--- 重置（调试）
function M.Reset()
    pool_ = 0
    currentMatch_ = nil
    M.Save()
    print("[SponsorPool] Reset to 0")
end

return M
