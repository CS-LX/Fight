-- ============================================================================
-- ui/SpectateUI.lua - 赞助观战押注界面
-- ============================================================================
-- 职责：显示即将开始的AI对战信息，让玩家选择押注队伍和金额
-- 设计风格：PixelForge 像素复古风

local UI = require("urhox-libs/UI")
local Economy = require("economy.Economy")

local M = {}

-- ============================================================================
-- PixelForge 色板
-- ============================================================================

local COLORS = {
    background  = { 15, 15, 35, 255 },
    surface     = { 27, 27, 58, 255 },
    surfaceHover= { 37, 37, 80, 255 },
    primary     = { 33, 189, 174, 255 },
    secondary   = { 108, 92, 231, 255 },
    text        = { 240, 240, 240, 255 },
    textMuted   = { 160, 160, 192, 255 },
    border      = { 58, 58, 106, 255 },
    gold        = { 255, 217, 61, 255 },
    redText     = { 255, 71, 87, 255 },
    blueText    = { 69, 170, 242, 255 },
    success     = { 80, 200, 120, 255 },
    shadow      = { 10, 10, 26, 204 },
}

local PIXEL_SHADOW = {
    { x = 3, y = 3, blur = 0, color = {10, 10, 26, 204} },
    { x = -1, y = -1, blur = 0, color = {255, 255, 255, 48} },
}

-- ============================================================================
-- 状态
-- ============================================================================

local isOpen_ = false
---@type Widget|nil
local root_ = nil
---@type function|nil
local onConfirmBet_ = nil
---@type function|nil
local onSkipBet_ = nil
---@type function|nil
local onCancel_ = nil

--- 当前选择
local selectedTeam_ = "red"   -- "red" | "blue"
local betAmount_ = 50         -- 默认押注额

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 打开赞助观战 UI
---@param opts {redCount:number, blueCount:number, characters:table[], onConfirmBet:function, onSkipBet:function, onCancel:function}
function M.Open(opts)
    isOpen_ = true
    onConfirmBet_ = opts.onConfirmBet
    onSkipBet_ = opts.onSkipBet
    onCancel_ = opts.onCancel

    selectedTeam_ = "red"
    betAmount_ = Economy.Config.SPONSOR_MIN_BET

    M.BuildUI(opts.redCount, opts.blueCount)
end

--- 关闭
function M.Close()
    isOpen_ = false
    onConfirmBet_ = nil
    onSkipBet_ = nil
    onCancel_ = nil
    if root_ then
        UI.SetRoot(nil)
        root_ = nil
    end
end

--- 是否打开
function M.IsOpen()
    return isOpen_
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function M.BuildUI(redCount, blueCount)
    local balance = Economy.GetBalance()
    local maxBet = math.min(Economy.Config.SPONSOR_MAX_BET, balance)

    -- 标题
    local titleSection = UI.Panel {
        alignItems = "center",
        marginBottom = 20,
        children = {
            UI.Label {
                text = "SPECTATE MATCH",
                fontSize = 18,
                fontWeight = "bold",
                color = COLORS.primary,
            },
            UI.Label {
                text = "选择你支持的队伍并押注",
                fontSize = 10,
                color = COLORS.textMuted,
                marginTop = 4,
            },
        },
    }

    -- 对阵信息
    local matchInfo = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        marginBottom = 20,
        gap = 16,
        children = {
            -- 红方
            UI.Panel {
                alignItems = "center",
                children = {
                    UI.Label { text = "RED", fontSize = 14, fontWeight = "bold", fontColor = COLORS.redText },
                    UI.Label { text = redCount .. " units", fontSize = 10, fontColor = COLORS.textMuted },
                },
            },
            UI.Label { text = "VS", fontSize = 16, fontWeight = "bold", fontColor = COLORS.text },
            -- 蓝方
            UI.Panel {
                alignItems = "center",
                children = {
                    UI.Label { text = "BLUE", fontSize = 14, fontWeight = "bold", fontColor = COLORS.blueText },
                    UI.Label { text = blueCount .. " units", fontSize = 10, fontColor = COLORS.textMuted },
                },
            },
        },
    }

    -- 队伍选择按钮
    local teamSelectLabel = UI.Label {
        text = "押注: RED",
        fontSize = 11,
        fontWeight = "bold",
        fontColor = COLORS.redText,
        marginBottom = 8,
    }

    local teamSection = UI.Panel {
        alignItems = "center",
        marginBottom = 16,
        children = {
            UI.Label { text = "选择队伍", fontSize = 10, fontColor = COLORS.textMuted, marginBottom = 6 },
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                children = {
                    UI.Button {
                        text = "RED",
                        width = 80,
                        height = 32,
                        backgroundColor = COLORS.redText,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            selectedTeam_ = "red"
                            teamSelectLabel:SetText("押注: RED")
                            teamSelectLabel:SetFontColor(COLORS.redText)
                        end,
                    },
                    UI.Button {
                        text = "BLUE",
                        width = 80,
                        height = 32,
                        backgroundColor = COLORS.blueText,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            selectedTeam_ = "blue"
                            teamSelectLabel:SetText("押注: BLUE")
                            teamSelectLabel:SetFontColor(COLORS.blueText)
                        end,
                    },
                },
            },
            teamSelectLabel,
        },
    }

    -- 押注金额
    local betLabel = UI.Label {
        text = betAmount_ .. "G",
        fontSize = 13,
        fontWeight = "bold",
        fontColor = COLORS.gold,
    }

    local betSection = UI.Panel {
        alignItems = "center",
        marginBottom = 20,
        children = {
            UI.Label { text = "押注金额", fontSize = 10, fontColor = COLORS.textMuted, marginBottom = 6 },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    UI.Button {
                        text = "-",
                        width = 32,
                        height = 32,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            betAmount_ = math.max(Economy.Config.SPONSOR_MIN_BET, betAmount_ - 10)
                            betLabel:SetText(betAmount_ .. "G")
                        end,
                    },
                    betLabel,
                    UI.Button {
                        text = "+",
                        width = 32,
                        height = 32,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            betAmount_ = math.min(maxBet, betAmount_ + 10)
                            betLabel:SetText(betAmount_ .. "G")
                        end,
                    },
                },
            },
            UI.Label {
                text = "余额: " .. balance .. "G | 赔率 " .. string.format("%.1fx", Economy.Config.SPONSOR_WIN_MULTIPLIER),
                fontSize = 9,
                color = COLORS.textMuted,
                marginTop = 4,
            },
        },
    }

    -- 操作按钮
    local actions = UI.Panel {
        flexDirection = "row",
        gap = 12,
        children = {
            UI.Button {
                text = "确认押注",
                width = 120,
                height = 36,
                backgroundColor = COLORS.primary,
                boxShadow = PIXEL_SHADOW,
                onClick = function()
                    if betAmount_ > balance then return end
                    local cb = onConfirmBet_
                    local amount = betAmount_
                    local team = selectedTeam_
                    M.Close()
                    UI.Toast { text = string.format("-%dG 押注%s方", amount, team), duration = 2000 }
                    if cb then
                        cb(amount, team)
                    end
                end,
            },
            UI.Button {
                text = "只看不押",
                width = 100,
                height = 36,
                backgroundColor = COLORS.surfaceHover,
                borderWidth = 2,
                borderColor = COLORS.border,
                boxShadow = PIXEL_SHADOW,
                onClick = function()
                    local cb = onSkipBet_
                    M.Close()
                    if cb then
                        cb()
                    end
                end,
            },
            UI.Button {
                text = "返回",
                width = 80,
                height = 36,
                backgroundColor = COLORS.surfaceHover,
                borderWidth = 2,
                borderColor = COLORS.border,
                onClick = function()
                    local cb = onCancel_
                    M.Close()
                    if cb then
                        cb()
                    end
                end,
            },
        },
    }

    -- 组装
    root_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = COLORS.background,
        alignItems = "center",
        justifyContent = "center",
        children = {
            UI.Panel {
                width = 360,
                padding = 24,
                backgroundColor = COLORS.surface,
                borderWidth = 2,
                borderColor = COLORS.border,
                alignItems = "center",
                boxShadow = {
                    { x = 4, y = 4, blur = 0, color = COLORS.shadow },
                },
                children = {
                    titleSection,
                    matchInfo,
                    teamSection,
                    betSection,
                    actions,
                },
            },
        },
    }

    UI.SetRoot(root_)
end

return M
