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
local isAllIn_ = false        -- 是否全押
local rainbowHue_ = 0         -- 彩虹色相
---@type Widget|nil
local fightBtn_ = nil         -- FIGHT按钮引用（用于变色）

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
    isAllIn_ = false
    fightBtn_ = nil
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
    -- 底边栏背景色：随押注方变化
    local BAR_COLOR_RED  = { 120, 30, 35, 240 }
    local BAR_COLOR_BLUE = { 25, 60, 130, 240 }

    -- 押注金额显示
    local betLabel = UI.Label {
        text = betAmount_ .. "G",
        fontSize = 13,
        fontWeight = "bold",
        fontColor = COLORS.gold,
    }

    --- HSV→RGB 转换（h: 0~360, s/v: 0~1）
    local function HSVtoRGB(h, s, v)
        local c = v * s
        local x = c * (1 - math.abs((h / 60) % 2 - 1))
        local m = v - c
        local r, g, b = 0, 0, 0
        if h < 60 then r, g, b = c, x, 0
        elseif h < 120 then r, g, b = x, c, 0
        elseif h < 180 then r, g, b = 0, c, x
        elseif h < 240 then r, g, b = 0, x, c
        elseif h < 300 then r, g, b = x, 0, c
        else r, g, b = c, 0, x
        end
        return math.floor((r + m) * 255), math.floor((g + m) * 255), math.floor((b + m) * 255)
    end

    --- 更新 all-in 状态及 FIGHT 按钮颜色
    local function UpdateAllInState()
        isAllIn_ = (betAmount_ >= maxBet) or (betAmount_ >= 5000)
        if not isAllIn_ and fightBtn_ then
            fightBtn_:SetBackgroundColor(COLORS.primary)
        end
    end

    -- FIGHT 按钮
    local fightBtn = UI.Button {
        text = "FIGHT!",
        width = 100, height = 36,
        fontSize = 12, fontWeight = "bold",
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
    }
    fightBtn_ = fightBtn

    ---@type Widget
    local bottomBar
    bottomBar = UI.Panel {
        width = "100%",
        position = "absolute",
        bottom = 0, left = 0,
        backgroundColor = BAR_COLOR_RED,  -- 默认红方
        borderColor = COLORS.border,
        borderTopWidth = 2,
        padding = 8,
        paddingLeft = 12,
        paddingRight = 12,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            -- 左: 押红 + 返回
            UI.Panel {
                flexDirection = "column",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Button {
                        text = "俺寻思红队能赢",
                        width = 130, height = 30,
                        fontSize = 10, fontWeight = "bold",
                        backgroundColor = COLORS.redText,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            selectedTeam_ = "red"
                            bottomBar:SetBackgroundColor(BAR_COLOR_RED)
                        end,
                    },
                    UI.Button {
                        text = "返回",
                        width = 60, height = 24,
                        fontSize = 9,
                        backgroundColor = COLORS.surfaceHover,
                        borderWidth = 1,
                        borderColor = COLORS.border,
                        onClick = function()
                            local cb = onCancel_
                            M.Close()
                            if cb then cb() end
                        end,
                    },
                },
            },
            -- 中: 金额调节 + ALL IN + FIGHT
            UI.Panel {
                flexDirection = "column",
                alignItems = "center",
                gap = 4,
                children = {
                    -- 金额调节行
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Button {
                                text = "-",
                                width = 26, height = 24,
                                fontSize = 12,
                                boxShadow = PIXEL_SHADOW,
                                onClick = function()
                                    betAmount_ = math.max(0, betAmount_ - 50)
                                    betLabel:SetText(betAmount_ .. "G")
                                    UpdateAllInState()
                                end,
                            },
                            betLabel,
                            UI.Button {
                                text = "+",
                                width = 26, height = 24,
                                fontSize = 12,
                                boxShadow = PIXEL_SHADOW,
                                onClick = function()
                                    betAmount_ = math.min(maxBet, betAmount_ + 50)
                                    betLabel:SetText(betAmount_ .. "G")
                                    UpdateAllInState()
                                end,
                            },
                            UI.Label {
                                text = "/ " .. balance .. "G",
                                fontSize = 8,
                                fontColor = { 200, 200, 220, 200 },
                            },
                            UI.Button {
                                text = "ALL IN",
                                width = 56, height = 24,
                                fontSize = 9, fontWeight = "bold",
                                backgroundColor = { 200, 50, 200, 255 },
                                boxShadow = PIXEL_SHADOW,
                                onClick = function()
                                    betAmount_ = maxBet
                                    betLabel:SetText(betAmount_ .. "G")
                                    isAllIn_ = true
                                end,
                            },
                        },
                    },
                    -- FIGHT 按钮
                    fightBtn,
                },
            },
            -- 右: 押蓝 + 只看
            UI.Panel {
                flexDirection = "column",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Button {
                        text = "显然是蓝队更厉害",
                        width = 130, height = 30,
                        fontSize = 10, fontWeight = "bold",
                        backgroundColor = COLORS.blueText,
                        boxShadow = PIXEL_SHADOW,
                        onClick = function()
                            selectedTeam_ = "blue"
                            bottomBar:SetBackgroundColor(BAR_COLOR_BLUE)
                        end,
                    },
                    UI.Button {
                        text = "只看",
                        width = 60, height = 24,
                        fontSize = 9,
                        backgroundColor = COLORS.surfaceHover,
                        borderWidth = 1,
                        borderColor = COLORS.border,
                        onClick = function()
                            local cb = onSkipBet_
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

-- ============================================================================
-- 彩虹 FIGHT 按钮更新（每帧调用）
-- ============================================================================

--- 在 HandleUpdate 中调用此函数驱动彩虹效果
---@param dt number
function M.Update(dt)
    if not isOpen_ or not isAllIn_ or not fightBtn_ then return end
    rainbowHue_ = (rainbowHue_ + dt * 200) % 360  -- 每秒转200度
    local r, g, b = 0, 0, 0
    -- HSV→RGB inline（s=0.9, v=1.0）
    local h = rainbowHue_
    local c = 0.9
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = 0.1
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x
    end
    local cr = math.floor((r + m) * 255)
    local cg = math.floor((g + m) * 255)
    local cb = math.floor((b + m) * 255)
    fightBtn_:SetBackgroundColor({ cr, cg, cb, 255 })
end

return M
