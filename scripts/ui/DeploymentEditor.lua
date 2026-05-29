-- ============================================================================
-- ui/DeploymentEditor.lua - TABS 部署编辑器（精美卡牌UI版）
-- ============================================================================
-- 全面战争模拟器风格：
--   左右两侧精美角色卡面板（Spine 头像 + 溢出裁剪）
--   顶部醒目标题栏 + 底部精美操作栏
--   中间透明露出 3D 竞技场，点击场地直接放置角色

local UI = require("urhox-libs/UI")
local CharRegistry = require("characters.CharRegistry")

local M = {}

-- ============================================================================
-- 设计常量
-- ============================================================================

-- 颜色体系
local COLORS = {
    -- 面板背景
    panelBg         = { 12, 12, 24, 235 },
    panelBorder     = { 60, 50, 90, 200 },
    -- 卡片
    cardRedBg       = { 70, 20, 20, 200 },
    cardRedSelected = { 200, 50, 50, 255 },
    cardRedBorder   = { 120, 40, 40, 200 },
    cardBlueBg      = { 20, 25, 70, 200 },
    cardBlueSelected= { 50, 80, 220, 255 },
    cardBlueBorder  = { 40, 50, 120, 200 },
    -- 顶栏/底栏
    headerBg        = { 20, 15, 35, 240 },
    footerBg        = { 15, 12, 28, 240 },
    -- 文字
    gold            = { 255, 215, 60, 255 },
    silver          = { 200, 200, 210, 255 },
    redText         = { 255, 100, 100, 255 },
    blueText        = { 100, 160, 255, 255 },
    hintText        = { 180, 180, 160, 180 },
    white           = { 255, 255, 255, 255 },
    -- 按钮
    btnPrimary      = { 220, 170, 30, 255 },
    btnPrimaryHover = { 240, 195, 50, 255 },
    btnPrimaryPress = { 180, 140, 20, 255 },
    btnDanger       = { 160, 50, 50, 255 },
    btnDangerHover  = { 190, 70, 70, 255 },
    btnDangerPress  = { 120, 40, 40, 255 },
}

-- ============================================================================
-- 状态
-- ============================================================================

---@type boolean
local isOpen_ = false

--- 当前选中的角色卡 { moduleId, team } 或 nil
---@type table|nil
local selectedCard_ = nil

--- UI 引用
---@type Widget|nil
local rootWidget_ = nil
---@type Widget|nil
local redCountLabel_ = nil
---@type Widget|nil
local blueCountLabel_ = nil
---@type Widget|nil
local hintLabel_ = nil
---@type Widget|nil
local startBtn_ = nil

--- 卡牌引用（用于切换选中态）
---@type Widget[]
local redCardRefs_ = {}
---@type Widget[]
local blueCardRefs_ = {}

--- 回调
---@type function|nil
local onStartBattle_ = nil
---@type function|nil
local onClear_ = nil

-- ============================================================================
-- 公开接口
-- ============================================================================

function M.GetSelectedCard()
    return selectedCard_
end

function M.UpdateCounts(redCount, blueCount)
    if redCountLabel_ then
        redCountLabel_:SetText(redCount .. "")
    end
    if blueCountLabel_ then
        blueCountLabel_:SetText(blueCount .. "")
    end
end

function M.SetHint(text)
    if hintLabel_ then
        hintLabel_:SetText(text)
    end
end

function M.IsOpen()
    return isOpen_
end

-- ============================================================================
-- UI 构建
-- ============================================================================

--- 创建角色卡牌（含 Spine 头像 + 精美样式）
---@param team string "red" | "blue"
---@return Widget 卡牌面板
local function CreateCardPanel(team)
    local allIds = CharRegistry.GetAllIds()
    local cards = {}
    local cardRefs = {}

    local isRed = (team == "red")
    local cardBg = isRed and COLORS.cardRedBg or COLORS.cardBlueBg
    local cardBorder = isRed and COLORS.cardRedBorder or COLORS.cardBlueBorder
    local cardSelectedBg = isRed and COLORS.cardRedSelected or COLORS.cardBlueSelected

    for _, id in ipairs(allIds) do
        local mod = CharRegistry.Get(id)
        local name = mod and mod.name or id
        local spineSrc = mod and mod.art and mod.art.spineSrc or nil
        local pma = mod and mod.art and mod.art.pma or true
        local idleAnim = mod and mod.art and mod.art.anims and mod.art.anims.idle or "Default"

        -- Spine 缩略图容器（裁剪溢出）
        local thumbContainer = UI.Panel {
            width = 48,
            height = 48,
            overflow = "hidden",
            borderRadius = 6,
            bgColor = { 0, 0, 0, 80 },
            alignItems = "center",
            justifyContent = "center",
            children = spineSrc and {
                UI.Spine {
                    src = spineSrc,
                    animation = idleAnim,
                    loop = true,
                    width = 44,
                    height = 44,
                    objectFit = "contain",
                    pma = pma,
                },
            } or {},
        }

        -- 角色名标签
        local nameLabel = UI.Label {
            text = name,
            fontSize = 10,
            fontColor = COLORS.silver,
            textAlign = "center",
            marginTop = 3,
        }

        local capturedId = id
        local card = UI.Panel {
            width = 64,
            height = 80,
            padding = 4,
            marginBottom = 6,
            alignItems = "center",
            justifyContent = "center",
            bgColor = cardBg,
            borderRadius = 10,
            borderWidth = 1.5,
            borderColor = cardBorder,
            shadowBlur = 4,
            shadowColor = { 0, 0, 0, 100 },
            transition = "bgColor 0.2s easeOut, borderColor 0.2s easeOut, scale 0.15s easeOut",
            cursor = "pointer",
            onClick = function(self)
                selectedCard_ = { moduleId = capturedId, team = team }
                -- 更新本队选中态
                local refs = isRed and redCardRefs_ or blueCardRefs_
                for _, c in ipairs(refs) do
                    c:SetStyle({ bgColor = cardBg, borderColor = cardBorder, scale = 1.0 })
                end
                self:SetStyle({ bgColor = cardSelectedBg, borderColor = COLORS.gold, scale = 1.08 })
                -- 清除另一队选中
                local otherRefs = isRed and blueCardRefs_ or redCardRefs_
                local otherBg = isRed and COLORS.cardBlueBg or COLORS.cardRedBg
                local otherBorder = isRed and COLORS.cardBlueBorder or COLORS.cardRedBorder
                for _, c in ipairs(otherRefs) do
                    c:SetStyle({ bgColor = otherBg, borderColor = otherBorder, scale = 1.0 })
                end
                M.SetHint("点击" .. (isRed and "左半场" or "右半场") .. "放置")
            end,
            children = { thumbContainer, nameLabel },
        }

        table.insert(cards, card)
        table.insert(cardRefs, card)
    end

    -- 保存引用
    if isRed then
        redCardRefs_ = cardRefs
    else
        blueCardRefs_ = cardRefs
    end

    -- 队伍标题
    local teamLabel = isRed and "RED" or "BLUE"
    local teamColor = isRed and COLORS.redText or COLORS.blueText

    local headerRow = UI.Panel {
        width = "100%",
        alignItems = "center",
        marginBottom = 8,
        children = {
            UI.Label {
                text = teamLabel,
                fontSize = 13,
                fontColor = teamColor,
                textAlign = "center",
                textStroke = { width = 1, color = { 0, 0, 0, 180 } },
            },
        },
    }

    -- 拼合为最终面板
    local panelChildren = { headerRow }
    for _, c in ipairs(cards) do
        table.insert(panelChildren, c)
    end

    return UI.Panel {
        width = 80,
        paddingTop = 10,
        paddingBottom = 10,
        paddingHorizontal = 8,
        bgColor = COLORS.panelBg,
        borderRadius = 12,
        borderWidth = 1,
        borderColor = COLORS.panelBorder,
        shadowBlur = 8,
        shadowColor = { 0, 0, 0, 150 },
        alignItems = "center",
        overflow = "scroll",
        children = panelChildren,
    }
end

--- 打开部署编辑器
---@param opts { onStartBattle: function, onClear: function, spineLayer: Widget|nil }
function M.Open(opts)
    opts = opts or {}
    onStartBattle_ = opts.onStartBattle
    onClear_ = opts.onClear
    local spineLayer = opts.spineLayer

    selectedCard_ = nil
    redCardRefs_ = {}
    blueCardRefs_ = {}
    isOpen_ = true

    -- 左侧红方卡牌面板
    local redPanel = CreateCardPanel("red")
    -- 右侧蓝方卡牌面板
    local bluePanel = CreateCardPanel("blue")

    -- === 顶部标题栏 ===
    local header = UI.Panel {
        width = "100%",
        height = 44,
        position = "absolute",
        top = 0,
        left = 0,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        bgColor = COLORS.headerBg,
        borderColor = { 80, 60, 20, 120 },
        borderWidth = 0,
        shadowBlur = 6,
        shadowColor = { 0, 0, 0, 120 },
        children = {
            UI.Label {
                text = "DEPLOY YOUR ARMY",
                fontSize = 18,
                fontColor = COLORS.gold,
                textAlign = "center",
                textStroke = { width = 1.5, color = { 60, 40, 0, 200 } },
                textShadow = { offsetX = 0, offsetY = 2, blur = 4, color = { 0, 0, 0, 150 } },
            },
        }
    }

    -- === 底部操作栏 ===
    -- 红方计数标签
    local redCountBadge = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Panel {
                width = 10, height = 10,
                borderRadius = 5,
                bgColor = COLORS.redText,
            },
            UI.Label {
                text = "RED",
                fontSize = 11,
                fontColor = COLORS.redText,
            },
        },
    }
    redCountLabel_ = UI.Label {
        text = "0",
        fontSize = 20,
        fontColor = COLORS.white,
        textStroke = { width = 1, color = { 120, 30, 30, 255 } },
        marginLeft = 4,
    }

    local blueCountBadge = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        marginLeft = 20,
        children = {
            UI.Panel {
                width = 10, height = 10,
                borderRadius = 5,
                bgColor = COLORS.blueText,
            },
            UI.Label {
                text = "BLUE",
                fontSize = 11,
                fontColor = COLORS.blueText,
            },
        },
    }
    blueCountLabel_ = UI.Label {
        text = "0",
        fontSize = 20,
        fontColor = COLORS.white,
        textStroke = { width = 1, color = { 30, 40, 120, 255 } },
        marginLeft = 4,
    }

    -- 提示文字
    hintLabel_ = UI.Label {
        text = "选择角色卡，然后点击场地放置",
        fontSize = 12,
        fontColor = COLORS.hintText,
        marginLeft = 16,
        flexGrow = 1,
        flexShrink = 1,
    }

    -- 开战按钮
    startBtn_ = UI.Button {
        text = "FIGHT!",
        width = 100,
        height = 38,
        fontSize = 16,
        borderRadius = 19,
        backgroundColor = COLORS.btnPrimary,
        hoverBackgroundColor = COLORS.btnPrimaryHover,
        pressedBackgroundColor = COLORS.btnPrimaryPress,
        textColor = { 30, 20, 0, 255 },
        shadowBlur = 6,
        shadowColor = { 220, 170, 30, 100 },
        onClick = function(self)
            if onStartBattle_ then
                onStartBattle_()
            end
        end,
    }

    -- 清空按钮
    local clearBtn = UI.Button {
        text = "CLEAR",
        width = 64,
        height = 30,
        fontSize = 11,
        borderRadius = 15,
        backgroundColor = COLORS.btnDanger,
        hoverBackgroundColor = COLORS.btnDangerHover,
        pressedBackgroundColor = COLORS.btnDangerPress,
        textColor = COLORS.white,
        marginLeft = 8,
        onClick = function(self)
            if onClear_ then onClear_() end
        end,
    }

    local footer = UI.Panel {
        width = "100%",
        height = 52,
        position = "absolute",
        bottom = 0,
        left = 0,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 16,
        bgColor = COLORS.footerBg,
        shadowBlur = 6,
        shadowColor = { 0, 0, 0, 120 },
        children = {
            redCountBadge,
            redCountLabel_,
            blueCountBadge,
            blueCountLabel_,
            hintLabel_,
            startBtn_,
            clearBtn,
        }
    }

    -- === 根布局 ===
    local rootChildren = {}

    -- spine 角色层在最底部
    if spineLayer then
        table.insert(rootChildren, spineLayer)
    end

    -- 左侧红方面板
    table.insert(rootChildren, UI.Panel {
        position = "absolute",
        left = 6,
        top = 52,
        bottom = 60,
        children = { redPanel },
    })
    -- 右侧蓝方面板
    table.insert(rootChildren, UI.Panel {
        position = "absolute",
        right = 6,
        top = 52,
        bottom = 60,
        children = { bluePanel },
    })
    table.insert(rootChildren, header)
    table.insert(rootChildren, footer)

    rootWidget_ = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = rootChildren,
    }

    UI.SetRoot(rootWidget_)
    print("[DeploymentEditor] Opened - TABS deployment with premium UI")
end

--- 关闭部署编辑器
function M.Close()
    if not isOpen_ then return end
    isOpen_ = false
    rootWidget_ = nil
    redCountLabel_ = nil
    blueCountLabel_ = nil
    hintLabel_ = nil
    startBtn_ = nil
    selectedCard_ = nil
    redCardRefs_ = {}
    blueCardRefs_ = {}
    print("[DeploymentEditor] Closed")
end

return M
