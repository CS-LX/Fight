-- ============================================================================
-- ui/components/BTNodePalette.lua - 行为树节点类型面板
-- ============================================================================
-- 左侧面板: 分类显示所有可用节点类型，点击按钮添加到画布

local UI = require("urhox-libs/UI")
local BTCanvas = require("ui.components.BTCanvas")
local BTTaskLibrary = require("logic.BTTaskLibrary")

local BTNodePalette = {}

-- 节点分类描述
local CATEGORY_INFO = {
    { key = "composite", label = "组合节点", color = { 59, 125, 216 } },
    { key = "decorator", label = "装饰节点", color = { 156, 86, 184 } },
    { key = "leaf",      label = "叶子节点", color = { 76, 175, 80 } },
}

--- 创建节点面板
---@param props table { onAddNode: function(type, taskName) }
---@return table widget
function BTNodePalette.Create(props)
    props = props or {}
    local onAddNode = props.onAddNode

    local children = {}

    -- 标题
    children[#children + 1] = UI.Label {
        text = "节点面板",
        fontSize = 14,
        fontWeight = "bold",
        color = { 220, 220, 220 },
        marginBottom = 8,
    }

    -- 按类别生成节点按钮
    for _, catInfo in ipairs(CATEGORY_INFO) do
        -- 分类标题
        children[#children + 1] = UI.Label {
            text = catInfo.label,
            fontSize = 11,
            color = catInfo.color,
            marginTop = 10,
            marginBottom = 4,
        }

        -- 节点按钮
        if catInfo.key == "leaf" then
            -- 叶子节点来自 BTTaskLibrary
            local tasks = BTTaskLibrary.GetAll()
            for _, task in ipairs(tasks) do
                local catLabel = task.category == "condition" and "[判]" or "[动]"
                children[#children + 1] = UI.Button {
                    text = catLabel .. " " .. task.label,
                    variant = "outlined",
                    size = "small",
                    width = "100%",
                    marginBottom = 2,
                    onClick = function()
                        if onAddNode then
                            onAddNode("Task", task.name)
                        end
                    end,
                }
            end
        else
            -- 组合/装饰节点来自 NODE_TYPES
            for _, nodeInfo in ipairs(BTCanvas.NODE_TYPES) do
                if nodeInfo.category == catInfo.key then
                    children[#children + 1] = UI.Button {
                        text = nodeInfo.label,
                        variant = "outlined",
                        size = "small",
                        width = "100%",
                        marginBottom = 2,
                        onClick = function()
                            if onAddNode then
                                onAddNode(nodeInfo.type, nil)
                            end
                        end,
                    }
                end
            end
        end
    end

    -- 外层固定容器（定位 + 背景），内层 ScrollView 负责滚动
    local paletteWidth = props.width or 180
    local palette = UI.Panel {
        width = paletteWidth,
        maxWidth = paletteWidth,
        minWidth = paletteWidth,
        flexShrink = 0,
        height = "100%",
        backgroundColor = { 35, 35, 40, 240 },
        flexDirection = "column",
        overflow = "hidden",
        children = {
            UI.ScrollView {
                scrollY = true,
                bounces = false,
                flexGrow = 1,
                flexShrink = 1,
                padding = 10,
                flexDirection = "column",
                children = children,
            }
        },
    }

    return palette
end

return BTNodePalette
