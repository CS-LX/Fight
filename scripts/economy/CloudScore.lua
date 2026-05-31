-- ============================================================================
-- economy/CloudScore.lua - 云端积分同步（排行榜数据源）
-- ============================================================================
-- 职责：将本地胜场同步到 cloudScore API，提供排行榜拉取接口
-- 榜单 key: "total_wins" （累计胜场，不重置）

local M = {}

-- ============================================================================
-- 常量
-- ============================================================================

--- 排行榜排序 key（整数类型 → iscores，可参与排名）
local RANK_KEY = "total_wins"

--- 排行榜每页条数
local PAGE_SIZE = 20

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 缓存的排行榜数据
---@type {rank: number, userId: number, nickname: string, wins: number}[]|nil
local cachedRankList_ = nil

--- 我的排名缓存
---@type {rank: number|nil, wins: number}|nil
local cachedMyRank_ = nil

--- 排行榜总人数缓存
---@type number|nil
local cachedTotal_ = nil

--- 是否正在加载
local loading_ = false

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 记录一次胜利（累加云端 total_wins）
---@param onDone? function 完成回调
function M.RecordWin(onDone)
    clientCloud:Add(RANK_KEY, 1, {
        ok = function()
            print("[CloudScore] Win recorded (+1)")
            if onDone then onDone(true) end
        end,
        error = function(code, reason)
            print("[CloudScore] RecordWin error: " .. tostring(reason))
            if onDone then onDone(false) end
        end,
        timeout = function()
            print("[CloudScore] RecordWin timeout")
            if onDone then onDone(false) end
        end,
    })
end

--- 拉取排行榜（Top N + 我的排名）
---@param opts? {count?: number, onDone?: function}
function M.FetchLeaderboard(opts)
    opts = opts or {}
    local count = opts.count or PAGE_SIZE

    if loading_ then
        print("[CloudScore] Already loading, skip")
        return
    end
    loading_ = true

    -- 并行请求：排行榜列表 + 我的排名 + 总人数
    local pending = 3
    local function checkDone()
        pending = pending - 1
        if pending <= 0 then
            loading_ = false
            if opts.onDone then opts.onDone() end
        end
    end

    -- 1) 获取排行榜前 N 名
    clientCloud:GetRankList(RANK_KEY, 0, count, {
        ok = function(rankList)
            -- 先解析数据
            local parsed = {}
            local userIds = {}
            for i, item in ipairs(rankList) do
                local entry = {
                    rank = i,
                    userId = item.userId,
                    nickname = "玩家" .. tostring(item.userId),  -- 临时名，后续查昵称覆盖
                    wins = (item.iscore and item.iscore[RANK_KEY]) or 0,
                }
                table.insert(parsed, entry)
                table.insert(userIds, item.userId)
            end
            cachedRankList_ = parsed

            -- 批量查昵称
            if #userIds > 0 then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        -- 建立 userId → nickname 映射
                        local nameMap = {}
                        for _, info in ipairs(nicknames) do
                            nameMap[tostring(info.userId)] = info.nickname
                        end
                        -- 填充到缓存
                        for _, entry in ipairs(cachedRankList_) do
                            local name = nameMap[tostring(entry.userId)]
                            if name and name ~= "" then
                                entry.nickname = name
                            end
                        end
                        print("[CloudScore] Nicknames loaded for " .. #nicknames .. " players")
                        checkDone()
                    end,
                    onError = function(code)
                        print("[CloudScore] GetUserNickname error: " .. tostring(code))
                        checkDone()
                    end,
                })
            else
                checkDone()
            end
        end,
        error = function(code, reason)
            print("[CloudScore] GetRankList error: " .. tostring(reason))
            cachedRankList_ = {}
            checkDone()
        end,
        timeout = function()
            print("[CloudScore] GetRankList timeout")
            cachedRankList_ = {}
            checkDone()
        end,
    })

    -- 2) 获取我的排名
    clientCloud:GetUserRank(clientCloud.userId, RANK_KEY, {
        ok = function(rank, scoreValue)
            cachedMyRank_ = {
                rank = rank,  -- nil 表示未上榜
                wins = scoreValue or 0,
            }
            print("[CloudScore] My rank: #" .. tostring(rank) .. " wins=" .. tostring(scoreValue or 0))
            checkDone()
        end,
        error = function(code, reason)
            print("[CloudScore] GetUserRank error: " .. tostring(reason))
            cachedMyRank_ = { rank = nil, wins = 0 }
            checkDone()
        end,
        timeout = function()
            print("[CloudScore] GetUserRank timeout")
            cachedMyRank_ = { rank = nil, wins = 0 }
            checkDone()
        end,
    })

    -- 3) 获取排行榜总人数
    clientCloud:GetRankTotal(RANK_KEY, {
        ok = function(total)
            cachedTotal_ = total
            print("[CloudScore] Total players: " .. total)
            checkDone()
        end,
        error = function(code, reason)
            print("[CloudScore] GetRankTotal error: " .. tostring(reason))
            cachedTotal_ = 0
            checkDone()
        end,
        timeout = function()
            print("[CloudScore] GetRankTotal timeout")
            cachedTotal_ = 0
            checkDone()
        end,
    })
end

--- 获取缓存的排行榜列表
---@return {rank: number, userId: number, nickname: string, wins: number}[]
function M.GetCachedRankList()
    return cachedRankList_ or {}
end

--- 获取缓存的我的排名
---@return {rank: number|nil, wins: number}
function M.GetCachedMyRank()
    return cachedMyRank_ or { rank = nil, wins = 0 }
end

--- 获取缓存的总人数
---@return number
function M.GetCachedTotal()
    return cachedTotal_ or 0
end

--- 是否正在加载
---@return boolean
function M.IsLoading()
    return loading_
end

return M
