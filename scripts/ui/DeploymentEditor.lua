-- ============================================================================
-- ui/DeploymentEditor.lua - TABS 部署编辑器（3D场景直接放置版）
-- ============================================================================
-- 全面战争模拟器风格：
--   左右两侧角色卡面板（UI.Spine 头像预览）
--   中间透明露出 3D 竞技场，点击场地直接放置角色
--   角色部署后可见（idle），开战后才行动

local UI = require("urhox-libs/UI")
local CharRegistry = require("characters.CharRegistry")

local M = {}

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

--- 获取当前选中的角色卡
---@return table|nil { moduleId: string, team: string }
function M.GetSelectedCard()
    return selectedCard_
end

--- 更新计数显示
---@param redCount number
---@param blueCount number
function M.UpdateCounts(redCount, blueCount)
    if redCountLabel_ then
        redCountLabel_:SetText("红方: " .. redCount)
    end
    if blueCountLabel_ then
        blueCountLabel_:SetText("蓝方: " .. blueCount)
    end
end

--- 更新提示文字
---@param text string
function M.SetHint(text)
    if hintLabel_ then
        hintLabel_:SetText(text)
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

--- 创建角色卡牌（含 Spine 头像）
---@param team string "red" | "blue"
---@return Widget 卡牌面板
local function CreateCardPanel(team)
    local allIds = CharRegistry.GetAllIds()
    local cards = {}
    local cardRefs = {}

    for _, id in ipairs(allIds) do
        local mod = CharRegistry.Get(id)
        local name = mod and mod.name or id
        local spineSrc = mod and mod.art and mod.art.spineSrc or nil
        local pma = mod and mod.art and mod.art.pma or true
        local idleAnim = mod and mod.art and mod.art.anims and mod.art.anims.idle or "Default"

        -- 角色卡片：Spine 头像 + 名字
        local cardChildren = {}

        -- Spine 缩略图
        if spineSrc then
            table.insert(cardChildren, UI.Spine {
                src = spineSrc,
                animation = idleAnim,
                loop = true,
                width = 56,
                height = 64,
                objectFit = "contain",
                pma = pma,
            })
        end

        -- 角色名
        table.insert(cardChildren, UI.Label {
            text = name,
            fontSize = 11,
            fontColor = { 220, 220, 220, 255 },
            textAlign = "center",
            marginTop = 2,
        })

        local cardBg = (team == "red")
            and { 80, 30, 30, 180 }
            or { 30, 30, 80, 180 }
        local cardBgSelected = (team == "red")
            and { 200, 60, 60, 240 }
            or { 60, 80, 200, 240 }

        local capturedId = id
        local card = UI.Panel {
            width = 72,
            height = 96,
            padding = 4,
            marginBottom = 8,
            alignItems = "center",
            justifyContent = "center",
            bgColor = cardBg,
            borderRadius = 8,
            cursor = "pointer",
            onClick = function(self)
                selectedCard_ = { moduleId = capturedId, team = team }
                -- 更新本队选中态
                local refs = (team == "red") and redCardRefs_ or blueCardRefs_
                for _, c in ipairs(refs) do
                    local defaultBg = (team == "red")
                        and { 80, 30, 30, 180 }
                        or { 30, 30, 80, 180 }
                    c:SetStyle({ bgColor = defaultBg })
                end
                self:SetStyle({ bgColor = cardBgSelected })
                -- 同时清除另一队的选中
                local otherRefs = (team == "red") and blueCardRefs_ or redCardRefs_
                for _, c in ipairs(otherRefs) do
                    local otherBg = (team ~= "red")
                        and { 80, 30, 30, 180 }
                        or { 30, 30, 80, 180 }
                    c:SetStyle({ bgColor = otherBg })
                end
                M.SetHint("点击" .. (team == "red" and "左半场" or "右半场") .. "放置角色")
            end,
            children = cardChildren,
        }

        table.insert(cards, card)
        table.insert(cardRefs, card)
    end

    -- 保存引用
    if team == "red" then
        redCardRefs_ = cardRefs
    else
        blueCardRefs_ = cardRefs
    end

    local teamLabel = (team == "red") and "红  方" or "蓝  方"
    local teamColor = (team == "red") and { 255, 100, 100, 255 } or { 100, 150, 255, 255 }

    return UI.Panel {
        width = 88,
        padding = 8,
        paddingTop = 12,
        bgColor = { 15, 15, 25, 210 },
        borderRadius = 8,
        alignItems = "center",
        overflow = "scroll",
        children = {
            UI.Label {
                text = teamLabel,
                fontSize = 14,
                fontColor = teamColor,
                marginBottom = 10,
                textAlign = "center",
            },
            table.unpack(cards),
        }
    }
end

--- 打开部署编辑器
---@param opts { onStartBattle: function, onClear: function, spineLayer: Widget|nil }
function M.Open(opts)
    opts = opts or {}
    onStartBattle_ = opts.onStartBattle
    onClear_ = opts.onClear
    local spineLayer = opts.spineLayer  -- 底层 spine 角色容器（可选）

    selectedCard_ = nil
    redCardRefs_ = {}
    blueCardRefs_ = {}
    isOpen_ = true

    -- 左侧红方卡牌面板
    local redPanel = CreateCardPanel("red")

    -- 右侧蓝方卡牌面板
    local bluePanel = CreateCardPanel("blue")

    -- 计数标签
    redCountLabel_ = UI.Label {
        text = "红方: 0",
        fontSize = 14,
        fontColor = { 255, 120, 120, 255 },
    }
    blueCountLabel_ = UI.Label {
        text = "蓝方: 0",
        fontSize = 14,
        fontColor = { 120, 150, 255, 255 },
        marginLeft = 16,
    }

    -- 提示文字
    hintLabel_ = UI.Label {
        text = "选择角色卡，然后点击场地放置",
        fontSize = 13,
        fontColor = { 200, 200, 180, 180 },
        marginLeft = 20,
    }

    -- 开战按钮
    startBtn_ = UI.Button {
        text = "开  战 !",
        width = 120,
        height = 42,
        fontSize = 18,
        variant = "primary",
        borderRadius = 8,
        marginLeft = 20,
        onClick = function(self)
            if onStartBattle_ then
                onStartBattle_()
            end
        end,
    }

    -- 清空按钮
    local clearBtn = UI.Button {
        text = "清空",
        width = 64,
        height = 32,
        fontSize = 12,
        variant = "outline",
        marginLeft = 12,
        onClick = function(self)
            if onClear_ then onClear_() end
        end,
    }

    -- 底部工具栏
    local footer = UI.Panel {
        width = "100%",
        height = 56,
        position = "absolute",
        bottom = 0,
        left = 0,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        bgColor = { 10, 10, 20, 200 },
        children = {
            redCountLabel_,
            blueCountLabel_,
            hintLabel_,
            startBtn_,
            clearBtn,
        }
    }

    -- 顶部标题
    local header = UI.Panel {
        width = "100%",
        height = 36,
        position = "absolute",
        top = 0,
        left = 0,
        justifyContent = "center",
        alignItems = "center",
        bgColor = { 10, 10, 20, 180 },
        children = {
            UI.Label {
                text = "- 部署阶段 -  布置你的军队",
                fontSize = 16,
                fontColor = { 255, 220, 100, 255 },
            },
        }
    }

    -- 根布局：spine 层(底) + 左右卡牌面板 + 中间透明（点击穿透到3D场景）
    local rootChildren = {}

    -- spine 角色层在最底部
    if spineLayer then
        table.insert(rootChildren, spineLayer)
    end

    -- 左侧红方面板
    table.insert(rootChildren, UI.Panel {
        position = "absolute",
        left = 8,
        top = 44,
        bottom = 64,
        children = { redPanel },
    })
    -- 右侧蓝方面板
    table.insert(rootChildren, UI.Panel {
        position = "absolute",
        right = 8,
        top = 44,
        bottom = 64,
        children = { bluePanel },
    })
    table.insert(rootChildren, header)
    table.insert(rootChildren, footer)

    rootWidget_ = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",  -- 中间区域点击穿透
        children = rootChildren,
    }

    UI.SetRoot(rootWidget_)
    print("[DeploymentEditor] Opened - TABS style, click arena to place")
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
