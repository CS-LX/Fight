-- ============================================================================
-- GMPanel.lua - GM 调试面板（仅限指定 TapTap 用户）
-- ============================================================================
local UI = require("urhox-libs/UI")
local Economy = require("economy.Economy")

local M = {}

local isOpen_ = false
---@type Widget|nil
local root_ = nil

--- GM 白名单（允许使用 GM 的 TapTap 用户 ID）
local GM_WHITELIST = {
    ["570079718"] = true,
    ["771520039"] = true,
}

--- 获取当前用户 ID
---@return string|nil
local function getCurrentUserId()
    if clientCloud and clientCloud.userId and clientCloud.userId ~= 0 then
        return tostring(clientCloud.userId)
    end
    return nil
end

--- 检查当前用户是否有 GM 权限
---@return boolean
function M.IsGMUser()
    local uid = getCurrentUserId()
    if uid then
        return GM_WHITELIST[uid] == true
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

    -- 获取 Lobby 根节点
    local Lobby = require("ui.Lobby")
    local lobbyRoot = Lobby.GetRoot()
    if not lobbyRoot then
        print("[GM] Cannot open: Lobby root not available")
        return
    end

    isOpen_ = true

    local goldLabel
    local crystalLabel

    local function refreshLabels()
        if goldLabel then goldLabel:SetText("金币: " .. tostring(Economy.GetBalance())) end
        if crystalLabel then crystalLabel:SetText("水晶: " .. tostring(Economy.GetCrystal())) end
        -- 同步刷新大厅余额
        Lobby.RefreshBalance()
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

    -- 使用 AddChild 添加到 Lobby 根节点
    lobbyRoot:AddChild(root_)
    print("[GM] Panel opened via AddChild")
end

function M.Close()
    if not isOpen_ then return end
    isOpen_ = false

    if root_ then
        local Lobby = require("ui.Lobby")
        local lobbyRoot = Lobby.GetRoot()
        if lobbyRoot then
            lobbyRoot:RemoveChild(root_)
        end
        root_ = nil
    end
    print("[GM] Panel closed")
end

function M.IsOpen()
    return isOpen_
end

return M
