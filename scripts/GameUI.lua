-- ============================================================================
-- GameUI.lua - 游戏 HUD（计分、状态、按钮）
-- ============================================================================
-- 职责：纯 UI 层，不处理角色渲染（角色渲染由 CharRender 负责）

local UI = require("urhox-libs/UI")
local Config = require("Config")
local CharRender = require("render.CharRender")

local M = {}

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

--- 创建完整游戏 HUD（含角色 Spine 层）
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
        }
    }

    UI.SetRoot(root)
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

return M
