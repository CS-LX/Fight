-- ============================================================================
-- network/Server.lua - 服务端 LLM 代理
-- ============================================================================
-- 职责：接收客户端的部署请求，调用 LLM API，返回部署决策
-- 服务端 headless 无渲染，仅做 HTTP 中继

local Shared = require("network.Shared")

local M = {}

-- ⚠️ 这些值必须由用户配置，禁止硬编码到版本控制
-- 实际运行时从环境变量或配置文件读取
local LLM_API_URL = ""    -- 用户提供
local LLM_API_KEY = ""    -- 用户提供
local LLM_MODEL   = ""    -- 用户提供

--- 系统提示词：告诉 LLM 它是竞技场部署 AI
local SYSTEM_PROMPT = [[
你是一个竞技场对战游戏的AI指挥官。你需要根据当前可用的角色和预算来决定部署方案。

游戏规则：
- 竞技场大小为 20m(宽) x 14m(深)
- 你的部署区域为右半场 (X: 1~9, Z: -6~6)
- 每个角色有不同的属性：HP(血量), ATK(攻击力), SPD(速度), Range(攻击范围)
- 高HP的角色适合放前排抗伤害
- 高Range的角色适合放后排输出
- 高SPD的角色适合放侧翼包抄

你需要返回一个 JSON 数组，格式为：
[{"id": "角色ID", "x": 部署X坐标, "z": 部署Z坐标}, ...]

注意：
- X坐标范围 1~9 (越小越靠近中线/前排)
- Z坐标范围 -6~6
- 合理分配前后排：坦克在前(x=2~3)，输出在后(x=6~8)
- 只返回 JSON 数组，不要加其他文字
]]

--- 从远程事件读取 LLM 配置（首次连接时客户端可能会发送）
local function LoadConfig()
    -- 尝试从文件加载配置（服务端可以读写文件）
    local configFile = File:new("llm_config.json", FILE_READ)
    if configFile and configFile:IsOpen() then
        local content = configFile:ReadString()
        configFile:Close()
        configFile:Dispose()
        local ok, cfg = pcall(cjson.decode, content)
        if ok and cfg then
            LLM_API_URL = cfg.api_url or ""
            LLM_API_KEY = cfg.api_key or ""
            LLM_MODEL   = cfg.model or ""
            print("[LLM Server] Config loaded: model=" .. LLM_MODEL)
            return true
        end
    end
    print("[LLM Server] No config found, waiting for client to provide config")
    return false
end

--- 处理客户端的部署请求
local function HandleDeployRequest(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local prompt = eventData["Prompt"]:GetString()

    print("[LLM Server] Received deploy request, prompt length=" .. #prompt)

    -- 检查配置
    if LLM_API_URL == "" or LLM_API_KEY == "" then
        -- 无配置，返回错误
        local resp = VariantMap()
        resp["Success"] = Variant(false)
        resp["Error"] = Variant("LLM 未配置。请在设置中提供 API URL、Key 和模型名")
        connection:SendRemoteEvent(Shared.EVENTS.LLM_DEPLOY_RESP, true, resp)
        return
    end

    -- 构建 LLM 请求
    local messages = {
        { role = "system", content = SYSTEM_PROMPT },
        { role = "user",   content = prompt },
    }
    local requestBody = cjson.encode({
        model = LLM_MODEL,
        messages = messages,
        max_tokens = 512,
        temperature = 0.7,
    })

    -- 发送 HTTP 请求到 LLM
    http:Create()
        :SetUrl(LLM_API_URL)
        :SetMethod(HTTP_POST)
        :SetContentType("application/json")
        :AddHeader("Authorization", "Bearer " .. LLM_API_KEY)
        :SetBody(requestBody)
        :OnSuccess(function(client, response)
            local resp = VariantMap()
            if response.success then
                local ok, data = pcall(cjson.decode, response.dataAsString)
                if ok and data and data.choices and data.choices[1] then
                    local content = data.choices[1].message.content
                    resp["Success"] = Variant(true)
                    resp["Content"] = Variant(content)
                    print("[LLM Server] Got LLM response, length=" .. #content)
                else
                    resp["Success"] = Variant(false)
                    resp["Error"] = Variant("LLM 响应解析失败")
                    print("[LLM Server] Failed to parse LLM response")
                end
            else
                resp["Success"] = Variant(false)
                resp["Error"] = Variant("HTTP " .. tostring(response.statusCode))
                print("[LLM Server] HTTP error: " .. tostring(response.statusCode))
            end
            connection:SendRemoteEvent(Shared.EVENTS.LLM_DEPLOY_RESP, true, resp)
        end)
        :OnError(function(client, statusCode, error)
            local resp = VariantMap()
            resp["Success"] = Variant(false)
            resp["Error"] = Variant("网络错误: " .. tostring(error))
            connection:SendRemoteEvent(Shared.EVENTS.LLM_DEPLOY_RESP, true, resp)
            print("[LLM Server] Network error: " .. tostring(error))
        end)
        :Send()
end

--- 处理客户端就绪
local function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    print("[LLM Server] Client connected and ready")

    -- 如果客户端带了配置信息
    local apiUrl = eventData["ApiUrl"] and eventData["ApiUrl"]:GetString() or nil
    if apiUrl and apiUrl ~= "" then
        LLM_API_URL = apiUrl
        LLM_API_KEY = eventData["ApiKey"]:GetString()
        LLM_MODEL   = eventData["Model"]:GetString()
        print("[LLM Server] Config received from client: model=" .. LLM_MODEL)

        -- 持久化配置
        local cfg = cjson.encode({
            api_url = LLM_API_URL,
            api_key = LLM_API_KEY,
            model   = LLM_MODEL,
        })
        local f = File:new("llm_config.json", FILE_WRITE)
        if f and f:IsOpen() then
            f:WriteString(cfg)
            f:Close()
            f:Dispose()
        end
    end
end

function M.Start()
    print("[LLM Server] Starting LLM proxy server...")

    -- 创建服务端场景（最小化，只用于连接管理）
    local scene = Scene()
    scene.name = "LLMServerScene"

    -- 注册服务端事件
    Shared.RegisterServerEvents()

    -- 订阅事件
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, HandleClientReady)
    SubscribeToEvent(Shared.EVENTS.LLM_DEPLOY_REQ, HandleDeployRequest)

    -- 加载配置
    LoadConfig()

    print("[LLM Server] Ready, waiting for client connections...")
end

function M.Stop()
    print("[LLM Server] Shutting down")
end

return M
