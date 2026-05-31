-- ============================================================================
-- ui/Leaderboard.lua - 排行榜浮层面板
-- ============================================================================
-- 职责：大厅右上角入口，点击打开排行榜浮层
-- 显示：排名 / 玩家名 / 累计胜场 / 底部固定「我的排名」
-- 数据源：economy/CloudScore.lua（clientCloud API）

local UI = require("urhox-libs/UI")
local CloudScore = require("economy.CloudScore")
local Anim = require("ui.UIAnimations")

local M = {}

-- ============================================================================
-- 色板（与 Lobby 保持一致的 PixelForge 风格）
-- ============================================================================

local COLORS = {
    background  = { 15, 15, 35, 240 },
    surface     = { 27, 27, 58, 255 },
    surfaceAlt  = { 35, 35, 72, 255 },
    primary     = { 33, 189, 174, 255 },
    gold        = { 255, 217, 61, 255 },
    silver      = { 192, 192, 210, 255 },
    bronze      = { 205, 127, 50, 255 },
    text        = { 240, 240, 240, 255 },
    textMuted   = { 160, 160, 192, 255 },
    border      = { 58, 58, 106, 255 },
    highlight   = { 33, 189, 174, 60 },
    overlay     = { 0, 0, 0, 160 },
}

-- ============================================================================
-- 状态
-- ============================================================================

local isOpen_ = false
---@type Widget|nil
local overlayRoot_ = nil
---@type Widget|nil
local panel_ = nil
---@type Widget|nil
local listContainer_ = nil
---@type Widget|nil
local myRankLabel_ = nil
---@type Widget|nil
local loadingLabel_ = nil

--- 关闭回调
---@type function|nil
local onClose_ = nil

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 打开排行榜面板（覆盖在当前 UI 之上）
---@param opts? {onClose?: function}
function M.Open(opts)
    opts = opts or {}
    onClose_ = opts.onClose

    if isOpen_ then return end
    isOpen_ = true

    M.BuildUI()

    -- 拉取排行榜数据
    CloudScore.FetchLeaderboard({
        count = 20,
        onDone = function()
            M.RefreshList()
        end,
    })
end

--- 关闭排行榜面板
function M.Close()
    if not isOpen_ then return end
    isOpen_ = false

    if overlayRoot_ then
        UI.PopOverlay(overlayRoot_)
        overlayRoot_ = nil
    end
    panel_ = nil
    listContainer_ = nil
    myRankLabel_ = nil
    loadingLabel_ = nil

    if onClose_ then
        onClose_()
        onClose_ = nil
    end
end

--- 是否打开
---@return boolean
function M.IsOpen()
    return isOpen_
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function M.BuildUI()
    -- 「我的排名」底栏
    myRankLabel_ = UI.Label {
        text = "加载中...",
        fontSize = 12,
        fontWeight = "bold",
        fontColor = COLORS.primary,
    }

    -- 加载状态
    loadingLabel_ = UI.Label {
        text = "加载排行榜...",
        fontSize = 11,
        fontColor = COLORS.textMuted,
    }

    -- 排行列表容器
    listContainer_ = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        overflow = "scroll",
        paddingLeft = 12,
        paddingRight = 12,
        paddingTop = 8,
        paddingBottom = 8,
        children = { loadingLabel_ },
    }

    -- 面板主体（onClick 阻止冒泡到遮罩层）
    panel_ = UI.Panel {
        width = 320,
        height = "80%",
        maxHeight = 500,
        backgroundColor = COLORS.surface,
        borderWidth = 2,
        borderColor = COLORS.border,
        borderRadius = 4,
        boxShadow = {
            { x = 0, y = 8, blur = 24, color = { 0, 0, 0, 180 } },
        },
        onClick = function() end,  -- 阻止冒泡
        children = {
            -- 标题栏
            UI.Panel {
                width = "100%",
                height = 44,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                paddingLeft = 16,
                paddingRight = 12,
                borderBottomWidth = 1,
                borderColor = COLORS.border,
                children = {
                    UI.Label {
                        text = "LEADERBOARD",
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = COLORS.gold,
                    },
                    UI.Button {
                        text = "X",
                        width = 28,
                        height = 28,
                        backgroundColor = { 0, 0, 0, 0 },
                        fontColor = COLORS.textMuted,
                        onClick = function()
                            M.Close()
                        end,
                    },
                },
            },
            -- 表头
            UI.Panel {
                width = "100%",
                height = 28,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 16,
                paddingRight = 16,
                backgroundColor = COLORS.surfaceAlt,
                children = {
                    UI.Label { text = "#", fontSize = 9, fontColor = COLORS.textMuted, width = 30 },
                    UI.Label { text = "玩家", fontSize = 9, fontColor = COLORS.textMuted, flexGrow = 1 },
                    UI.Label { text = "胜场", fontSize = 9, fontColor = COLORS.textMuted, width = 50, textAlign = "right" },
                },
            },
            -- 列表区域（可滚动）
            listContainer_,
            -- 底部：我的排名
            UI.Panel {
                width = "100%",
                height = 44,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                borderTopWidth = 1,
                borderColor = COLORS.border,
                backgroundColor = COLORS.surfaceAlt,
                gap = 8,
                children = {
                    UI.Label {
                        text = "我的排名:",
                        fontSize = 11,
                        fontColor = COLORS.textMuted,
                    },
                    myRankLabel_,
                },
            },
        },
    }

    -- 遮罩层（点击外部关闭；panel_ 的 onClick 会阻止冒泡）
    overlayRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = COLORS.overlay,
        justifyContent = "center",
        alignItems = "center",
        onClick = function()
            M.Close()
        end,
        children = { panel_ },
    }

    UI.PushOverlay(overlayRoot_)

    -- 入场动画
    Anim.PopIn(panel_, { duration = 0.3, ease = "backout" })
end

-- ============================================================================
-- 列表刷新
-- ============================================================================

--- 刷新排行榜列表内容
function M.RefreshList()
    if not listContainer_ then return end

    local rankList = CloudScore.GetCachedRankList()
    local myRank = CloudScore.GetCachedMyRank()
    local total = CloudScore.GetCachedTotal()
    local myUserId = clientCloud.userId

    -- 构建排行行列表
    local rows = {}
    if #rankList == 0 then
        table.insert(rows, UI.Panel {
            width = "100%",
            height = 60,
            alignItems = "center",
            justifyContent = "center",
            children = {
                UI.Label {
                    text = "暂无数据",
                    fontSize = 11,
                    fontColor = COLORS.textMuted,
                },
                UI.Label {
                    text = "赢得对战即可上榜！",
                    fontSize = 9,
                    fontColor = COLORS.textMuted,
                    marginTop = 4,
                },
            },
        })
    else
        for _, entry in ipairs(rankList) do
            local isMe = (entry.userId == myUserId)
            local rankColor = COLORS.textMuted
            if entry.rank == 1 then rankColor = COLORS.gold
            elseif entry.rank == 2 then rankColor = COLORS.silver
            elseif entry.rank == 3 then rankColor = COLORS.bronze
            end

            local row = UI.Panel {
                width = "100%",
                height = 36,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 16,
                paddingRight = 16,
                backgroundColor = isMe and COLORS.highlight or { 0, 0, 0, 0 },
                borderBottomWidth = 1,
                borderColor = { 58, 58, 106, 80 },
                children = {
                    -- 排名
                    UI.Label {
                        text = tostring(entry.rank),
                        fontSize = 12,
                        fontWeight = (entry.rank <= 3) and "bold" or "normal",
                        fontColor = rankColor,
                        width = 30,
                    },
                    -- 玩家名
                    UI.Label {
                        text = entry.nickname .. (isMe and " (我)" or ""),
                        fontSize = 11,
                        fontWeight = isMe and "bold" or "normal",
                        fontColor = isMe and COLORS.primary or COLORS.text,
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    -- 胜场
                    UI.Label {
                        text = tostring(entry.wins) .. " 胜",
                        fontSize = 11,
                        fontWeight = "bold",
                        fontColor = COLORS.gold,
                        width = 50,
                        textAlign = "right",
                    },
                },
            }
            table.insert(rows, row)
        end
    end

    -- 重建列表容器子元素
    listContainer_:ClearChildren()
    for _, row in ipairs(rows) do
        listContainer_:AddChild(row)
    end

    -- 更新我的排名
    if myRankLabel_ then
        if myRank.rank then
            myRankLabel_:SetText("第 " .. myRank.rank .. " 名 / " .. myRank.wins .. " 胜")
        else
            myRankLabel_:SetText("未上榜 / " .. myRank.wins .. " 胜")
        end
    end

    -- 总人数提示（如果有）
    if total > 0 then
        print("[Leaderboard] Displaying " .. #rankList .. "/" .. total .. " players")
    end
end

return M
