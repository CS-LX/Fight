-- ============================================================================
-- network/Client.lua - 客户端 LLM 通信模块
-- ============================================================================
-- 职责：当 LLM toggle 开启时，将部署请求发送给服务端，接收 LLM 决策结果
-- 客户端无法直接发 HTTP，必须通过服务端中继

local Shared = require("network.Shared")

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

--- LLM 是否启用（由 Lobby toggle 控制）
local llmEnabled_ = false

--- 是否已连接服务端
local connected_ = false

--- 当前请求的回调（一次只有一个在途请求）
---@type function|nil
local pendingCallback_ = nil

--- LLM 配置（用户可在设置中修改）
local llmConfig_ = {
    api_url = "",
    api_key = "",
    model   = "",
}

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化客户端网络（在游戏 Start 时调用）
function M.Init()
    -- 注册客户端事件
    Shared.RegisterClientEvents()

    -- 订阅服务端响应
    SubscribeToEvent(Shared.EVENTS.LLM_DEPLOY_RESP, M.HandleDeployResponse)

    -- 订阅连接成功事件
    SubscribeToEvent("ServerConnected", function()
        connected_ = true
        print("[LLM Client] Connected to server")
        -- 发送 ClientReady + 配置
        M.SendClientReady()
    end)

    SubscribeToEvent("ServerDisconnected", function()
        connected_ = false
        print("[LLM Client] Disconnected from server")
    end)

    -- 尝试加载本地 LLM 配置
    M.LoadLocalConfig()

    print("[LLM Client] Initialized")
end

--- 设置 LLM 开关
---@param enabled boolean
function M.SetEnabled(enabled)
    llmEnabled_ = enabled
    print("[LLM Client] LLM AI " .. (enabled and "ENABLED" or "DISABLED"))
end

--- 获取 LLM 开关状态
---@return boolean
function M.IsEnabled()
    return llmEnabled_
end

--- 是否已连接服务端（LLM 可用的前提）
---@return boolean
function M.IsConnected()
    return connected_
end

--- 设置 LLM 配置
---@param config {api_url: string, api_key: string, model: string}
function M.SetConfig(config)
    llmConfig_.api_url = config.api_url or ""
    llmConfig_.api_key = config.api_key or ""
    llmConfig_.model   = config.model or ""
    M.SaveLocalConfig()
    -- 如果已连接，立即发送配置到服务端
    if connected_ then
        M.SendClientReady()
    end
end

--- 获取当前配置
---@return table
function M.GetConfig()
    return llmConfig_
end

--- 请求 LLM 部署决策
---@param gameState table 当前游戏状态（角色列表、金币等）
---@param callback function(success: boolean, result: table|string) 回调
function M.RequestDeploy(gameState, callback)
    if not llmEnabled_ then
        callback(false, "LLM 未启用")
        return
    end

    if not connected_ then
        callback(false, "未连接服务端，请检查网络")
        return
    end

    if pendingCallback_ then
        callback(false, "上一个请求仍在处理中")
        return
    end

    pendingCallback_ = callback

    -- 构建 prompt：告诉 LLM 当前游戏状态
    local prompt = M.BuildPrompt(gameState)

    -- 发送 RemoteEvent 到服务端
    local data = VariantMap()
    data["Prompt"] = Variant(prompt)

    local serverConnection = network:GetServerConnection()
    if serverConnection then
        serverConnection:SendRemoteEvent(Shared.EVENTS.LLM_DEPLOY_REQ, true, data)
        print("[LLM Client] Deploy request sent, prompt length=" .. #prompt)
    else
        pendingCallback_ = nil
        callback(false, "无法获取服务端连接")
    end
end

--- 是否有请求正在进行
---@return boolean
function M.IsPending()
    return pendingCallback_ ~= nil
end

-- ============================================================================
-- 内部方法
-- ============================================================================

--- 构建发给 LLM 的 prompt
---@param gameState table
---@return string
function M.BuildPrompt(gameState)
    local lines = {}
    table.insert(lines, "当前游戏状态：")
    table.insert(lines, string.format("- 可用金币: %d G", gameState.gold or 0))
    table.insert(lines, string.format("- 部署费用: %d G/角色", gameState.costPerUnit or 10))
    table.insert(lines, string.format("- 队伍: %s", gameState.team or "blue"))
    table.insert(lines, "")
    table.insert(lines, "可选角色列表：")

    if gameState.availableChars then
        for _, char in ipairs(gameState.availableChars) do
            table.insert(lines, string.format(
                "  - ID: %s | HP: %d | ATK: %d | SPD: %.1f | Range: %.1f | 费用: %dG | 技能: %s",
                char.id,
                char.hp or 100,
                char.atk or 10,
                char.spd or 1.0,
                char.range or 1.0,
                char.cost or 10,
                char.skill or "无"
            ))
        end
    end

    table.insert(lines, "")
    table.insert(lines, string.format("请选择 %d~%d 个角色部署（总费用不超过 %d G），并给出部署坐标。",
        gameState.minUnits or 2,
        gameState.maxUnits or 5,
        gameState.gold or 100
    ))

    return table.concat(lines, "\n")
end

--- 处理服务端返回的 LLM 响应
function M.HandleDeployResponse(eventType, eventData)
    local callback = pendingCallback_
    pendingCallback_ = nil

    if not callback then
        print("[LLM Client] Received response but no pending callback")
        return
    end

    local success = eventData["Success"]:GetBool()

    if success then
        local content = eventData["Content"]:GetString()
        print("[LLM Client] Got LLM response, length=" .. #content)

        -- 解析 JSON 数组
        local ok, deployPlan = pcall(cjson.decode, content)
        if ok and type(deployPlan) == "table" then
            callback(true, deployPlan)
        else
            -- LLM 可能返回了带有说明文字的 JSON，尝试提取
            local jsonStr = content:match("%[.-%]")
            if jsonStr then
                local ok2, plan2 = pcall(cjson.decode, jsonStr)
                if ok2 then
                    callback(true, plan2)
                    return
                end
            end
            callback(false, "LLM 返回格式无法解析: " .. content:sub(1, 200))
        end
    else
        local errMsg = eventData["Error"]:GetString()
        print("[LLM Client] Error: " .. errMsg)
        callback(false, errMsg)
    end
end

--- 发送 ClientReady（携带配置）
function M.SendClientReady()
    local serverConnection = network:GetServerConnection()
    if not serverConnection then return end

    local data = VariantMap()
    if llmConfig_.api_url ~= "" then
        data["ApiUrl"] = Variant(llmConfig_.api_url)
        data["ApiKey"] = Variant(llmConfig_.api_key)
        data["Model"]  = Variant(llmConfig_.model)
    end
    serverConnection:SendRemoteEvent(Shared.EVENTS.CLIENT_READY, true, data)
end

--- 加载本地 LLM 配置
function M.LoadLocalConfig()
    local f = File:new("llm_client_config.json", FILE_READ)
    if f and f:IsOpen() then
        local content = f:ReadString()
        f:Close()
        f:Dispose()
        local ok, cfg = pcall(cjson.decode, content)
        if ok and cfg then
            llmConfig_.api_url = cfg.api_url or ""
            llmConfig_.api_key = cfg.api_key or ""
            llmConfig_.model   = cfg.model or ""
            print("[LLM Client] Local config loaded: model=" .. llmConfig_.model)
        end
    end
end

--- 保存本地 LLM 配置
function M.SaveLocalConfig()
    local content = cjson.encode(llmConfig_)
    local f = File:new("llm_client_config.json", FILE_WRITE)
    if f and f:IsOpen() then
        f:WriteString(content)
        f:Close()
        f:Dispose()
        print("[LLM Client] Config saved locally")
    end
end

return M
