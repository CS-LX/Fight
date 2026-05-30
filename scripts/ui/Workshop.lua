-- ============================================================================
-- ui/Workshop.lua - UGC 角色工坊主界面 (Phase 3)
-- ============================================================================
-- 职责：展示玩家已创建的 UGC 角色列表 + 创建新角色入口
-- 入口：大厅 "角色工坊" 按钮
-- 出口：返回大厅 / 进入 CharacterMaker 编辑器

local UI = require("urhox-libs/UI")
local Economy = require("economy.Economy")
local CharRegistry = require("characters.CharRegistry")

local M = {}

-- ============================================================================
-- PixelForge 色板
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
    crystal     = { 180, 120, 255, 255 },
    redText     = { 255, 71, 87, 255 },
    shadow      = { 10, 10, 26, 204 },
    cardBg      = { 20, 20, 48, 255 },
}

local PIXEL_SHADOW = {
    { x = 3, y = 3, blur = 0, color = { 10, 10, 26, 204 } },
}

-- ============================================================================
-- 状态
-- ============================================================================

local isOpen_ = false
---@type Widget|nil
local root_ = nil

--- 回调
---@type {onBack: function, onCreate: function, onEdit: function}|nil
local callbacks_ = nil

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 打开工坊界面
---@param opts {onBack: function, onCreate: function, onEdit: function}
---  onBack: 返回大厅
---  onCreate: 开始创建新角色（进入编辑器，新建模式）
---  onEdit: 编辑已有角色（id）→ 进入编辑器
function M.Open(opts)
    callbacks_ = opts
    isOpen_ = true
    M.BuildUI()
end

--- 关闭工坊界面
function M.Close()
    isOpen_ = false
    callbacks_ = nil
    if root_ then
        UI.SetRoot(nil)
        root_ = nil
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
    local crystalBalance = Economy.GetCrystal()
    local createCost = Economy.Config.UGC_CREATE_COST
    local canCreate = crystalBalance >= createCost

    -- 顶部导航栏
    local topBar = UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingLeft = 12,
        paddingRight = 16,
        backgroundColor = COLORS.surface,
        borderBottomWidth = 2,
        borderColor = COLORS.border,
        children = {
            -- 左侧：返回按钮
            UI.Button {
                text = "← 大厅",
                variant = "text",
                height = 32,
                fontSize = 11,
                onClick = function()
                    if callbacks_ and callbacks_.onBack then
                        local cb = callbacks_.onBack
                        M.Close()
                        cb()
                    end
                end,
            },
            -- 中间：标题
            UI.Label {
                text = "角色工坊",
                fontSize = 14,
                fontWeight = "bold",
                fontColor = COLORS.primary,
            },
            -- 右侧：创造晶余额
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "◆",
                        fontSize = 12,
                        fontColor = COLORS.crystal,
                        marginRight = 4,
                    },
                    UI.Label {
                        text = tostring(crystalBalance),
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = COLORS.crystal,
                    },
                },
            },
        },
    }

    -- 创建新角色按钮区
    local createSection = UI.Panel {
        width = "100%",
        paddingHorizontal = 16,
        paddingVertical = 12,
        alignItems = "center",
        children = {
            UI.Button {
                text = canCreate
                    and ("+ 创建新角色 (" .. createCost .. "◆)")
                    or ("◆不足 (需要" .. createCost .. ", 拥有" .. crystalBalance .. ")"),
                width = 280,
                height = 40,
                fontSize = 12,
                fontWeight = "bold",
                disabled = not canCreate,
                backgroundColor = canCreate and COLORS.secondary or COLORS.surface,
                borderWidth = 2,
                borderColor = canCreate and COLORS.crystal or COLORS.border,
                boxShadow = canCreate and PIXEL_SHADOW or nil,
                onClick = function()
                    if not canCreate then return end
                    if callbacks_ and callbacks_.onCreate then
                        local cb = callbacks_.onCreate
                        M.Close()
                        cb()
                    end
                end,
            },
            -- 创造晶获取提示
            not canCreate and UI.Label {
                text = "通过对战连胜、每日首胜获取创造晶",
                fontSize = 9,
                fontColor = COLORS.textMuted,
                marginTop = 6,
            } or nil,
        },
    }

    -- 角色列表
    local customIds = CharRegistry.GetCustomIds()
    local charCards = {}

    if #customIds == 0 then
        -- 空状态
        table.insert(charCards, UI.Panel {
            width = "100%",
            height = 120,
            alignItems = "center",
            justifyContent = "center",
            children = {
                UI.Label {
                    text = "还没有自创角色",
                    fontSize = 13,
                    fontColor = COLORS.textMuted,
                },
                UI.Label {
                    text = "创建你的第一个 UGC 角色吧！",
                    fontSize = 10,
                    fontColor = COLORS.textMuted,
                    marginTop = 4,
                },
            },
        })
    else
        for _, id in ipairs(customIds) do
            local mod = CharRegistry.Get(id)
            if mod then
                table.insert(charCards, M.CreateCharCard(mod))
            end
        end
    end

    -- 角色列表容器（可滚动）
    local charList = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        paddingHorizontal = 16,
        paddingVertical = 8,
        children = {
            UI.Panel {
                width = "100%",
                gap = 10,
                children = charCards,
            },
        },
    }

    -- 底部统计信息
    local footer = UI.Panel {
        width = "100%",
        height = 30,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = COLORS.surface,
        borderTopWidth = 1,
        borderColor = COLORS.border,
        children = {
            UI.Label {
                text = string.format("自创角色: %d | 总角色: %d", #customIds, CharRegistry.GetCount()),
                fontSize = 9,
                fontColor = COLORS.textMuted,
            },
        },
    }

    -- 组装根布局
    root_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = COLORS.background,
        children = {
            topBar,
            createSection,
            charList,
            footer,
        },
    }

    UI.SetRoot(root_)
end

--- 创建角色卡片
---@param mod CharModule
---@return Widget
function M.CreateCharCard(mod)
    local config = mod.config or {}
    local statsText = string.format("HP:%d ATK:%d SPD:%.1f RNG:%.1f",
        config.baseHP or 100,
        config.attackDamage or 10,
        config.baseSpeed or 2.5,
        config.attackRange or 1.2
    )

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = 10,
        paddingHorizontal = 12,
        backgroundColor = COLORS.cardBg,
        borderWidth = 2,
        borderColor = COLORS.border,
        boxShadow = PIXEL_SHADOW,
        children = {
            -- 左侧：角色信息
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    -- 名称行
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = mod.name or mod.id,
                                fontSize = 13,
                                fontWeight = "bold",
                                fontColor = COLORS.text,
                            },
                            UI.Label {
                                text = "  [UGC-B]",
                                fontSize = 9,
                                fontColor = COLORS.crystal,
                            },
                        },
                    },
                    -- 属性行
                    UI.Label {
                        text = statsText,
                        fontSize = 9,
                        fontColor = COLORS.textMuted,
                        marginTop = 2,
                    },
                    -- AI 行为
                    UI.Label {
                        text = "AI: " .. (mod.ai and mod.ai.profile or "balanced"),
                        fontSize = 8,
                        fontColor = COLORS.textMuted,
                        marginTop = 1,
                    },
                },
            },
            -- 右侧：编辑按钮
            UI.Button {
                text = "编辑",
                width = 56,
                height = 28,
                fontSize = 10,
                variant = "outline",
                onClick = function()
                    if callbacks_ and callbacks_.onEdit then
                        local cb = callbacks_.onEdit
                        M.Close()
                        cb(mod.id)
                    end
                end,
            },
        },
    }
end

return M
