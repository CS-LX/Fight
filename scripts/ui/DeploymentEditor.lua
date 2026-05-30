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
    -- 面板背景（实底带微透）
    panelBg         = { 30, 28, 45, 245 },
    panelBorder     = { 80, 65, 110, 255 },
    -- 卡片
    cardRedBg       = { 90, 30, 30, 240 },
    cardRedSelected = { 200, 50, 50, 255 },
    cardRedBorder   = { 150, 55, 55, 255 },
    cardBlueBg      = { 30, 38, 90, 240 },
    cardBlueSelected= { 50, 80, 220, 255 },
    cardBlueBorder  = { 55, 65, 150, 255 },
    -- 顶栏/底栏（实底）
    headerBg        = { 25, 20, 40, 250 },
    footerBg        = { 22, 18, 38, 250 },
    -- 文字
    gold            = { 255, 215, 60, 255 },
    silver          = { 220, 220, 230, 255 },
    redText         = { 255, 100, 100, 255 },
    blueText        = { 100, 160, 255, 255 },
    hintText        = { 200, 200, 180, 220 },
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
---@type function|nil
local onOpenMaker_ = nil

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

--- 角色卡尺寸
local CARD_SIZE = 72

--- 创建角色卡牌（方形头像撑满 + 顶部黑底名称条）
---@param team string "red" | "blue"
---@return Widget 卡牌面板
local function CreateCardPanel(team)
    local allIds = CharRegistry.GetAllIds()
    local cards = {}
    local cardRefs = {}

    local isRed = (team == "red")
    local cardSelectedBorder = isRed and COLORS.cardRedSelected or COLORS.cardBlueSelected

    for _, id in ipairs(allIds) do
        local mod = CharRegistry.Get(id)
        local name = mod and mod.name or id
        local avatarImg = mod and mod.art and mod.art.avatar or "image/edited_wisdel_avatar_20260529105147.png"

        local capturedId = id
        local card = UI.Panel {
            width = CARD_SIZE,
            height = CARD_SIZE,
            marginBottom = 6,
            borderRadius = 4,
            overflow = "hidden",
            borderWidth = 2,
            borderColor = { 40, 40, 50, 200 },
            shadowBlur = 4,
            shadowColor = { 0, 0, 0, 120 },
            transition = "borderColor 0.15s easeOut, scale 0.12s easeOut",
            cursor = "pointer",
            onClick = function(self)
                selectedCard_ = { moduleId = capturedId, team = team }
                -- 更新本队选中态
                local refs = isRed and redCardRefs_ or blueCardRefs_
                for _, c in ipairs(refs) do
                    c:SetStyle({ borderColor = { 40, 40, 50, 200 }, scale = 1.0 })
                end
                self:SetStyle({ borderColor = COLORS.gold, scale = 1.06 })
                -- 清除另一队选中
                local otherRefs = isRed and blueCardRefs_ or redCardRefs_
                for _, c in ipairs(otherRefs) do
                    c:SetStyle({ borderColor = { 40, 40, 50, 200 }, scale = 1.0 })
                end
                M.SetHint("点击" .. (isRed and "左半场" or "右半场") .. "放置")
            end,
            children = {
                -- 背景头像（撑满整个卡片）
                UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0, bottom = 0,
                    backgroundImage = avatarImg,
                    backgroundFit = "cover",
                },
                -- 顶部名称条（黑底白字）
                UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0,
                    height = 18,
                    bgColor = { 0, 0, 0, 180 },
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = name,
                            fontSize = 10,
                            fontColor = COLORS.white,
                            textAlign = "center",
                            backgroundColor = { 0, 0, 0, 199 },
                        },
                    },
                },
            },
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
        marginBottom = 6,
        children = {
            UI.Label {
                text = teamLabel,
                fontSize = 12,
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
        width = CARD_SIZE + 16,
        paddingTop = 8,
        paddingBottom = 8,
        paddingHorizontal = 8,
        bgColor = COLORS.panelBg,
        borderRadius = 8,
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
---@param opts { onStartBattle: function, onClear: function, onOpenMaker: function|nil, spineLayer: Widget|nil }
function M.Open(opts)
    opts = opts or {}
    onStartBattle_ = opts.onStartBattle
    onClear_ = opts.onClear
    onOpenMaker_ = opts.onOpenMaker
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

    -- 角色制作器入口按钮
    local makerBtn = UI.Button {
        text = "MAKER",
        width = 68,
        height = 30,
        fontSize = 11,
        borderRadius = 15,
        backgroundColor = { 60, 120, 200, 255 },
        hoverBackgroundColor = { 80, 145, 230, 255 },
        pressedBackgroundColor = { 45, 95, 170, 255 },
        textColor = COLORS.white,
        marginLeft = 8,
        onClick = function(self)
            if onOpenMaker_ then onOpenMaker_() end
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
            makerBtn,
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
