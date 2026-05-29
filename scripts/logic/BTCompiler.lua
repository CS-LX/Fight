-- ============================================================================
-- logic/BTCompiler.lua - 行为树编译器（JSON数据 → BT运行时对象）
-- ============================================================================
-- 将编辑器产出的节点图数据递归编译为 behaviourtree 库的运行时树

local BT = require("lib.behaviourtree")
local BTTaskLibrary = require("logic.BTTaskLibrary")

local M = {}

-- ============================================================================
-- 节点类型 → BT构造器映射
-- ============================================================================

local COMPOSITE_MAP = {
    Sequence       = BT.Sequence,
    Priority       = BT.Priority,
    ActivePriority = BT.ActivePriority,
    Random         = BT.Random,
}

local DECORATOR_MAP = {
    Invert        = BT.InvertDecorator,
    AlwaysFail    = BT.AlwaysFailDecorator,
    AlwaysSucceed = BT.AlwaysSucceedDecorator,
}

-- ============================================================================
-- 编译主函数
-- ============================================================================

--- 将编辑器的树数据编译为 BT 运行时实例
---@param treeData table { rootId, nodes, edges }
---@return table|nil BehaviourTree instance, string|nil error
function M.Compile(treeData)
    if not treeData then
        return nil, "treeData is nil"
    end
    if not treeData.rootId then
        return nil, "missing rootId"
    end
    if not treeData.nodes or not treeData.nodes[treeData.rootId] then
        return nil, "root node not found: " .. tostring(treeData.rootId)
    end

    -- 构建邻接表: parentId -> sorted children ids
    local childrenOf = {}
    for _, edge in ipairs(treeData.edges or {}) do
        if not childrenOf[edge.from] then
            childrenOf[edge.from] = {}
        end
        childrenOf[edge.from][#childrenOf[edge.from] + 1] = {
            id = edge.to,
            order = edge.order or 999,
        }
    end
    -- 按 order 排序
    for _, children in pairs(childrenOf) do
        table.sort(children, function(a, b) return a.order < b.order end)
    end

    -- 递归编译节点
    local rootBTNode, err = M._CompileNode(treeData.rootId, treeData.nodes, childrenOf)
    if not rootBTNode then
        return nil, err
    end

    -- 创建 BehaviourTree 实例
    local tree = BT:new({
        tree = rootBTNode,
        object = {},  -- 运行时由AI.lua填充上下文
    })

    return tree, nil
end

--- 递归编译单个节点
---@param nodeId string
---@param nodes table id->nodeData
---@param childrenOf table id->sorted child ids
---@return table|nil btNode, string|nil error
function M._CompileNode(nodeId, nodes, childrenOf)
    local nodeData = nodes[nodeId]
    if not nodeData then
        return nil, "node not found: " .. tostring(nodeId)
    end

    local nodeType = nodeData.type

    -- Task (叶子节点)
    if nodeType == "Task" then
        local taskName = nodeData.taskName
        if not taskName then
            -- 无绑定的Task，返回一个空成功节点
            return BT.Task:new({
                run = function(task) task:success() end,
            }), nil
        end
        local taskInstance = BTTaskLibrary.Create(taskName)
        if not taskInstance then
            return nil, "unknown task: " .. tostring(taskName)
        end
        return taskInstance, nil
    end

    -- 组合节点（Sequence/Priority/ActivePriority/Random）
    local compositeClass = COMPOSITE_MAP[nodeType]
    if compositeClass then
        local childNodes = {}
        local childList = childrenOf[nodeId] or {}
        for _, child in ipairs(childList) do
            local childBT, err = M._CompileNode(child.id, nodes, childrenOf)
            if not childBT then
                return nil, err
            end
            childNodes[#childNodes + 1] = childBT
        end
        if #childNodes == 0 then
            -- 组合节点无子节点，返回空成功
            return BT.Task:new({
                run = function(task) task:success() end,
            }), nil
        end
        return compositeClass:new({ nodes = childNodes }), nil
    end

    -- 装饰节点（Invert/AlwaysFail/AlwaysSucceed）
    local decoratorClass = DECORATOR_MAP[nodeType]
    if decoratorClass then
        local childList = childrenOf[nodeId] or {}
        if #childList == 0 then
            return nil, "decorator has no child: " .. nodeId
        end
        local childBT, err = M._CompileNode(childList[1].id, nodes, childrenOf)
        if not childBT then
            return nil, err
        end
        return decoratorClass:new({ node = childBT }), nil
    end

    return nil, "unknown node type: " .. tostring(nodeType)
end

--- 验证树数据的基本完整性（不编译，仅检查）
---@param treeData table
---@return boolean ok, string|nil error
function M.Validate(treeData)
    if not treeData then return false, "treeData is nil" end
    if not treeData.rootId then return false, "missing rootId" end
    if not treeData.nodes then return false, "missing nodes" end
    if not treeData.nodes[treeData.rootId] then
        return false, "root node not found"
    end

    -- 检查所有 Task 节点是否有有效绑定
    for id, node in pairs(treeData.nodes) do
        if node.type == "Task" and node.taskName then
            if not BTTaskLibrary.registry[node.taskName] then
                return false, "unknown task binding: " .. node.taskName .. " in node " .. id
            end
        end
    end

    -- 检查所有边的端点是否存在
    for _, edge in ipairs(treeData.edges or {}) do
        if not treeData.nodes[edge.from] then
            return false, "edge from unknown node: " .. tostring(edge.from)
        end
        if not treeData.nodes[edge.to] then
            return false, "edge to unknown node: " .. tostring(edge.to)
        end
    end

    return true, nil
end

return M
