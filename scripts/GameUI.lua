-- ============================================================================
-- GameUI.lua - 游戏 HUD（战斗阶段精美 UI）
-- ============================================================================
-- 职责：战斗阶段的 UI 层（计分、状态、胜负、重置）
-- 设计风格：暗色磨砂 + 金色高光 + 描边文字

local UI = require("urhox-libs/UI")
local Config = require("Config")
local CharRender = require("render.CharRender")

local M = {}

-- ============================================================================
-- 设计常量
-- ============================================================================

local COLORS = {
    headerBg    = { 25, 20, 40, 250 },
    gold        = { 255, 215, 60, 255 },
    white       = { 255, 255, 255, 255 },
    redText     = { 255, 90, 90, 255 },
    blueText    = { 90, 150, 255, 255 },
    dimText     = { 180, 180, 180, 230 },
    btnBg       = { 55, 45, 85, 250 },
    btnHover    = { 75, 60, 110, 255 },
    btnPress    = { 40, 30, 65, 255 },
    statusGold  = { 255, 230, 80, 255 },
    shadow      = { 0, 0, 0, 180 },
}

-- UI 引用
---@type Widget|nil
local statusLabel_ = nil
---@type Widget|nil
local redCountLabel_ = nil
---@type Widget|nil
local blueCountLabel_ = nil
---@type Widget|nil
local resultOverlay_ = nil

--- 初始化 UI 系统
function M.Init()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

--- 关闭 UI 系统
function M.Shutdown()
    UI.Shutdown()
end

--- 创建战斗阶段 HUD（含角色 Spine 层 + 精美顶部 HUD + 底部按钮）
---@param characters table[] 逻辑数据列表
---@param onReset function 重置回调
function M.CreateBattleHUD(characters, onReset)
    -- 角色 Spine 容器
    local spineLayer = CharRender.CreateSpines(characters)

    -- 计数
    local redCount = 0
    local blueCount = 0
    for _, c in ipairs(characters) do
        if c.team == "red" then redCount = redCount + 1
        else blueCount = blueCount + 1 end
    end

    -- === 顶部 HUD 栏 ===
    -- 红方计数
    local redDot = UI.Panel {
        width = 12, height = 12,
        borderRadius = 6,
        bgColor = COLORS.redText,
        shadowBlur = 4,
        shadowColor = { 255, 60, 60, 120 },
    }
    redCountLabel_ = UI.Label {
        text = tostring(redCount),
        fontSize = 22,
        fontColor = COLORS.white,
        textStroke = { width = 1.5, color = { 150, 30, 30, 255 } },
        marginLeft = 6,
    }

    -- VS
    statusLabel_ = UI.Label {
        text = "FIGHT!",
        fontSize = 20,
        fontColor = COLORS.statusGold,
        textStroke = { width = 1.5, color = { 80, 60, 0, 200 } },
        textShadow = { offsetX = 0, offsetY = 1, blur = 3, color = { 0, 0, 0, 150 } },
    }

    -- 蓝方计数
    local blueDot = UI.Panel {
        width = 12, height = 12,
        borderRadius = 6,
        bgColor = COLORS.blueText,
        shadowBlur = 4,
        shadowColor = { 60, 100, 255, 120 },
    }
    blueCountLabel_ = UI.Label {
        text = tostring(blueCount),
        fontSize = 22,
        fontColor = COLORS.white,
        textStroke = { width = 1.5, color = { 30, 40, 150, 255 } },
        marginRight = 6,
    }

    local topBar = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0,
        height = 48,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 12,
        bgColor = COLORS.headerBg,
        shadowBlur = 6,
        shadowColor = COLORS.shadow,
        children = {
            redDot,
            redCountLabel_,
            UI.Panel { width = 20 },  -- spacer
            statusLabel_,
            UI.Panel { width = 20 },  -- spacer
            blueCountLabel_,
            blueDot,
        }
    }

    -- === 底部重新部署按钮 ===
    local resetBtn = UI.Button {
        text = "REDEPLOY",
        width = 120,
        height = 38,
        fontSize = 13,
        borderRadius = 19,
        backgroundColor = COLORS.btnBg,
        hoverBackgroundColor = COLORS.btnHover,
        pressedBackgroundColor = COLORS.btnPress,
        textColor = COLORS.white,
        shadowBlur = 4,
        shadowColor = { 0, 0, 0, 100 },
        position = "absolute",
        bottom = 16,
        right = 16,
        onClick = function(self)
            if onReset then onReset() end
        end,
    }

    -- === 结果覆盖层（初始隐藏） ===
    resultOverlay_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        bgColor = { 0, 0, 0, 0 },
        opacity = 0,
        transition = "opacity 0.5s easeOut",
        pointerEvents = "box-none",
        children = {
            UI.Label {
                id = "resultText",
                text = "",
                fontSize = 36,
                fontColor = COLORS.gold,
                textStroke = { width = 2, color = { 60, 40, 0, 255 } },
                textShadow = { offsetX = 0, offsetY = 3, blur = 8, color = { 0, 0, 0, 200 } },
            },
        },
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            spineLayer,
            topBar,
            resetBtn,
            resultOverlay_,
        }
    }

    UI.SetRoot(root)
end

--- 更新队伍存活计数
---@param redAlive number
---@param blueAlive number
function M.UpdateCounts(redAlive, blueAlive)
    if redCountLabel_ then
        redCountLabel_:SetText(tostring(redAlive))
    end
    if blueCountLabel_ then
        blueCountLabel_:SetText(tostring(blueAlive))
    end
end

--- 显示胜利信息（大字居中 + 遮罩渐显）
---@param message string
function M.ShowResult(message)
    if statusLabel_ then
        statusLabel_:SetText(message)
    end
    if resultOverlay_ then
        local textWidget = resultOverlay_:FindById("resultText")
        if textWidget then
            textWidget:SetText(message)
        end
        resultOverlay_:SetStyle({ opacity = 1, bgColor = { 0, 0, 0, 120 } })
    end
end

--- 重置状态文字
function M.ResetStatus()
    if statusLabel_ then
        statusLabel_:SetText("FIGHT!")
    end
    if resultOverlay_ then
        resultOverlay_:SetStyle({ opacity = 0, bgColor = { 0, 0, 0, 0 } })
    end
end

return M
