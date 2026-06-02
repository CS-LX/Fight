-- ============================================================================
-- GameUI.lua - 游戏 HUD（战斗阶段精美 UI）
-- ============================================================================
-- 职责：战斗阶段的 UI 层（计分、状态、胜负、重置）
-- 设计风格：PixelForge 像素复古风

local UI = require("urhox-libs/UI")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
local Config = require("Config")
local CharRender = require("render.CharRender")
local Anim = require("ui.UIAnimations")

local M = {}

-- ============================================================================
-- PixelForge 像素风设计常量
-- ============================================================================

-- Button shadow: 3px hard drop + top-left bevel (Buttons ONLY)
local PIXEL_SHADOW = {
    { x = 3, y = 3, blur = 0, color = {10, 10, 26, 204} },
    { x = -1, y = -1, blur = 0, color = {255, 255, 255, 48} },
}

local COLORS = {
    -- PixelForge 标准色板
    background  = { 15, 15, 35, 255 },     -- #0F0F23
    surface     = { 27, 27, 58, 255 },     -- #1B1B3A
    surfaceHover= { 37, 37, 80, 255 },     -- #252550
    primary     = { 33, 189, 174, 255 },   -- #21BDAE teal
    primaryDark = { 25, 168, 153, 255 },   -- #19A899
    secondary   = { 108, 92, 231, 255 },   -- #6C5CE7 purple
    text        = { 240, 240, 240, 255 },  -- #F0F0F0
    textMuted   = { 160, 160, 192, 255 },  -- #A0A0C0
    border      = { 58, 58, 106, 255 },    -- #3A3A6A
    -- 队伍颜色
    redText     = { 255, 71, 87, 255 },    -- #FF4757
    blueText    = { 69, 170, 242, 255 },   -- #45AAF2
    -- 功能色
    gold        = { 255, 217, 61, 255 },   -- #FFD93D
    white       = { 240, 240, 240, 255 },
    shadow      = { 10, 10, 26, 204 },
    -- 按钮色
    btnPrimary  = { 33, 189, 174, 255 },
    btnHover    = { 61, 208, 193, 255 },
    btnPress    = { 25, 168, 153, 255 },
    btnDanger   = { 255, 71, 87, 255 },
    btnDangerHover = { 255, 107, 122, 255 },
    btnDangerPress = { 200, 50, 60, 255 },
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
---@type Widget|nil
local topBar_ = nil
---@type Widget|nil
local gradientBg_ = nil

-- Profile 数据（由 CreateBattleHUD 传入）
---@type {name: string, avatar: string}|nil
local redProfile_ = nil
---@type {name: string, avatar: string}|nil
local blueProfile_ = nil

-- 动效追踪
local prevRedCount_ = -1
local prevBlueCount_ = -1

--- 初始化 UI 系统（PixelForge 像素风主题）
function M.Init()
    local PixelForgeTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        colors = {
            primary = {33, 189, 174, 255},
            primaryHover = {61, 208, 193, 255},
            primaryPressed = {25, 168, 153, 255},
            secondary = {108, 92, 231, 255},
            secondaryHover = {133, 119, 237, 255},
            secondaryPressed = {90, 75, 214, 255},
            background = {15, 15, 35, 255},
            surface = {27, 27, 58, 255},
            surfaceHover = {37, 37, 80, 255},
            text = {240, 240, 240, 255},
            textSecondary = {160, 160, 192, 255},
            textDisabled = {80, 80, 112, 255},
            border = {58, 58, 106, 255},
            borderFocus = {33, 189, 174, 255},
            disabled = {42, 42, 74, 255},
            disabledText = {80, 80, 112, 255},
            success = {80, 200, 120, 255},
            warning = {255, 217, 61, 255},
            error = {255, 71, 87, 255},
            overlay = {0, 0, 0, 180},
        },
        radius = {
            sm = 0, md = 0, lg = 0, xl = 0, full = 0,
        },
        componentDefaults = {
            borderRadius = 0,
        },
        components = {
            Button = { borderWidth = 2, boxShadow = PIXEL_SHADOW },
            Card = {
                borderWidth = 2,
                boxShadow = {
                    { x = 4, y = 4, blur = 0, color = {10, 10, 26, 204} },
                },
            },
        },
    })

    -- 平台字体选择：仅桌面原生端用像素字体，其余（移动端/Web编辑器）用 MiSans
    -- 原因：像素字体 CJK 字形集约 7MB/个，Web/移动端异步加载会导致文字不显示
    local fonts
    if PlatformUtils.IsDesktopPlatform() then
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/FusionPixel-12px-Prop-zh_hans.ttf",
                bold   = "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf",
            }},
            { family = "mono", weights = {
                normal = "Fonts/FusionPixel-12px-Mono-zh_hans.ttf",
            }},
        }
    else
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } },
        }
    end

    UI.Init({
        theme = PixelForgeTheme,
        fonts = fonts,
        scale = UI.Scale.DEFAULT,
    })
end

--- 关闭 UI 系统
function M.Shutdown()
    UI.Shutdown()
end

--- 创建战斗阶段 HUD（含角色 Spine 层 + 像素风顶部 HUD + 底部按钮）
---@param characters table[] 逻辑数据列表
---@param onReset function 重置回调
---@param opts? {redProfile?: {name: string, avatar: string}, blueProfile?: {name: string, avatar: string}}
function M.CreateBattleHUD(characters, onReset, opts)
    opts = opts or {}
    redProfile_ = opts.redProfile
    blueProfile_ = opts.blueProfile

    -- 角色 Spine 容器
    local spineLayer = CharRender.CreateSpines(characters)

    -- 计数
    local redCount = 0
    local blueCount = 0
    for _, c in ipairs(characters) do
        if c.team == "red" then redCount = redCount + 1
        else blueCount = blueCount + 1 end
    end

    -- === 顶部 HUD 栏（像素风 + Profile） ===

    -- 红方头像+昵称+计数
    local redAvatar = nil
    if redProfile_ and redProfile_.avatar then
        redAvatar = UI.Panel {
            width = 28, height = 28,
            backgroundImage = redProfile_.avatar,
            borderWidth = 2,
            borderColor = COLORS.redText,
        }
    end
    local redNameLabel = nil
    if redProfile_ and redProfile_.name then
        redNameLabel = UI.Label {
            text = redProfile_.name,
            fontSize = 11,
            fontColor = { 255, 200, 200, 255 },
            marginLeft = 4,
        }
    end
    redCountLabel_ = UI.Label {
        text = tostring(redCount),
        fontSize = 18,
        fontWeight = "bold",
        fontColor = COLORS.redText,
        marginLeft = 4,
    }

    -- VS
    statusLabel_ = UI.Label {
        text = "FIGHT!",
        fontSize = 18,
        fontWeight = "bold",
        fontColor = COLORS.gold,
    }

    -- 蓝方计数+昵称+头像
    blueCountLabel_ = UI.Label {
        text = tostring(blueCount),
        fontSize = 18,
        fontWeight = "bold",
        fontColor = COLORS.blueText,
        marginRight = 4,
    }
    local blueNameLabel = nil
    if blueProfile_ and blueProfile_.name then
        blueNameLabel = UI.Label {
            text = blueProfile_.name,
            fontSize = 11,
            fontColor = { 200, 220, 255, 255 },
            marginRight = 4,
        }
    end
    local blueAvatar = nil
    if blueProfile_ and blueProfile_.avatar then
        blueAvatar = UI.Panel {
            width = 28, height = 28,
            backgroundImage = blueProfile_.avatar,
            borderWidth = 2,
            borderColor = COLORS.blueText,
        }
    end

    -- 红蓝渐变背景（线性渐变：左红→右蓝）
    gradientBg_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundGradient = {
            type = "linear",
            direction = "to-right",
            from = { 120, 30, 40, 255 },
            to = { 30, 50, 120, 255 },
        },
    }

    -- 构建顶部栏内容子项（红方左侧 | VS | 蓝方右侧）
    local topChildren = {}
    if redAvatar then table.insert(topChildren, redAvatar) end
    if redNameLabel then table.insert(topChildren, redNameLabel) end
    table.insert(topChildren, redCountLabel_)
    table.insert(topChildren, UI.Panel { width = 12 })
    table.insert(topChildren, statusLabel_)
    table.insert(topChildren, UI.Panel { width = 12 })
    table.insert(topChildren, blueCountLabel_)
    if blueNameLabel then table.insert(topChildren, blueNameLabel) end
    if blueAvatar then table.insert(topChildren, blueAvatar) end

    local topBar = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0,
        height = 44,
        borderWidth = 2,
        borderColor = COLORS.border,
        children = {
            gradientBg_,
            -- 前景层：头像+昵称+计数
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                paddingHorizontal = 8,
                gap = 4,
                children = topChildren,
            },
        }
    }
    topBar_ = topBar

    -- === 底部重新部署按钮（像素风 bevel） ===
    local resetBtn = UI.Button {
        text = "REDEPLOY",
        width = 120,
        height = 36,
        fontSize = 12,
        fontWeight = "bold",
        backgroundColor = COLORS.secondary,
        hoverBackgroundColor = { 133, 119, 237, 255 },
        pressedBackgroundColor = { 90, 75, 214, 255 },
        textColor = COLORS.white,
        borderWidth = 2,
        borderColor = { 80, 65, 180, 255 },
        position = "absolute",
        bottom = 12,
        right = 12,
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
        transition = "opacity 0.4s easeOut",
        pointerEvents = "box-none",
        children = {
            UI.Label {
                id = "resultText",
                text = "",
                fontSize = 28,
                fontWeight = "bold",
                fontColor = COLORS.gold,
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

    -- === 入场动画 ===
    Anim.SlideInFromTop(topBar, { duration = 0.5, distance = 50, ease = "backout" })
    Anim.FadeIn(resetBtn, { duration = 0.4, delay = 0.3 })
end

--- 更新队伍存活计数（带数字滚动动效）
---@param redAlive number
---@param blueAlive number
function M.UpdateCounts(redAlive, blueAlive)
    if redCountLabel_ then
        if prevRedCount_ >= 0 and prevRedCount_ ~= redAlive then
            Anim.CountUp(redCountLabel_, prevRedCount_, redAlive, { duration = 0.4 })
        else
            redCountLabel_:SetText(tostring(redAlive))
        end
        prevRedCount_ = redAlive
    end
    if blueCountLabel_ then
        if prevBlueCount_ >= 0 and prevBlueCount_ ~= blueAlive then
            Anim.CountUp(blueCountLabel_, prevBlueCount_, blueAlive, { duration = 0.4 })
        else
            blueCountLabel_:SetText(tostring(blueAlive))
        end
        prevBlueCount_ = blueAlive
    end
end

--- 颜色插值
local function lerpColor(a, b, t)
    return {
        math.floor(a[1] + (b[1] - a[1]) * t),
        math.floor(a[2] + (b[2] - a[2]) * t),
        math.floor(a[3] + (b[3] - a[3]) * t),
        math.floor(a[4] + (b[4] - a[4]) * t),
    }
end

local RED_FULL = { 180, 40, 50, 255 }
local RED_DIM = { 80, 25, 35, 255 }
local BLUE_FULL = { 40, 70, 180, 255 }
local BLUE_DIM = { 25, 35, 80, 255 }

--- 更新血量比例（渐变颜色强度随 HP 变化）
---@param redRatio number 红方HP系数 (currentHP/initialHP)
---@param blueRatio number 蓝方HP系数 (currentHP/initialHP)
function M.UpdateHPRatio(redRatio, blueRatio)
    if not gradientBg_ then return end
    -- 红方血量越多红色越亮，蓝方同理
    local fromColor = lerpColor(RED_DIM, RED_FULL, math.min(redRatio, 1.0))
    local toColor = lerpColor(BLUE_DIM, BLUE_FULL, math.min(blueRatio, 1.0))
    gradientBg_:SetStyle({
        backgroundGradient = {
            type = "linear",
            direction = "to-right",
            from = fromColor,
            to = toColor,
        },
    })
end

--- 显示胜利信息（像素风大字居中）
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
        resultOverlay_:SetStyle({ opacity = 1, bgColor = { 10, 10, 26, 160 } })
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
    -- 重置计数追踪（新战斗开始时首次设置不触发动画）
    prevRedCount_ = -1
    prevBlueCount_ = -1
end

--- 显示战斗结算面板（含收支明细 + 返回按钮）
---@param title string 标题（"VICTORY!" / "DEFEAT" / "SPONSOR WIN!"）
---@param isWin boolean 是否胜利（影响颜色）
---@param items table[] 明细列表 { label: string, amount: number, unit?: string }
---@param onContinue function 点击"返回大厅"的回调
function M.ShowSettlement(title, isWin, items, onContinue)
    if not resultOverlay_ then return end

    -- 计算净收益
    local netTotal = 0
    for _, item in ipairs(items) do
        if not item.unit then  -- 只累加金币项
            netTotal = netTotal + item.amount
        end
    end

    -- 标题颜色
    local titleColor = isWin and COLORS.gold or COLORS.redText

    -- 构建明细行
    local detailRows = {}
    for _, item in ipairs(items) do
        local unit = item.unit or "G"
        local amountStr
        local amountColor
        if item.amount > 0 then
            amountStr = "+" .. item.amount .. unit
            amountColor = { 80, 200, 120, 255 }  -- green
        elseif item.amount < 0 then
            amountStr = tostring(item.amount) .. unit
            amountColor = COLORS.redText
        else
            amountStr = "0" .. unit
            amountColor = COLORS.textMuted
        end

        table.insert(detailRows, UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            width = "100%",
            paddingVertical = 2,
            children = {
                UI.Label { text = item.label, fontSize = 11, fontColor = COLORS.textMuted },
                UI.Label { text = amountStr, fontSize = 11, fontWeight = "bold", fontColor = amountColor },
            }
        })
    end

    -- 分隔线
    table.insert(detailRows, UI.Panel {
        width = "100%",
        height = 2,
        bgColor = COLORS.border,
        marginVertical = 4,
    })

    -- 净收益行
    local netColor = netTotal >= 0 and { 80, 200, 120, 255 } or COLORS.redText
    local netStr = (netTotal >= 0 and "+" or "") .. netTotal .. "G"
    table.insert(detailRows, UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        width = "100%",
        children = {
            UI.Label { text = "净收益", fontSize = 12, fontWeight = "bold", fontColor = COLORS.text },
            UI.Label { text = netStr, fontSize = 14, fontWeight = "bold", fontColor = netColor },
        }
    })

    -- 当前余额行
    local Economy = require("economy.Economy")
    table.insert(detailRows, UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        width = "100%",
        marginTop = 4,
        children = {
            UI.Label { text = "当前余额", fontSize = 10, fontColor = COLORS.textMuted },
            UI.Label { text = tostring(Economy.GetBalance()) .. "G", fontSize = 12, fontWeight = "bold", fontColor = COLORS.gold },
        }
    })

    -- 结算卡片
    local settlementCard = UI.Panel {
        width = 220,
        bgColor = COLORS.surface,
        backgroundColor = {0, 7, 52, 115},
        borderWidth = 2,
        borderColor = COLORS.border,
        padding = 16,
        alignItems = "center",
        gap = 8,
        children = {
            -- 标题
            UI.Label { text = title, fontSize = 22, fontWeight = "bold", fontColor = titleColor },
            -- 副标题分隔
            UI.Panel { width = 140, height = 2, bgColor = COLORS.border, marginVertical = 4 },
            -- 结算标签
            UI.Label { text = "— 结算明细 —", fontSize = 10, fontColor = COLORS.textMuted },
            -- 明细区域
            UI.Panel {
                width = "100%",
                paddingHorizontal = 4,
                gap = 0,
                children = detailRows,
            },
            -- 返回按钮
            UI.Button {
                text = "返回大厅",
                width = 140,
                height = 32,
                fontSize = 12,
                fontWeight = "bold",
                marginTop = 8,
                variant = "primary",
                onClick = function(self)
                    if onContinue then onContinue() end
                end,
            },
        },
    }

    -- 替换 resultOverlay_ 内容
    resultOverlay_:ClearChildren()
    resultOverlay_:AddChild(settlementCard)
    resultOverlay_:SetStyle({ opacity = 1, bgColor = { 10, 10, 26, 200 }, pointerEvents = "auto" })

    -- 结算卡片弹入动画
    Anim.PopIn(settlementCard, { duration = 0.4, delay = 0.1, ease = "backout" })
end

return M
