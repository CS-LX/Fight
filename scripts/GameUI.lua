-- ============================================================================
-- GameUI.lua - 游戏 HUD（计分、状态、按钮）
-- ============================================================================
-- 职责：纯 UI 层，不处理角色渲染（角色渲染由 CharRender 负责）

local UI = require("urhox-libs/UI")
local Config = require("Config")
local CharRender = require("render.CharRender")
local CharCustomUI = require("CharCustomUI")
local CharRegistry = require("characters.CharRegistry")
local BehaviourTreeEditor = require("ui.BehaviourTreeEditor")

local M = {}

-- 外部回调：当保存自定义角色后使用该角色重开游戏
---@type function|nil
local onUseCustomChar_ = nil

-- UI 引用
---@type Widget|nil
local statusLabel_ = nil
---@type Widget|nil
local redCountLabel_ = nil
---@type Widget|nil
local blueCountLabel_ = nil

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

--- 创建完整游戏 HUD（含角色 Spine 层 + 自定义面板）
---@param characters table[] 逻辑数据列表
---@param onReset function 重置回调
function M.CreateHUD(characters, onReset)
    -- 角色 Spine 容器（由 CharRender 管理）
    local spineLayer = CharRender.CreateSpines(characters)

    -- 红队计数
    redCountLabel_ = UI.Label {
        text = "Red: " .. Config.TeamSize,
        fontSize = 18,
        fontColor = { 255, 80, 80, 255 },
        position = "absolute",
        top = 12,
        left = 16,
    }

    -- 蓝队计数
    blueCountLabel_ = UI.Label {
        text = "Blue: " .. Config.TeamSize,
        fontSize = 18,
        fontColor = { 80, 120, 255, 255 },
        position = "absolute",
        top = 12,
        right = 16,
    }

    -- 中间状态
    statusLabel_ = UI.Label {
        text = "FIGHT!",
        fontSize = 28,
        fontColor = { 255, 255, 100, 255 },
        position = "absolute",
        top = 10,
        left = 0,
        right = 0,
        textAlign = "center",
    }

    -- 重新开始按钮
    local resetBtn = UI.Button {
        text = "Restart",
        width = 100,
        height = 36,
        position = "absolute",
        bottom = 20,
        right = 16,
        onClick = function(self)
            if onReset then onReset() end
        end,
    }

    -- 自定义角色按钮
    local customBtn = UI.Button {
        text = "Custom",
        width = 100,
        height = 36,
        position = "absolute",
        bottom = 20,
        right = 126,
        onClick = function(self)
            if CharCustomUI.IsVisible() then
                CharCustomUI.Hide()
            else
                CharCustomUI.ShowNew()
            end
        end,
    }

    -- 行为树编辑器按钮
    local btEditBtn = UI.Button {
        text = "BT Edit",
        width = 100,
        height = 36,
        position = "absolute",
        bottom = 20,
        right = 236,
        onClick = function(self)
            M.OpenBTEditor()
        end,
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            spineLayer,
            redCountLabel_,
            blueCountLabel_,
            statusLabel_,
            resetBtn,
            customBtn,
            btEditBtn,
        }
    }

    UI.SetRoot(root)

    -- 创建自定义角色面板（挂载到根容器，初始隐藏）
    CharCustomUI.Create(root, function(mod)
        -- 保存后：使用该自定义角色重新开始
        if onUseCustomChar_ then
            onUseCustomChar_(mod.id)
        end
    end, nil)
end

--- 设置"使用自定义角色"的回调
---@param fn function(moduleId: string)
function M.SetOnUseCustomChar(fn)
    onUseCustomChar_ = fn
end

--- 更新队伍存活计数
---@param redAlive number
---@param blueAlive number
function M.UpdateCounts(redAlive, blueAlive)
    if redCountLabel_ then
        redCountLabel_:SetText("Red: " .. redAlive)
    end
    if blueCountLabel_ then
        blueCountLabel_:SetText("Blue: " .. blueAlive)
    end
end

--- 显示胜利信息
---@param message string
function M.ShowResult(message)
    if statusLabel_ then
        statusLabel_:SetText(message)
    end
end

--- 重置状态文字
function M.ResetStatus()
    if statusLabel_ then
        statusLabel_:SetText("FIGHT!")
    end
end

-- ============================================================================
-- 行为树编辑器集成
-- ============================================================================

--- 缓存的行为树数据（编辑器关闭后保留）
local btEditorData_ = nil

--- 重建游戏 HUD 的回调引用
local cachedCharacters_ = nil
local cachedOnReset_ = nil

--- 打开行为树编辑器
function M.OpenBTEditor()
    BehaviourTreeEditor.Open({
        initialData = btEditorData_,
        onSave = function(data)
            btEditorData_ = data
            print("[GameUI] BT data saved (" .. (data and #(data.edges or {}) or 0) .. " edges)")
        end,
        onClose = function()
            -- 恢复游戏 HUD
            if cachedCharacters_ and cachedOnReset_ then
                M.CreateHUD(cachedCharacters_, cachedOnReset_)
            end
        end,
    })
end

--- 缓存角色和重置回调（供编辑器关闭时恢复HUD用）
local _originalCreateHUD = M.CreateHUD
function M.CreateHUD(characters, onReset)
    cachedCharacters_ = characters
    cachedOnReset_ = onReset
    _originalCreateHUD(characters, onReset)
end

return M
