-- ============================================================================
-- ui/components/BTInspector.lua - 行为树节点属性检查面板
-- ============================================================================
-- 右侧面板: 显示选中节点的属性，支持修改名称、设为根、删除

local UI = require("urhox-libs/UI")
local BTTaskLibrary = require("logic.BTTaskLibrary")

local BTInspector = {}

--- 创建检查面板（静态壳）
--- 内部内容通过 UpdateSelection 动态更新
---@param props table { onDelete, onSetRoot, onRename }
---@return table panel, table api
function BTInspector.Create(props)
    props = props or {}

    -- 创建内容面板(会被替换内容)
    local contentPanel = UI.Panel {
        id = "bt_inspector_content",
        width = "100%",
        flexDirection = "column",
    }

    local container = UI.ScrollView {
        width = props.width or 200,
        height = "100%",
        backgroundColor = { 35, 35, 40, 240 },
        padding = 10,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                children = {
                    UI.Label {
                        text = "属性面板",
                        fontSize = 14,
                        fontWeight = "bold",
                        color = { 220, 220, 220 },
                        marginBottom = 10,
                    },
                    contentPanel,
                }
            }
        }
    }

    -- API 对象
    local api = {}

    --- 更新选中状态
    ---@param node table|nil 选中的节点数据
    function api.UpdateSelection(node)
        -- 清空旧内容
        contentPanel:RemoveAllChildren()

        if not node then
            contentPanel:AddChild(UI.Label {
                text = "未选中节点",
                fontSize = 12,
                color = { 120, 120, 120 },
            })
            return
        end

        -- 节点类型
        contentPanel:AddChild(UI.Label {
            text = "类型: " .. node.type,
            fontSize = 12,
            color = { 160, 180, 220 },
            marginBottom = 6,
        })

        -- 节点ID
        contentPanel:AddChild(UI.Label {
            text = "ID: " .. node.id,
            fontSize = 10,
            color = { 100, 100, 100 },
            marginBottom = 8,
        })

        -- 名称显示
        contentPanel:AddChild(UI.Label {
            text = "名称",
            fontSize = 11,
            color = { 150, 150, 150 },
            marginBottom = 2,
        })
        contentPanel:AddChild(UI.TextField {
            value = node.name or "",
            placeholder = "节点名称",
            width = "100%",
            marginBottom = 8,
            onSubmit = function(self, text)
                if props.onRename then
                    props.onRename(node.id, text)
                end
            end,
        })

        -- Task 节点显示绑定信息
        if node.type == "Task" and node.taskName then
            local info = BTTaskLibrary.registry[node.taskName]
            contentPanel:AddChild(UI.Panel {
                width = "100%",
                backgroundColor = { 45, 55, 45, 200 },
                borderRadius = 4,
                padding = 6,
                marginBottom = 8,
                flexDirection = "column",
                children = {
                    UI.Label {
                        text = "绑定: " .. node.taskName,
                        fontSize = 11,
                        color = { 120, 200, 120 },
                    },
                    info and UI.Label {
                        text = info.desc or "",
                        fontSize = 10,
                        color = { 100, 160, 100 },
                        marginTop = 2,
                    } or nil,
                }
            })
        end

        -- 操作按钮组
        contentPanel:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "column",
            marginTop = 12,
            gap = 6,
            children = {
                UI.Button {
                    text = "设为根节点",
                    variant = "outlined",
                    size = "small",
                    width = "100%",
                    onClick = function()
                        if props.onSetRoot then
                            props.onSetRoot(node.id)
                        end
                    end,
                },
                UI.Button {
                    text = "删除节点",
                    variant = "outlined",
                    size = "small",
                    width = "100%",
                    color = { 220, 80, 80 },
                    onClick = function()
                        if props.onDelete then
                            props.onDelete(node.id)
                        end
                    end,
                },
            }
        })
    end

    -- 初始显示空状态
    api.UpdateSelection(nil)

    return container, api
end

return BTInspector
