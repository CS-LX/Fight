-- ============================================================================
-- ui/BehaviourTreeEditor.lua - 行为树可视化编辑器（顶层容器）
-- ============================================================================
-- 三栏布局: [节点面板 | 画布 | 属性面板]
-- 顶部工具栏: 新建 / 清空 / 保存 / 加载 / 返回

local UI = require("urhox-libs/UI")
local BTCanvas = require("ui.components.BTCanvas")
local BTNodePalette = require("ui.components.BTNodePalette")
local BTInspector = require("ui.components.BTInspector")
local BTCompiler = require("logic.BTCompiler")

local BehaviourTreeEditor = {}

-- 存档文件名
local SAVE_FILENAME = "bt_custom.json"

-- ============================================================================
-- 文件持久化
-- ============================================================================

--- 保存行为树数据到本地文件
---@param treeData table
---@return boolean success
local function SaveToFile(treeData)
    local jsonStr = cjson.encode(treeData)
    local file = File(SAVE_FILENAME, FILE_WRITE)
    if not file:IsOpen() then
        print("[BTEditor] Failed to open file for writing: " .. SAVE_FILENAME)
        return false
    end
    file:WriteString(jsonStr)
    file:Close()
    print("[BTEditor] Saved to " .. SAVE_FILENAME .. " (" .. #jsonStr .. " bytes)")
    return true
end

--- 从本地文件加载行为树数据
---@return table|nil treeData, string|nil error
local function LoadFromFile()
    if not fileSystem:FileExists(SAVE_FILENAME) then
        return nil, "文件不存在"
    end
    local file = File(SAVE_FILENAME, FILE_READ)
    if not file:IsOpen() then
        return nil, "无法打开文件"
    end
    local jsonStr = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok then
        return nil, "JSON 解析失败"
    end

    -- 基本结构验证
    if type(data) ~= "table" or not data.nodes then
        return nil, "数据格式无效"
    end

    print("[BTEditor] Loaded from " .. SAVE_FILENAME)
    return data, nil
end

--- 打开行为树编辑器
---@param props table|nil { onClose: function, initialData: table|nil, onSave: function(data) }
---@return table api 编辑器控制 API
function BehaviourTreeEditor.Open(props)
    props = props or {}

    local api = {}
    local canvas = nil
    local inspectorApi = nil

    -- ============================================================
    -- 画布组件
    -- ============================================================
    canvas = BTCanvas {
        flexGrow = 1,
        height = "100%",
        onSelectionChanged = function(node)
            if inspectorApi then
                inspectorApi.UpdateSelection(node)
            end
        end,
        onTreeChanged = function(data)
            -- 可以在这里触发自动保存等
        end,
        onDoubleClickCanvas = function(cx, cy)
            -- 双击画布空白处暂不处理（由面板按钮添加节点）
        end,
    }

    -- ============================================================
    -- 节点面板（左）
    -- ============================================================
    local palette = BTNodePalette.Create({
        width = 170,
        onAddNode = function(nodeType, taskName)
            -- 在画布中心附近添加节点
            local layout = canvas:GetAbsoluteLayout()
            local cx, cy = 0, 0
            if layout then
                cx, cy = canvas:ScreenToCanvas(
                    layout.x + layout.w * 0.5,
                    layout.y + layout.h * 0.5
                )
            end
            -- 添加微量随机偏移避免重叠
            cx = cx + (math.random() - 0.5) * 80
            cy = cy + (math.random() - 0.5) * 60
            local name = nil
            if taskName then
                local info = require("logic.BTTaskLibrary").registry[taskName]
                if info then name = info.label end
            end
            canvas:AddNode(nodeType, cx, cy, name, taskName)
        end,
    })

    -- ============================================================
    -- 属性面板（右）
    -- ============================================================
    local inspectorPanel
    inspectorPanel, inspectorApi = BTInspector.Create({
        width = 190,
        onDelete = function(nodeId)
            canvas:RemoveNode(nodeId)
            inspectorApi.UpdateSelection(nil)
        end,
        onSetRoot = function(nodeId)
            canvas:SetAsRoot(nodeId)
        end,
        onRename = function(nodeId, newName)
            local node = canvas.nodes_[nodeId]
            if node then
                node.name = newName
            end
        end,
    })

    -- ============================================================
    -- 工具栏
    -- ============================================================
    local toolbar = UI.Panel {
        width = "100%",
        height = 40,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = { 28, 28, 32, 250 },
        paddingLeft = 12,
        paddingRight = 12,
        gap = 8,
        children = {
            UI.Label {
                text = "行为树编辑器",
                fontSize = 14,
                fontWeight = "bold",
                color = { 200, 200, 200 },
                marginRight = 16,
            },
            UI.Button {
                text = "清空",
                variant = "outlined",
                size = "small",
                onClick = function()
                    canvas:ClearAll()
                    inspectorApi.UpdateSelection(nil)
                end,
            },
            UI.Button {
                text = "保存",
                variant = "primary",
                size = "small",
                onClick = function()
                    local data = canvas:GetTreeData()
                    -- 保存到文件
                    local ok = SaveToFile(data)
                    -- 回调外部
                    if props.onSave then
                        props.onSave(data)
                    end
                    UI.Toast { text = ok and "已保存到文件" or "保存失败", duration = 2000 }
                end,
            },
            UI.Button {
                text = "加载",
                variant = "outlined",
                size = "small",
                onClick = function()
                    local data, err = LoadFromFile()
                    if data then
                        canvas:LoadTreeData(data)
                        inspectorApi.UpdateSelection(nil)
                        if props.onSave then
                            props.onSave(data)
                        end
                        UI.Toast { text = "已从文件加载", duration = 2000 }
                    else
                        UI.Toast { text = "加载失败: " .. (err or "未知错误"), duration = 3000 }
                    end
                end,
            },
            -- 测试战斗按钮（高亮醒目）
            UI.Button {
                text = "测试战斗",
                variant = "primary",
                size = "small",
                backgroundColor = { 220, 80, 60 },
                onClick = function()
                    local data = canvas:GetTreeData()
                    -- 验证树结构
                    local valid, err = BTCompiler.Validate(data)
                    if not valid then
                        UI.Toast { text = "行为树无效: " .. (err or "结构错误"), duration = 3000 }
                        return
                    end
                    -- 保存并触发测试战斗
                    SaveToFile(data)
                    if props.onSave then
                        props.onSave(data)
                    end
                    if props.onTestBattle then
                        props.onTestBattle(data)
                    end
                end,
            },
            -- 弹性间隔
            UI.Panel { flexGrow = 1 },
            UI.Button {
                text = "返回",
                variant = "text",
                size = "small",
                color = { 180, 180, 180 },
                onClick = function()
                    BehaviourTreeEditor.Close()
                    if props.onClose then
                        props.onClose()
                    end
                end,
            },
        }
    }

    -- ============================================================
    -- 三栏布局主体
    -- ============================================================
    local body = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "row",
        children = {
            palette,
            canvas,
            inspectorPanel,
        }
    }

    -- ============================================================
    -- 顶层根
    -- ============================================================
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            toolbar,
            body,
        }
    }

    UI.SetRoot(root)

    -- 加载初始数据
    if props.initialData then
        canvas:LoadTreeData(props.initialData)
    end

    -- ============================================================
    -- 公开 API
    -- ============================================================
    api.canvas = canvas
    api.root = root

    function api.GetTreeData()
        return canvas:GetTreeData()
    end

    function api.LoadTreeData(data)
        canvas:LoadTreeData(data)
        inspectorApi.UpdateSelection(nil)
    end

    BehaviourTreeEditor._currentApi = api
    return api
end

--- 关闭编辑器
function BehaviourTreeEditor.Close()
    BehaviourTreeEditor._currentApi = nil
    UI.SetRoot(nil)
end

--- 获取当前编辑器 API（如果已打开）
function BehaviourTreeEditor.GetCurrent()
    return BehaviourTreeEditor._currentApi
end

return BehaviourTreeEditor
