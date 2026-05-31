-- ============================================================================
-- ui/Lobby.lua - 竞技大厅（Phase 2 主入口）
-- ============================================================================
-- 职责：模式选择入口 + 金币余额/段位显示 + 救济金入口
-- 模式：1) AI对战  2) 排位对战  3) 赞助观战
-- 设计风格：PixelForge 像素复古风

local UI = require("urhox-libs/UI")
local Economy = require("economy.Economy")
local Ranked = require("economy.Ranked")
local Anim = require("ui.UIAnimations")
-- LLM 网络模块（当前仅预留，需 persistent_world 服务端支持）
-- local LLMClient = require("network.Client")

local M = {}

-- ============================================================================
-- PixelForge 色板（与 GameUI 保持一致）
-- ============================================================================

local COLORS = {
    background  = { 15, 15, 35, 255 },
    surface     = { 27, 27, 58, 255 },
    surfaceHover= { 37, 37, 80, 255 },
    primary     = { 33, 189, 174, 255 },
    primaryDark = { 25, 168, 153, 255 },
    secondary   = { 108, 92, 231, 255 },
    text        = { 240, 240, 240, 255 },
    textMuted   = { 160, 160, 192, 255 },
    border      = { 58, 58, 106, 255 },
    gold        = { 255, 217, 61, 255 },
    redText     = { 255, 71, 87, 255 },
    blueText    = { 69, 170, 242, 255 },
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
---@type Widget|nil
local balanceLabel_ = nil
---@type Widget|nil
local crystalLabel_ = nil

--- 回调
---@type {onBattle: function, onRanked: function, onSpectate: function, onMaker: function}|nil
local callbacks_ = nil

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 打开大厅 UI
---@param opts {onBattle: function, onRanked: function, onSpectate: function, onMaker: function}
function M.Open(opts)
    callbacks_ = opts
    isOpen_ = true

    Economy.Init(function()
        -- 云端数据就绪后刷新余额显示
        M.RefreshBalance()
    end)
    Ranked.Init()

    M.BuildUI()
end

--- 关闭大厅 UI
function M.Close()
    isOpen_ = false
    callbacks_ = nil
    if root_ then
        UI.SetRoot(nil)
        root_ = nil
        balanceLabel_ = nil
        crystalLabel_ = nil
    end
end

--- 是否打开
---@return boolean
function M.IsOpen()
    return isOpen_
end

--- 获取根节点（供 GM 面板等附加 UI 使用）
---@return Widget|nil
function M.GetRoot()
    return root_
end

--- 刷新余额显示
function M.RefreshBalance()
    if balanceLabel_ then
        balanceLabel_:SetText(tostring(Economy.GetBalance()))
    end
    if crystalLabel_ then
        crystalLabel_:SetText(tostring(Economy.GetCrystal()))
    end
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function M.BuildUI()
    -- 金币余额标签（保存引用以便刷新）
    balanceLabel_ = UI.Label {
        text = tostring(Economy.GetBalance()),
        fontSize = 14,
        fontWeight = "bold",
        fontColor = COLORS.gold,
    }

    -- 创造晶余额标签
    crystalLabel_ = UI.Label {
        text = tostring(Economy.GetCrystal()),
        fontSize = 14,
        fontWeight = "bold",
        fontColor = { 180, 120, 255, 255 },  -- 紫色代表创造晶
    }

    -- 段位信息
    local tier = Ranked.GetTier()
    local tierProgress = Ranked.GetTierProgress()
    local nextScore = Ranked.GetNextTierScore()

    -- 顶部状态栏（金币 + 段位）
    local topBar = UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingRight = 16,
        paddingLeft = 16,
        backgroundGradient = {
            type = "linear",
            direction = "to-right",
            from = { 20, 18, 48, 240 },
            to = { 30, 25, 55, 240 },
        },
        borderBottomWidth = 1,
        borderColor = { 58, 58, 106, 120 },
        children = {
            -- 左侧：段位
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "RANK",
                        fontSize = 9,
                        fontColor = COLORS.textMuted,
                        marginRight = 6,
                    },
                    UI.Label {
                        text = tier.name,
                        fontSize = 12,
                        fontWeight = "bold",
                        fontColor = tier.color,
                    },
                    UI.Label {
                        text = "  " .. Ranked.GetScore() .. "pt",
                        fontSize = 10,
                        fontColor = COLORS.textMuted,
                    },
                },
            },
            -- 右侧：金币 + 创造晶
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 14,
                children = {
                    -- 创造晶
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "◆",
                                fontSize = 10,
                                fontColor = { 180, 120, 255, 255 },
                                marginRight = 3,
                            },
                            crystalLabel_,
                        },
                    },
                    -- 金币
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "GOLD",
                                fontSize = 10,
                                fontColor = COLORS.textMuted,
                                marginRight = 6,
                            },
                            balanceLabel_,
                        },
                    },
                },
            },
        },
    }

    -- 标题（带光晕装饰）
    local title = UI.Panel {
        alignItems = "center",
        marginTop = 24,
        marginBottom = 20,
        children = {
            -- 标题发光底层
            UI.Panel {
                position = "absolute",
                top = -10, left = -40, right = -40,
                height = 50,
                borderRadius = 25,
                backgroundGradient = {
                    type = "radial",
                    from = { 33, 189, 174, 30 },
                    to = { 33, 189, 174, 0 },
                },
            },
            UI.Label {
                text = "⚔ ARENA LOBBY ⚔",
                fontSize = 22,
                fontWeight = "bold",
                fontColor = COLORS.primary,
            },
            UI.Label {
                text = "选择你的比赛方式",
                fontSize = 11,
                fontColor = COLORS.textMuted,
                marginTop = 4,
            },
        },
    }

    -- AI 模式提示（LLM 功能预留，需配置服务端后启用）
    local llmToggle = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        marginBottom = 14,
        gap = 10,
        children = {
            UI.Label {
                text = "AI 模式: 阵型AI",
                fontSize = 10,
                fontColor = COLORS.textMuted,
            },
        },
    }

    -- 模式卡片1：AI 对战
    local battleCard = M.CreateModeCard({
        title = "AI 对战",
        desc = "部署你的战队，与AI对手正面交锋",
        cost = "部署费: " .. Economy.Config.DEPLOY_COST_PER_UNIT .. "G/角色",
        reward = "胜利奖励: " .. Economy.Config.WIN_BASE_REWARD .. "G+",
        btnText = "进入部署",
        btnColor = COLORS.primary,
        onClick = function()
            if callbacks_ and callbacks_.onBattle then
                local cb = callbacks_.onBattle
                M.Close()
                cb()
            end
        end,
    })

    -- 模式卡片2：排位对战
    local rankedReward = math.floor(Economy.Config.WIN_BASE_REWARD * Ranked.Config.REWARD_MULTIPLIER)
    local rankedCard = M.CreateModeCard({
        title = "排位对战",
        desc = tier.name .. "段 · 更强AI · 更高回报",
        cost = "部署费: " .. Economy.Config.DEPLOY_COST_PER_UNIT .. "G/角色",
        reward = "胜利奖励: " .. rankedReward .. "G+ (×1.5)",
        btnText = "排位匹配",
        btnColor = tier.color,
        onClick = function()
            if callbacks_ and callbacks_.onRanked then
                local cb = callbacks_.onRanked
                M.Close()
                cb()
            end
        end,
    })

    -- 模式卡片3：赞助观战
    local spectateCard = M.CreateModeCard({
        title = "赞助观战",
        desc = "观看AI对战，押注你看好的队伍",
        cost = "押注: " .. Economy.Config.SPONSOR_MIN_BET .. "~" .. Economy.Config.SPONSOR_MAX_BET .. "G",
        reward = "猜对翻 " .. string.format("%.1fx", Economy.Config.SPONSOR_WIN_MULTIPLIER),
        btnText = "寻找比赛",
        btnColor = COLORS.secondary,
        onClick = function()
            if callbacks_ and callbacks_.onSpectate then
                local cb = callbacks_.onSpectate
                M.Close()
                cb()
            end
        end,
    })

    -- 救济金按钮（仅当余额低时显示）
    local reliefPanel = nil
    local canRelief, _ = Economy.CanClaimRelief()
    if canRelief or Economy.GetBalance() < Economy.Config.RELIEF_THRESHOLD then
        reliefPanel = UI.Panel {
            marginTop = 12,
            alignItems = "center",
            children = {
                UI.Button {
                    text = canRelief and ("领取救济金 +" .. Economy.Config.RELIEF_AMOUNT .. "G") or "救济金(今日已领)",
                    variant = "outline",
                    width = 200,
                    height = 32,
                    disabled = not canRelief,
                    onClick = function()
                        local ok, msg = Economy.ClaimRelief()
                        if ok then
                            M.RefreshBalance()
                            -- 重建UI刷新按钮状态
                            M.BuildUI()
                        end
                        print("[Lobby] Relief: " .. msg)
                    end,
                },
                Economy.IsInNewbieProtection() and UI.Label {
                    text = "新手保护中: 部署费减半",
                    fontSize = 9,
                    fontColor = COLORS.gold,
                    marginTop = 4,
                } or nil,
            },
        }
    end

    -- 底部按钮：角色制作
    local makerBtn = UI.Button {
        text = "角色工坊",
        variant = "outline",
        width = 200,
        height = 36,
        onClick = function()
            if callbacks_ and callbacks_.onMaker then
                local cb = callbacks_.onMaker
                M.Close()
                cb()
            end
        end,
    }

    -- 段位进度条（排位卡片下方）
    local progressBar = UI.Panel {
        width = 200,
        marginTop = 12,
        alignItems = "center",
        children = {
            -- 进度条背景
            UI.Panel {
                width = "100%",
                height = 8,
                backgroundColor = COLORS.surface,
                borderWidth = 1,
                borderColor = COLORS.border,
                children = {
                    UI.Panel {
                        width = tostring(math.floor(tierProgress * 100)) .. "%",
                        height = "100%",
                        backgroundColor = tier.color,
                    },
                },
            },
            -- 进度文本
            UI.Label {
                text = nextScore
                    and (Ranked.GetScore() .. " / " .. nextScore .. " pt")
                    or "MAX",
                fontSize = 8,
                fontColor = COLORS.textMuted,
                marginTop = 2,
            },
        },
    }

    -- 胜率统计
    local statsRow = UI.Panel {
        flexDirection = "row",
        gap = 16,
        marginTop = 6,
        children = {
            UI.Label {
                text = "场次: " .. Ranked.GetTotalMatches(),
                fontSize = 8,
                fontColor = COLORS.textMuted,
            },
            UI.Label {
                text = "胜率: " .. math.floor(Ranked.GetWinRate() * 100) .. "%",
                fontSize = 8,
                fontColor = COLORS.textMuted,
            },
        },
    }

    -- 收集卡片行的 children
    local cardRowChildren = { battleCard, rankedCard, spectateCard }

    -- 收集底部区域 children
    local bottomChildren = { progressBar, statsRow }
    if reliefPanel then
        bottomChildren[#bottomChildren + 1] = reliefPanel
    end
    bottomChildren[#bottomChildren + 1] = UI.Panel {
        marginTop = 16,
        alignItems = "center",
        children = { makerBtn },
    }

    -- === 背景装饰层 ===
    -- 顶部渐变光晕（从蓝紫向下淡出）
    local bgGlowTop = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0,
        height = "45%",
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom",
            from = { 25, 20, 60, 180 },
            to = { 15, 15, 35, 0 },
        },
    }

    -- 底部渐变（从深红/暖色向上淡出）
    local bgGlowBottom = UI.Panel {
        position = "absolute",
        bottom = 0, left = 0, right = 0,
        height = "35%",
        backgroundGradient = {
            type = "linear",
            direction = "to-top",
            from = { 40, 15, 25, 120 },
            to = { 15, 15, 35, 0 },
        },
    }

    -- 中心径向光晕（聚焦中心亮区）
    local bgRadialCenter = UI.Panel {
        position = "absolute",
        top = "15%", left = "20%", right = "20%",
        height = "50%",
        backgroundGradient = {
            type = "radial",
            from = { 45, 40, 90, 60 },
            to = { 15, 15, 35, 0 },
        },
    }

    -- 左上装饰光斑
    local decorSpotTL = UI.Panel {
        position = "absolute",
        top = 30, left = 20,
        width = 120, height = 120,
        borderRadius = 60,
        backgroundGradient = {
            type = "radial",
            from = { 108, 92, 231, 35 },
            to = { 108, 92, 231, 0 },
        },
    }

    -- 右下装饰光斑
    local decorSpotBR = UI.Panel {
        position = "absolute",
        bottom = 60, right = 30,
        width = 160, height = 160,
        borderRadius = 80,
        backgroundGradient = {
            type = "radial",
            from = { 33, 189, 174, 30 },
            to = { 33, 189, 174, 0 },
        },
    }

    -- 右上小光斑
    local decorSpotTR = UI.Panel {
        position = "absolute",
        top = 80, right = 60,
        width = 80, height = 80,
        borderRadius = 40,
        backgroundGradient = {
            type = "radial",
            from = { 255, 217, 61, 20 },
            to = { 255, 217, 61, 0 },
        },
    }

    -- GM 调试按钮（直接作为 absolute 子元素）
    local GMPanel = require("ui.GMPanel")
    local gmBtn = UI.Button {
        text = "GM",
        variant = "secondary",
        size = "sm",
        position = "absolute",
        top = 50,
        right = 8,
        visible = GMPanel.IsGMUser(),
        onClick = function()
            GMPanel.Toggle()
        end,
    }

    -- 组装根布局
    root_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = COLORS.background,
        children = {
            -- 装饰层（absolute，不影响布局）
            bgGlowTop,
            bgGlowBottom,
            bgRadialCenter,
            decorSpotTL,
            decorSpotBR,
            decorSpotTR,
            -- 内容层
            topBar,
            UI.Panel {
                flexGrow = 1,
                width = "100%",
                alignItems = "center",
                justifyContent = "center",
                paddingBottom = 20,
                children = {
                    title,
                    -- LLM AI 开关
                    llmToggle,
                    -- 卡片行（3 张卡片）
                    UI.Panel {
                        flexDirection = "row",
                        gap = 16,
                        children = cardRowChildren,
                    },
                    -- 段位进度 + 统计 + 救济金 + 角色工坊
                    UI.Panel {
                        marginTop = 16,
                        alignItems = "center",
                        children = bottomChildren,
                    },
                },
            },
            -- GM 按钮（放最后确保在最顶层可点击）
            gmBtn,
        },
    }

    UI.SetRoot(root_)

    -- === 入场动画 ===
    Anim.SlideInFromTop(topBar, { duration = 0.4, distance = 44, ease = "cubicout" })
    Anim.FadeIn(title, { duration = 0.5, delay = 0.15 })
    Anim.Stagger({ battleCard, rankedCard, spectateCard }, Anim.PopIn, {
        stagger = 0.08,
        baseDelay = 0.2,
    })
end

--- 创建模式选择卡片
---@param opts {title:string, desc:string, cost:string, reward:string, btnText:string, btnColor:table, onClick:function}
---@return Widget
function M.CreateModeCard(opts)
    -- 卡片微渐变：从按钮色调的极淡版本开始
    local cardGradientFrom = {
        math.min(255, opts.btnColor[1] + 5),
        math.min(255, opts.btnColor[2] + 5),
        math.min(255, opts.btnColor[3] + 5),
        18
    }
    return UI.Panel {
        width = 220,
        paddingTop = 20,
        paddingBottom = 20,
        paddingLeft = 16,
        paddingRight = 16,
        backgroundColor = COLORS.surface,
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom",
            from = cardGradientFrom,
            to = { 27, 27, 58, 255 },
        },
        borderWidth = 1,
        borderColor = { opts.btnColor[1], opts.btnColor[2], opts.btnColor[3], 60 },
        borderRadius = 8,
        alignItems = "center",
        boxShadow = {
            { x = 0, y = 4, blur = 12, color = { opts.btnColor[1], opts.btnColor[2], opts.btnColor[3], 25 } },
            { x = 0, y = 1, blur = 0, color = { 255, 255, 255, 8 } },
        },
        children = {
            -- 标题
            UI.Label {
                text = opts.title,
                fontSize = 15,
                fontWeight = "bold",
                fontColor = COLORS.text,
                marginBottom = 8,
            },
            -- 描述
            UI.Label {
                text = opts.desc,
                fontSize = 9,
                fontColor = COLORS.textMuted,
                textAlign = "center",
                marginBottom = 14,
            },
            -- 费用行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                marginBottom = 4,
                children = {
                    UI.Label { text = opts.cost, fontSize = 9, fontColor = COLORS.gold },
                },
            },
            -- 奖励行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                marginBottom = 16,
                children = {
                    UI.Label { text = opts.reward, fontSize = 9, fontColor = {80, 200, 120, 255} },
                },
            },
            -- 按钮
            UI.Button {
                text = opts.btnText,
                width = "100%",
                height = 36,
                backgroundColor = opts.btnColor,
                boxShadow = PIXEL_SHADOW,
                onClick = function() opts.onClick() end,
            },
        },
    }
end

return M
