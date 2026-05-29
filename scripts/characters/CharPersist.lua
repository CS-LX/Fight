-- ============================================================================
-- characters/CharPersist.lua - 角色模块持久化（JSON 文件存储）
-- ============================================================================
-- 职责：保存/加载/删除自定义角色模块到本地文件系统
-- 使用 cjson + File API（WASM 下为内存存储，刷新后丢失）

local CharModule = require("characters.CharModule")

local M = {}

-- 存储目录
local SAVE_DIR = "characters"
-- 索引文件名
local INDEX_FILE = SAVE_DIR .. "/index.json"

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保目录存在
local function EnsureDir()
    if not fileSystem:DirExists(SAVE_DIR) then
        fileSystem:CreateDir(SAVE_DIR)
    end
end

--- 获取角色存储文件路径
---@param id string
---@return string
local function GetFilePath(id)
    return SAVE_DIR .. "/" .. id .. ".json"
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 保存角色模块到文件
---@param mod CharModule
---@return boolean
function M.Save(mod)
    EnsureDir()
    local data = CharModule.Serialize(mod)
    local json = cjson.encode(data)

    local file = File(GetFilePath(mod.id), FILE_WRITE)
    if file then
        file:WriteLine(json)
        file:Close()
        -- 更新索引
        M.UpdateIndex(mod.id, true)
        print("[CharPersist] Saved: " .. mod.id)
        return true
    end
    print("[CharPersist] Failed to save: " .. mod.id)
    return false
end

--- 加载单个角色模块
---@param id string
---@return CharModule|nil
function M.Load(id)
    local path = GetFilePath(id)
    if not fileSystem:FileExists(path) then
        return nil
    end

    local file = File(path, FILE_READ)
    if not file then return nil end

    local json = file:ReadLine()
    file:Close()

    if not json or json == "" then return nil end

    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then
        print("[CharPersist] Decode failed for: " .. id)
        return nil
    end

    return CharModule.Deserialize(data)
end

--- 加载所有已保存的角色模块
---@return CharModule[]
function M.LoadAll()
    local results = {}
    local ids = M.GetSavedIds()

    for _, id in ipairs(ids) do
        local mod = M.Load(id)
        if mod then
            table.insert(results, mod)
        end
    end

    return results
end

--- 删除角色存档
---@param id string
---@return boolean
function M.Delete(id)
    local path = GetFilePath(id)
    if fileSystem:FileExists(path) then
        fileSystem:Delete(path)
        M.UpdateIndex(id, false)
        print("[CharPersist] Deleted: " .. id)
        return true
    end
    return false
end

--- 获取已保存的角色ID列表（从索引文件读取）
---@return string[]
function M.GetSavedIds()
    if not fileSystem:FileExists(INDEX_FILE) then
        return {}
    end

    local file = File(INDEX_FILE, FILE_READ)
    if not file then return {} end

    local json = file:ReadLine()
    file:Close()

    if not json or json == "" then return {} end

    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then return {} end

    return data.ids or {}
end

--- 更新索引文件（添加或移除ID）
---@param id string
---@param add boolean true=添加, false=移除
function M.UpdateIndex(id, add)
    EnsureDir()
    local ids = M.GetSavedIds()

    if add then
        -- 避免重复
        for _, existId in ipairs(ids) do
            if existId == id then return end
        end
        table.insert(ids, id)
    else
        -- 移除
        for i, existId in ipairs(ids) do
            if existId == id then
                table.remove(ids, i)
                break
            end
        end
    end

    local json = cjson.encode({ ids = ids })
    local file = File(INDEX_FILE, FILE_WRITE)
    if file then
        file:WriteLine(json)
        file:Close()
    end
end

return M
