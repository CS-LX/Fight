-- ============================================================================
-- ui/DeploymentEditor.lua - TABS 部署编辑器（PixelForge 像素风）
-- ============================================================================
-- 像素复古风格：
--   左右两侧角色卡面板（方形无圆角 + 硬阴影）
--   顶部像素标题栏 + 底部操作栏
--   中间透明露出 3D 竞技场，点击场地直接放置角色

local UI = require("urhox-libs/UI")
local CharRegistry = require("characters.CharRegistry")

local M = {}

-- ============================================================================
-- PixelForge 像素风设计常量
-- ============================================================================

-- 颜色体系（PixelForge 标准色板）
local COLORS = {
    -- 面板背景
    panelBg         = { 27, 27, 58, 250 },     -- surface
    panelBorder     = { 58, 58, 106, 255 },    -- border
    -- 卡片
    cardBorder      = { 58, 58, 106, 255 },
    cardSelected    = { 255, 200, 40, 255 },    -- golden yellow
    -- 顶栏/底栏
    headerBg        = { 15, 15, 35, 250 },     -- background
    footerBg        = { 15, 15, 35, 250 },
    -- 文字
    gold            = { 255, 217, 61, 255 },   -- warning/gold
    redText         = { 255, 71, 87, 255 },    -- error/red
    blueText        = { 69, 170, 242, 255 },   -- info/blue
    hintText        = { 160, 160, 192, 255 },  -- textSecondary
    white           = { 240, 240, 240, 255 },  -- text
    -- 按钮
    btnPrimary      = { 33, 189, 174, 255 },   -- primary teal
    btnPrimaryHover = { 61, 208, 193, 255 },
    btnPrimaryPress = { 25, 168, 153, 255 },
    btnDanger       = { 255, 71, 87, 255 },
    btnDangerHover  = { 255, 107, 122, 255 },
    btnDangerPress  = { 200, 50, 60, 255 },
    btnSecondary    = { 108, 92, 231, 255 },   -- secondary purple
    btnSecondaryHover = { 133, 119, 237, 255 },
    btnSecondaryPress = { 90, 75, 214, 255 },
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

--- 创建角色卡牌（像素风方形 + 硬阴影 + 无圆角）
---@param team string "red" | "blue"
---@return Widget 卡牌面板
local function CreateCardPanel(team)
    local allIds = CharRegistry.GetAllIds()
    local cards = {}
    local cardRefs = {}

    local isRed = (team == "red")

    for _, id in ipairs(allIds) do
        local mod = CharRegistry.Get(id)
        local name = mod and mod.name or id
        local avatarImg = mod and mod.art and mod.art.avatar or "image/edited_wisdel_avatar_20260529105147.png"

        local capturedId = id
        local card = UI.Panel {
            width = CARD_SIZE,
            height = CARD_SIZE,
            marginBottom = 6,
            overflow = "hidden",
            borderWidth = 2,
            borderColor = COLORS.cardBorder,
            transition = "borderColor 0.1s easeOut",
            cursor = "pointer",
            onClick = function(self)
                selectedCard_ = { moduleId = capturedId, team = team }
                -- 更新本队选中态
                local refs = isRed and redCardRefs_ or blueCardRefs_
                for _, c in ipairs(refs) do
                    c:SetStyle({ borderColor = COLORS.cardBorder, boxShadow = {} })
                end
                self:SetStyle({
                    borderColor = COLORS.cardSelected,
                    boxShadow = {
                        { x = 0, y = 0, blur = 0, spread = 1, color = { 255, 200, 40, 180 } },
                        { x = 0, y = 0, blur = 0, spread = 3, color = { 255, 200, 40, 90 } },
                    },
                })
                -- 清除另一队选中
                local otherRefs = isRed and blueCardRefs_ or redCardRefs_
                for _, c in ipairs(otherRefs) do
                    c:SetStyle({ borderColor = COLORS.cardBorder, boxShadow = {} })
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
                -- 顶部名称条（像素风半透明黑底白字）
                UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0,
                    height = 16,
                    bgColor = { 0, 0, 0, 171 },
                    justifyContent = "center",
                    alignItems = "flex-start",
                    children = {
                        UI.Label {
                            text = name,
                            fontSize = 9,
                            fontColor = COLORS.white,
                            backgroundColor = { 0, 0, 0, 131 },
                            width = "100%",
                            textAlign = "center",
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
                fontWeight = "bold",
                fontColor = teamColor,
                textAlign = "center",
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
        borderWidth = 2,
        borderColor = COLORS.panelBorder,
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

    -- === 顶部标题栏（红蓝渐变） ===
    local header = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0,
        height = 40,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        backgroundGradient = {
            type = "linear",
            direction = "to-right",
            from = { 120, 30, 40, 255 },
            to = { 30, 50, 120, 255 },
        },
        borderWidth = 2,
        borderColor = COLORS.panelBorder,
        children = {
            UI.Label {
                text = "DEPLOY YOUR ARMY",
                fontSize = 16,
                fontWeight = "bold",
                fontColor = COLORS.gold,
                textAlign = "center",
            },
        }
    }

    -- === 底部操作栏（像素风） ===
    -- 红方计数标签
    local redCountBadge = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Panel {
                width = 8, height = 8,
                bgColor = COLORS.redText,
                borderWidth = 1,
                borderColor = { 180, 40, 50, 255 },
            },
            UI.Label {
                text = "RED",
                fontSize = 10,
                fontColor = COLORS.redText,
            },
        },
    }
    redCountLabel_ = UI.Label {
        text = "0",
        fontSize = 16,
        fontWeight = "bold",
        fontColor = COLORS.redText,
        marginLeft = 4,
    }

    local blueCountBadge = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        marginLeft = 16,
        children = {
            UI.Panel {
                width = 8, height = 8,
                bgColor = COLORS.blueText,
                borderWidth = 1,
                borderColor = { 40, 120, 180, 255 },
            },
            UI.Label {
                text = "BLUE",
                fontSize = 10,
                fontColor = COLORS.blueText,
            },
        },
    }
    blueCountLabel_ = UI.Label {
        text = "0",
        fontSize = 16,
        fontWeight = "bold",
        fontColor = COLORS.blueText,
        marginLeft = 4,
    }

    -- 提示文字
    hintLabel_ = UI.Label {
        text = "选择角色卡，然后点击场地放置",
        fontSize = 10,
        fontColor = COLORS.hintText,
        marginLeft = 12,
        flexGrow = 1,
        flexShrink = 1,
    }

    -- 开战按钮（像素风 bevel + 按下动画）
    startBtn_ = UI.Button {
        text = "FIGHT!",
        width = 96,
        height = 34,
        fontSize = 14,
        fontWeight = "bold",
        backgroundColor = COLORS.btnPrimary,
        hoverBackgroundColor = COLORS.btnPrimaryHover,
        pressedBackgroundColor = COLORS.btnPrimaryPress,
        textColor = { 15, 15, 35, 255 },
        borderWidth = 2,
        borderColor = { 25, 168, 153, 255 },
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
        height = 28,
        fontSize = 10,
        fontWeight = "bold",
        backgroundColor = COLORS.btnDanger,
        hoverBackgroundColor = COLORS.btnDangerHover,
        pressedBackgroundColor = COLORS.btnDangerPress,
        textColor = COLORS.white,
        borderWidth = 2,
        borderColor = { 200, 50, 60, 255 },
        marginLeft = 8,
        onClick = function(self)
            if onClear_ then onClear_() end
        end,
    }

    -- 角色制作器入口按钮
    local makerBtn = UI.Button {
        text = "MAKER",
        width = 68,
        height = 28,
        fontSize = 10,
        fontWeight = "bold",
        backgroundColor = COLORS.btnSecondary,
        hoverBackgroundColor = COLORS.btnSecondaryHover,
        pressedBackgroundColor = COLORS.btnSecondaryPress,
        textColor = COLORS.white,
        borderWidth = 2,
        borderColor = { 90, 75, 214, 255 },
        marginLeft = 8,
        onClick = function(self)
            if onOpenMaker_ then onOpenMaker_() end
        end,
    }

    local footer = UI.Panel {
        width = "100%",
        height = 44,
        position = "absolute",
        bottom = 0,
        left = 0,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 12,
        bgColor = COLORS.footerBg,
        borderWidth = 2,
        borderColor = COLORS.panelBorder,
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
        left = 4,
        top = 44,
        bottom = 48,
        children = { redPanel },
    })
    -- 右侧蓝方面板
    table.insert(rootChildren, UI.Panel {
        position = "absolute",
        right = 4,
        top = 44,
        bottom = 48,
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
    print("[DeploymentEditor] Opened - PixelForge pixel-art UI")
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
