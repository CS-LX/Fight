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
-- 自定义装饰器（不修改 BT 库，在编译阶段包装子节点）
-- ============================================================================

--- RepeatN: 重复执行子节点 N 次（全部成功才成功，任意一次失败则失败）
---@param childBT table 子节点
---@param count number 重复次数
local function WrapRepeatN(childBT, count)
    return BT.Task:new({
        start = function(task)
            task._repeatCount = 0
            task._maxCount = count or 3
        end,
        run = function(task, ctx)
            task._repeatCount = task._repeatCount + 1
            -- 利用子节点的 run（需要手动驱动）
            childBT:setControl({
                success = function()
                    if task._repeatCount >= task._maxCount then
                        task:success()
                    else
                        task:running()
                    end
                end,
                fail = function()
                    task:fail()
                end,
                running = function()
                    task:running()
                end,
            })
            childBT:start(ctx)
            childBT:call_run(ctx)
        end,
    })
end

--- UntilFail: 循环执行子节点直到它失败（失败时返回 success）
---@param childBT table 子节点
local function WrapUntilFail(childBT)
    return BT.Task:new({
        run = function(task, ctx)
            childBT:setControl({
                success = function()
                    task:running()  -- 子节点成功 → 继续循环
                end,
                fail = function()
                    task:success()  -- 子节点失败 → 本节点成功退出
                end,
                running = function()
                    task:running()
                end,
            })
            childBT:start(ctx)
            childBT:call_run(ctx)
        end,
    })
end

--- UntilSuccess: 循环执行子节点直到它成功
---@param childBT table 子节点
local function WrapUntilSuccess(childBT)
    return BT.Task:new({
        run = function(task, ctx)
            childBT:setControl({
                success = function()
                    task:success()
                end,
                fail = function()
                    task:running()  -- 子节点失败 → 继续循环
                end,
                running = function()
                    task:running()
                end,
            })
            childBT:start(ctx)
            childBT:call_run(ctx)
        end,
    })
end

--- Cooldown: 子节点执行成功后进入冷却期，冷却期间直接失败
---@param childBT table 子节点
---@param cooldownTime number 冷却时间(秒)
local function WrapCooldown(childBT, cooldownTime)
    return BT.Task:new({
        start = function(task)
            task._lastSuccess = -9999
        end,
        run = function(task, ctx)
            local now = (ctx.char and ctx.char._btTime) or 0
            if now - task._lastSuccess < cooldownTime then
                task:fail()  -- 冷却中
                return
            end
            childBT:setControl({
                success = function()
                    task._lastSuccess = now
                    task:success()
                end,
                fail = function()
                    task:fail()
                end,
                running = function()
                    task:running()
                end,
            })
            childBT:start(ctx)
            childBT:call_run(ctx)
        end,
    })
end

--- Probability: 以指定概率执行子节点，否则直接失败
---@param childBT table 子节点
---@param chance number 0~1之间的概率
local function WrapProbability(childBT, chance)
    return BT.Task:new({
        run = function(task, ctx)
            if math.random() > chance then
                task:fail()  -- 概率未命中
                return
            end
            childBT:setControl({
                success = function() task:success() end,
                fail = function() task:fail() end,
                running = function() task:running() end,
            })
            childBT:start(ctx)
            childBT:call_run(ctx)
        end,
    })
end

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
        local taskInstance = BTTaskLibrary.Create(taskName, nodeData.params)
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

    -- 自定义装饰器（带参数的包装节点）
    if nodeType == "RepeatN" then
        local childList = childrenOf[nodeId] or {}
        if #childList == 0 then return nil, "RepeatN has no child: " .. nodeId end
        local childBT, err = M._CompileNode(childList[1].id, nodes, childrenOf)
        if not childBT then return nil, err end
        local count = nodeData.count or 3
        return WrapRepeatN(childBT, count), nil
    end

    if nodeType == "UntilFail" then
        local childList = childrenOf[nodeId] or {}
        if #childList == 0 then return nil, "UntilFail has no child: " .. nodeId end
        local childBT, err = M._CompileNode(childList[1].id, nodes, childrenOf)
        if not childBT then return nil, err end
        return WrapUntilFail(childBT), nil
    end

    if nodeType == "UntilSuccess" then
        local childList = childrenOf[nodeId] or {}
        if #childList == 0 then return nil, "UntilSuccess has no child: " .. nodeId end
        local childBT, err = M._CompileNode(childList[1].id, nodes, childrenOf)
        if not childBT then return nil, err end
        return WrapUntilSuccess(childBT), nil
    end

    if nodeType == "Cooldown" then
        local childList = childrenOf[nodeId] or {}
        if #childList == 0 then return nil, "Cooldown has no child: " .. nodeId end
        local childBT, err = M._CompileNode(childList[1].id, nodes, childrenOf)
        if not childBT then return nil, err end
        local cooldownTime = nodeData.cooldownTime or 2.0
        return WrapCooldown(childBT, cooldownTime), nil
    end

    if nodeType == "Probability" then
        local childList = childrenOf[nodeId] or {}
        if #childList == 0 then return nil, "Probability has no child: " .. nodeId end
        local childBT, err = M._CompileNode(childList[1].id, nodes, childrenOf)
        if not childBT then return nil, err end
        local chance = nodeData.chance or 0.5
        return WrapProbability(childBT, chance), nil
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
