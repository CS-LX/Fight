-- ============================================================================
-- characters/CharRegistry.lua - 角色注册表（管理所有角色模块）
-- ============================================================================
-- 职责：从 JSON 加载预设角色、注册自定义角色、按ID查询角色模块
-- 支持：JSON 预设 + 用户自定义持久化角色

local CharModule = require("characters.CharModule")
local CharPersist = require("characters.CharPersist")
local cjson = require("cjson")

local M = {}

--- 已注册的角色模块 (id → CharModule)
---@type table<string, CharModule>
local registry_ = {}

--- 内置预设ID列表
local presetIds_ = {}

--- 预设 JSON 文件列表（相对于资源根目录）
local PRESET_FILES = {
    "char_defs/wisdel.json",
    "char_defs/bloody_wolf.json",
    "char_defs/kisaki.json",
    "char_defs/originium_slug.json",
    "char_defs/doro.json",
    "char_defs/qiaolezi.json",
}

-- ============================================================================
-- JSON 加载辅助
-- ============================================================================

--- 从 JSON 文件加载角色定义
---@param path string 资源相对路径
---@return CharModule|nil mod, string|nil error
local function LoadPresetFromJSON(path)
    local file = cache:GetFile(path)
    if not file then
        return nil, "File not found: " .. path
    end
    local content = file:ReadString()
    file:Close()
    if not content or content == "" then
        return nil, "Empty file: " .. path
    end
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        return nil, "JSON decode error in " .. path .. ": " .. tostring(data)
    end
    -- 使用 Deserialize 填充默认值
    local mod = CharModule.Deserialize(data)
    local valid, err = CharModule.Validate(mod)
    if not valid then
        return nil, "Validation failed for " .. path .. ": " .. (err or "unknown")
    end
    return mod, nil
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化注册表（从 JSON 加载预设 + 恢复持久化角色）
function M.Init()
    registry_ = {}
    presetIds_ = {}

    -- 从 JSON 文件加载内置预设
    for _, path in ipairs(PRESET_FILES) do
        local mod, err = LoadPresetFromJSON(path)
        if mod then
            M.Register(mod, true)
            print("[CharRegistry] Loaded preset from JSON: " .. mod.id)
        else
            print("[CharRegistry] Failed to load preset: " .. (err or "unknown"))
        end
    end

    -- 恢复持久化的自定义角色
    local saved = CharPersist.LoadAll()
    for _, mod in ipairs(saved) do
        local valid, err = CharModule.Validate(mod)
        if valid then
            registry_[mod.id] = mod
            print("[CharRegistry] Loaded custom: " .. mod.id)
        else
            print("[CharRegistry] Skip invalid saved module: " .. (err or "unknown"))
        end
    end

    print("[CharRegistry] Init complete. Total: " .. M.GetCount() .. " characters")
end

--- 注册一个角色模块
---@param mod CharModule
---@param isPreset boolean|nil 是否为内置预设
---@return boolean success, string|nil error
function M.Register(mod, isPreset)
    local valid, err = CharModule.Validate(mod)
    if not valid then
        return false, err
    end
    registry_[mod.id] = mod
    if isPreset then
        table.insert(presetIds_, mod.id)
    end
    return true, nil
end

--- 注销角色模块（不能删除预设）
---@param id string
---@return boolean
function M.Unregister(id)
    if not registry_[id] then return false end
    -- 检查是否预设
    for _, pid in ipairs(presetIds_) do
        if pid == id then
            print("[CharRegistry] Cannot unregister preset: " .. id)
            return false
        end
    end
    registry_[id] = nil
    CharPersist.Delete(id)
    return true
end

--- 获取角色模块
---@param id string
---@return CharModule|nil
function M.Get(id)
    return registry_[id]
end

--- 获取所有角色ID列表
---@return string[]
function M.GetAllIds()
    local ids = {}
    for id, _ in pairs(registry_) do
        table.insert(ids, id)
    end
    table.sort(ids)
    return ids
end

--- 获取预设角色ID列表
---@return string[]
function M.GetPresetIds()
    return presetIds_
end

--- 获取自定义角色ID列表
---@return string[]
function M.GetCustomIds()
    local ids = {}
    for id, _ in pairs(registry_) do
        local isPreset = false
        for _, pid in ipairs(presetIds_) do
            if pid == id then isPreset = true; break end
        end
        if not isPreset then
            table.insert(ids, id)
        end
    end
    table.sort(ids)
    return ids
end

--- 判断是否为预设角色
---@param id string
---@return boolean
function M.IsPreset(id)
    for _, pid in ipairs(presetIds_) do
        if pid == id then return true end
    end
    return false
end

--- 获取注册数量
---@return number
function M.GetCount()
    local count = 0
    for _ in pairs(registry_) do count = count + 1 end
    return count
end

--- 保存自定义角色（注册 + 持久化）
---@param mod CharModule
---@return boolean success, string|nil error
function M.SaveCustom(mod, isPreset)
    local ok, err = M.Register(mod, false)
    if not ok then return false, err end
    CharPersist.Save(mod)
    return true, nil
end

--- 当前使用的角色 ID（外部可设置，默认返回第一个自定义角色或首个预设）
---@type string|nil
local currentId_ = nil

--- 设置当前使用的角色 ID
---@param id string
function M.SetCurrentId(id)
    currentId_ = id
end

--- 获取当前使用的角色 ID
---@return string|nil
function M.GetCurrentId()
    if currentId_ and registry_[currentId_] then
        return currentId_
    end
    -- 优先返回第一个自定义角色
    local customIds = M.GetCustomIds()
    if #customIds > 0 then return customIds[1] end
    -- 否则返回第一个预设
    if #presetIds_ > 0 then return presetIds_[1] end
    return nil
end

return M
