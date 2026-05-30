-- ============================================================================
-- network/Shared.lua - 共享事件名定义
-- ============================================================================
-- 客户端和服务端共用的常量与事件注册

local M = {}

-- 远程事件名
M.EVENTS = {
    CLIENT_READY      = "ClientReady",
    -- LLM 部署请求/响应
    LLM_DEPLOY_REQ    = "LLMDeployReq",     -- Client → Server
    LLM_DEPLOY_RESP   = "LLMDeployResp",    -- Server → Client
}

-- 服务端需要接收的事件（客户端发送）
M.SERVER_EVENTS = {
    M.EVENTS.CLIENT_READY,
    M.EVENTS.LLM_DEPLOY_REQ,
}

-- 客户端需要接收的事件（服务端发送）
M.CLIENT_EVENTS = {
    M.EVENTS.LLM_DEPLOY_RESP,
}

--- 注册服务端事件
function M.RegisterServerEvents()
    for _, eventName in ipairs(M.SERVER_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

--- 注册客户端事件
function M.RegisterClientEvents()
    for _, eventName in ipairs(M.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

return M
