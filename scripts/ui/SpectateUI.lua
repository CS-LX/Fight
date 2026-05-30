-- ============================================================================
-- ui/SpectateUI.lua - 赞助观战押注界面
-- ============================================================================
-- 职责：显示即将开始的AI对战信息，让玩家选择押注队伍和金额
-- 设计风格：PixelForge 像素复古风

local UI = require("urhox-libs/UI")
local Economy = require("economy.Economy")
local Anim = require("ui.UIAnimations")

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
    betAmount_ = math.min(Economy.Config.SPONSOR_MIN_BET, Economy.GetBalance())

    M.BuildUI(opts.redCount, opts.blueCount, opts.spineLayer)
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

function M.BuildUI(redCount, blueCount, spineLayer)
    local balance = Economy.GetBalance()
    local maxBet = math.min(Economy.Config.SPONSOR_MAX_BET, balance)

    -- === 顶部标题栏 ===
    local topBar = UI.Panel {
        width = "100%",
        position = "absolute",
        top = 0, left = 0,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        height = 36,
        backgroundColor = { 15, 15, 35, 200 },
        children = {
            UI.Label {
                text = string.format("SPECTATE  RED %d  VS  BLUE %d", redCount, blueCount),
                fontSize = 13,
                fontWeight = "bold",
                fontColor = COLORS.primary,
            },
        },
    }

    -- === 底部押注栏 ===
    -- 队伍选择指示
    local teamLabel = UI.Label {
        text = "RED",
        fontSize = 12,
        fontWeight = "bold",
        fontColor = COLORS.redText,
    }

    -- 押注金额显示
    local betLabel = UI.Label {
        text = betAmount_ .. "G",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = COLORS.gold,
    }

    local bottomBar = UI.Panel {
        width = "100%",
        position = "absolute",
        bottom = 0, left = 0,
        backgroundColor = { 20, 20, 45, 240 },
        borderColor = COLORS.border,
        borderTopWidth = 2,
        padding = 10,
        paddingLeft = 16,
        paddingRight = 16,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            -- 左: 队伍选择
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label { text = "押注", fontSize = 10, fontColor = COLORS.textMuted },
                    UI.Button {
                        text = "RED",
                        width = 52, height = 28,
                        fontSize = 10, fontWeight = "bold",
                        backgroundColor = COLORS.redText,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            selectedTeam_ = "red"
                            teamLabel:SetText("RED")
                            teamLabel:SetFontColor(COLORS.redText)
                        end,
                    },
                    UI.Button {
                        text = "BLUE",
                        width = 52, height = 28,
                        fontSize = 10, fontWeight = "bold",
                        backgroundColor = COLORS.blueText,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            selectedTeam_ = "blue"
                            teamLabel:SetText("BLUE")
                            teamLabel:SetFontColor(COLORS.blueText)
                        end,
                    },
                    teamLabel,
                },
            },
            -- 中: 金额调节
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Button {
                        text = "-",
                        width = 28, height = 28,
                        fontSize = 12,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            betAmount_ = math.max(0, betAmount_ - 10)
                            betLabel:SetText(betAmount_ .. "G")
                        end,
                    },
                    betLabel,
                    UI.Button {
                        text = "+",
                        width = 28, height = 28,
                        fontSize = 12,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            betAmount_ = math.min(maxBet, betAmount_ + 10)
                            betLabel:SetText(betAmount_ .. "G")
                        end,
                    },
                    UI.Label {
                        text = "/ " .. balance .. "G",
                        fontSize = 9,
                        fontColor = COLORS.textMuted,
                    },
                },
            },
            -- 右: 操作按钮
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Button {
                        text = "FIGHT!",
                        width = 80, height = 32,
                        fontSize = 11, fontWeight = "bold",
                        backgroundColor = COLORS.primary,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            if betAmount_ > 0 and betAmount_ > balance then return end
                            local cb = (betAmount_ > 0) and onConfirmBet_ or onSkipBet_
                            local amount = betAmount_
                            local team = selectedTeam_
                            M.Close()
                            if amount > 0 then
                                UI.Toast { text = string.format("-%dG 押注%s方", amount, team), duration = 2000 }
                                if cb then cb(amount, team) end
                            else
                                UI.Toast { text = "免费观战", duration = 1500 }
                                if cb then cb() end
                            end
                        end,
                    },
                    UI.Button {
                        text = "只看",
                        width = 52, height = 32,
                        fontSize = 10,
                        backgroundColor = COLORS.surfaceHover,
                        borderWidth = 2,
                        borderColor = COLORS.border,
                        onClick = function()
                            local cb = onSkipBet_
                            M.Close()
                            if cb then cb() end
                        end,
                    },
                    UI.Button {
                        text = "返回",
                        width = 52, height = 32,
                        fontSize = 10,
                        backgroundColor = COLORS.surfaceHover,
                        borderWidth = 2,
                        borderColor = COLORS.border,
                        onClick = function()
                            local cb = onCancel_
                            M.Close()
                            if cb then cb() end
                        end,
                    },
                },
            },
        },
    }

    -- 组装：spineLayer 全屏显示 + 顶部/底部栏覆盖
    local rootChildren = {}
    if spineLayer then
        table.insert(rootChildren, spineLayer)
    end
    table.insert(rootChildren, topBar)
    table.insert(rootChildren, bottomBar)

    root_ = UI.Panel {
        width = "100%",
        height = "100%",
        children = rootChildren,
    }

    UI.SetRoot(root_)

    -- 入场动效
    Anim.SlideInFromTop(topBar, { duration = 0.4, distance = 40, ease = "cubicout" })
    Anim.SlideInFromBottom(bottomBar, { duration = 0.5, distance = 60, ease = "backout", delay = 0.15 })
end

return M
