-- ============================================================================
-- ui/BehaviourTreeEditor.lua - 行为树可视化编辑器（顶层容器）
-- ============================================================================
-- 三栏布局: [节点面板 | 画布 | 属性面板]
-- 顶部工具栏: 新建 / 清空 / 保存 / 加载 / 返回

local UI = require("urhox-libs/UI")
local BTCanvas = require("ui.components.BTCanvas")
local BTNodePalette = require("ui.components.BTNodePalette")
local BTInspector = require("ui.components.BTInspector")

local BehaviourTreeEditor = {}

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
                    if props.onSave then
                        props.onSave(data)
                    end
                    UI.Toast { text = "行为树已保存", duration = 2000 }
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
