-- ============================================================================
-- GMPanel.lua - GM 调试面板（同时按住 1+2+3 打开）
-- ============================================================================
local UI = require("urhox-libs/UI")
local Economy = require("economy.Economy")

local M = {}

local isOpen_ = false
local root_ = nil

--- 连续快速按 5 次 G 键触发（500ms 内完成）
local tapCount_ = 0
local tapTimer_ = 0
local TAP_THRESHOLD = 5      -- 需要连按次数
local TAP_WINDOW = 1.5       -- 时间窗口（秒）

---@param dt number 帧间隔
---@return boolean
function M.CheckHotkey(dt)
    -- 计时器递减
    if tapTimer_ > 0 then
        tapTimer_ = tapTimer_ - dt
        if tapTimer_ <= 0 then
            tapCount_ = 0  -- 超时重置
        end
    end

    -- 检测 G 键按下（GetKeyPress = 仅按下瞬间为 true）
    if input:GetKeyPress(KEY_G) then
        tapCount_ = tapCount_ + 1
        tapTimer_ = TAP_WINDOW  -- 重置窗口
        if tapCount_ >= TAP_THRESHOLD then
            tapCount_ = 0
            tapTimer_ = 0
            return true
        end
    end

    return false
end

--- 切换 GM 面板
function M.Toggle()
    if isOpen_ then
        M.Close()
    else
        M.Open()
    end
end

function M.Open()
    if isOpen_ then return end
    isOpen_ = true

    local goldLabel
    local crystalLabel

    local function refreshLabels()
        if goldLabel then goldLabel:SetText("金币: " .. tostring(Economy.GetBalance())) end
        if crystalLabel then crystalLabel:SetText("水晶: " .. tostring(Economy.GetCrystal())) end
    end

    local function makeRow(label, getValue, setFn)
        local valLabel = UI.Label { text = label .. ": " .. tostring(getValue()), fontSize = 14, fontColor = {240,240,240,255} }

        local btnRow = UI.Panel {
            flexDirection = "row",
            gap = 6,
            children = {
                UI.Button { text = "-1000", variant = "secondary", size = "sm", onClick = function() setFn(-1000); refreshLabels() end },
                UI.Button { text = "-100", variant = "secondary", size = "sm", onClick = function() setFn(-100); refreshLabels() end },
                UI.Button { text = "+100", variant = "primary", size = "sm", onClick = function() setFn(100); refreshLabels() end },
                UI.Button { text = "+1000", variant = "primary", size = "sm", onClick = function() setFn(1000); refreshLabels() end },
                UI.Button { text = "+9999", variant = "primary", size = "sm", onClick = function() setFn(9999); refreshLabels() end },
            },
        }

        return valLabel, UI.Panel {
            gap = 4,
            children = { valLabel, btnRow },
        }
    end

    local goldLbl, goldRow = makeRow("金币", Economy.GetBalance, function(delta)
        if delta > 0 then
            Economy.Earn(delta, "GM调试")
        else
            local cur = Economy.GetBalance()
            local spend = math.min(cur, math.abs(delta))
            if spend > 0 then Economy.Spend(spend, "GM调试") end
        end
    end)
    goldLabel = goldLbl

    local crystalLbl, crystalRow = makeRow("水晶", Economy.GetCrystal, function(delta)
        if delta > 0 then
            Economy.EarnCrystal(delta, "GM调试")
        else
            local cur = Economy.GetCrystal()
            local spend = math.min(cur, math.abs(delta))
            if spend > 0 then Economy.SpendCrystal(spend, "GM调试") end
        end
    end)
    crystalLabel = crystalLbl

    root_ = UI.Panel {
        position = "absolute",
        top = 60, left = 12,
        width = 320,
        padding = 12,
        gap = 10,
        backgroundColor = { 20, 20, 20, 230 },
        borderWidth = 1,
        borderColor = { 255, 200, 0, 200 },
        borderRadius = 6,
        children = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label { text = "GM Panel", fontSize = 16, fontColor = {255, 200, 0, 255}, fontWeight = "bold" },
                    UI.Button { text = "X", size = "sm", variant = "secondary", onClick = function() M.Close() end },
                },
            },
            goldRow,
            crystalRow,
        },
    }

    UI.PushOverlay(root_)
    print("[GM] Panel opened")
end

function M.Close()
    if not isOpen_ then return end
    isOpen_ = false
    UI.PopOverlay(root_)
    root_ = nil
    print("[GM] Panel closed")
end

function M.IsOpen()
    return isOpen_
end

return M
