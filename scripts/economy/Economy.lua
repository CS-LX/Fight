-- ============================================================================
-- economy/Economy.lua - 金币经济系统
-- ============================================================================
-- 职责：管理金币余额、收支交易、持久化存储
-- Phase 1 核心模块：所有对战/赞助/创建都围绕金币经济运转

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================

--- 经济配置表
M.Config = {
    -- 初始金币（新玩家）
    STARTER_GOLD = 500,
    -- 每日登录奖励
    DAILY_LOGIN_REWARD = 50,
    -- 部署成本（每个角色上场花费）
    DEPLOY_COST_PER_UNIT = 30,
    -- 战斗胜利基础奖励
    WIN_BASE_REWARD = 80,
    -- 战斗失败安慰奖
    LOSE_CONSOLATION = 10,
    -- 赞助观战最低押注
    SPONSOR_MIN_BET = 20,
    -- 赞助观战最高押注
    SPONSOR_MAX_BET = 200,
    -- 赞助赔率（猜对时倍数，含本金）
    SPONSOR_WIN_MULTIPLIER = 1.8,
    -- 观战不押注的基础奖励（参与奖）
    SPECTATE_BASE_REWARD = 5,
    -- 防破产：救济金阈值（余额低于此值可领取）
    RELIEF_THRESHOLD = 50,
    -- 防破产：救济金金额
    RELIEF_AMOUNT = 100,
    -- 防破产：每日最多领取次数
    RELIEF_MAX_PER_DAY = 1,
    -- 新手保护：低金币时 AI 对战部署成本倍率（减半）
    NEWBIE_COST_MULTIPLIER = 0.5,
    -- 新手保护：金币低于此值时触发
    NEWBIE_THRESHOLD = 100,
}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 玩家金币余额
local balance_ = 0

--- 交易历史（最近 50 条）
---@type {type: string, amount: number, desc: string, time: number}[]
local history_ = {}

--- 历史最大保留条数
local MAX_HISTORY = 50

--- 云变量 key
local CLOUD_KEY_BALANCE = "gold"
local CLOUD_KEY_HISTORY = "tx_history"

--- 是否已初始化
local initialized_ = false

--- 初始化完成回调队列
local onReadyCallbacks_ = {}
--- 是否已就绪（云端数据加载完毕）
local isReady_ = false

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 触发所有 onReady 回调
local function FireReady()
    isReady_ = true
    for _, cb in ipairs(onReadyCallbacks_) do
        cb()
    end
    onReadyCallbacks_ = {}
end

--- 记录交易到历史
---@param txType string "earn" | "spend"
---@param amount number
---@param desc string
local function RecordTransaction(txType, amount, desc)
    table.insert(history_, 1, {
        type = txType,
        amount = amount,
        desc = desc,
        time = os.time(),
    })
    -- 截断超出部分
    while #history_ > MAX_HISTORY do
        table.remove(history_)
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化经济系统（从云端加载存档或创建新存档）
---@param onReady? function 数据就绪后回调
function M.Init(onReady)
    if onReady then
        if isReady_ then
            onReady()
        else
            table.insert(onReadyCallbacks_, onReady)
        end
    end
    if initialized_ then return end
    initialized_ = true

    M.Load()
end

--- 是否已就绪
---@return boolean
function M.IsReady()
    return isReady_
end

--- 获取当前余额
---@return number
function M.GetBalance()
    return balance_
end

--- 判断是否能负担指定金额
---@param amount number
---@return boolean
function M.CanAfford(amount)
    return balance_ >= amount
end

--- 获得金币（正数）
---@param amount number 获得金额（正数）
---@param desc string 描述（如"战斗胜利奖励"）
---@return number newBalance 操作后余额
function M.Earn(amount, desc)
    if amount <= 0 then return balance_ end
    balance_ = balance_ + amount
    RecordTransaction("earn", amount, desc or "收入")
    M.Save()
    print(string.format("[Economy] +%d (%s) → %d", amount, desc or "收入", balance_))
    return balance_
end

--- 花费金币（返回是否成功）
---@param amount number 花费金额（正数）
---@param desc string 描述（如"部署角色×3"）
---@return boolean success 是否成功扣款
function M.Spend(amount, desc)
    if amount <= 0 then return true end
    if balance_ < amount then
        print(string.format("[Economy] FAILED: need %d, have %d (%s)", amount, balance_, desc or "支出"))
        return false
    end
    balance_ = balance_ - amount
    RecordTransaction("spend", amount, desc or "支出")
    M.Save()
    print(string.format("[Economy] -%d (%s) → %d", amount, desc or "支出", balance_))
    return true
end

--- 计算部署总成本
---@param unitCount number 部署角色数量
---@return number totalCost
function M.CalcDeployCost(unitCount)
    return unitCount * M.Config.DEPLOY_COST_PER_UNIT
end

--- 计算战斗奖励
---@param won boolean 是否胜利
---@param enemyCount number 对方角色数量
---@return number reward
function M.CalcBattleReward(won, enemyCount)
    if won then
        -- 胜利：基础奖励 + 每击败一个敌人的额外奖励
        return M.Config.WIN_BASE_REWARD + enemyCount * 10
    else
        return M.Config.LOSE_CONSOLATION
    end
end

--- 计算赞助观战收益
---@param betAmount number 押注金额
---@param guessCorrect boolean 是否猜对
---@return number profit 净收益（正=赚，负=亏，0=未押注）
function M.CalcSponsorProfit(betAmount, guessCorrect)
    if betAmount <= 0 then
        -- 未押注，只给参与奖
        return M.Config.SPECTATE_BASE_REWARD
    end
    if guessCorrect then
        -- 猜对：获得 betAmount × multiplier（含本金）
        local payout = math.floor(betAmount * M.Config.SPONSOR_WIN_MULTIPLIER)
        return payout - betAmount  -- 净利润
    else
        -- 猜错：损失全部押注
        return -betAmount
    end
end

--- 获取交易历史
---@return table[]
function M.GetHistory()
    return history_
end

--- 获取最近 N 条交易
---@param n number
---@return table[]
function M.GetRecentHistory(n)
    local result = {}
    for i = 1, math.min(n, #history_) do
        result[i] = history_[i]
    end
    return result
end

-- ============================================================================
-- 持久化（clientCloud 云存储）
-- ============================================================================

--- 保存到云端
function M.Save()
    clientCloud:BatchSet()
        :SetInt(CLOUD_KEY_BALANCE, balance_)
        :Set(CLOUD_KEY_HISTORY, history_)
        :Save("economy_save", {
            ok = function()
                print("[Economy] Cloud save OK, balance=" .. balance_)
            end,
            error = function(code, reason)
                print("[Economy] Cloud save FAILED: " .. tostring(reason))
            end,
        })
end

--- 从云端加载
function M.Load()
    clientCloud:BatchGet()
        :Key(CLOUD_KEY_BALANCE)
        :Key(CLOUD_KEY_HISTORY)
        :Fetch({
            ok = function(values, iscores)
                local savedBalance = iscores[CLOUD_KEY_BALANCE]
                if savedBalance and savedBalance > 0 then
                    -- 老玩家：恢复存档
                    balance_ = savedBalance
                    history_ = values[CLOUD_KEY_HISTORY] or {}
                    print("[Economy] Cloud load OK, balance=" .. balance_)
                else
                    -- 新玩家：发放初始金币
                    balance_ = M.Config.STARTER_GOLD
                    history_ = {}
                    RecordTransaction("earn", M.Config.STARTER_GOLD, "新手礼包")
                    M.Save()
                    print("[Economy] New player, starter gold: " .. balance_)
                end
                FireReady()
            end,
            error = function(code, reason)
                -- 云端加载失败，使用默认值继续游戏
                print("[Economy] Cloud load FAILED: " .. tostring(reason) .. ", using defaults")
                balance_ = M.Config.STARTER_GOLD
                history_ = {}
                RecordTransaction("earn", M.Config.STARTER_GOLD, "新手礼包")
                FireReady()
            end,
        })
end

--- 重置经济数据（调试用）
function M.Reset()
    balance_ = M.Config.STARTER_GOLD
    history_ = {}
    RecordTransaction("earn", M.Config.STARTER_GOLD, "重置奖励")
    M.Save()
    print("[Economy] Reset to starter gold: " .. balance_)
end

-- ============================================================================
-- 防破产/新手保护 (Phase 2)
-- ============================================================================

--- 今日已领取救济金次数
local reliefUsedToday_ = 0
--- 上次领取救济金的日期 (yday)
local lastReliefDay_ = -1

--- 是否可以领取救济金
---@return boolean canClaim
---@return string|nil reason 不可领取的原因
function M.CanClaimRelief()
    if balance_ >= M.Config.RELIEF_THRESHOLD then
        return false, "余额充足（≥" .. M.Config.RELIEF_THRESHOLD .. "G），无需救济"
    end
    -- 检查日期重置
    local today = os.date("*t").yday
    if today ~= lastReliefDay_ then
        reliefUsedToday_ = 0
        lastReliefDay_ = today
    end
    if reliefUsedToday_ >= M.Config.RELIEF_MAX_PER_DAY then
        return false, "今日救济次数已用完"
    end
    return true, nil
end

--- 领取救济金
---@return boolean success
---@return string message
function M.ClaimRelief()
    local can, reason = M.CanClaimRelief()
    if not can then
        return false, reason or "不可领取"
    end
    -- 日期重置检查
    local today = os.date("*t").yday
    if today ~= lastReliefDay_ then
        reliefUsedToday_ = 0
        lastReliefDay_ = today
    end
    reliefUsedToday_ = reliefUsedToday_ + 1
    M.Earn(M.Config.RELIEF_AMOUNT, "救济金")
    return true, "获得 " .. M.Config.RELIEF_AMOUNT .. "G 救济金！"
end

--- 是否处于新手保护状态（低金币）
---@return boolean
function M.IsInNewbieProtection()
    return balance_ < M.Config.NEWBIE_THRESHOLD
end

--- 计算实际部署成本（考虑新手保护）
---@param unitCount number
---@param isRanked boolean 是否排位赛（排位赛不享受减半）
---@return number
function M.CalcActualDeployCost(unitCount, isRanked)
    local base = M.CalcDeployCost(unitCount)
    if not isRanked and M.IsInNewbieProtection() then
        return math.floor(base * M.Config.NEWBIE_COST_MULTIPLIER)
    end
    return base
end

return M
