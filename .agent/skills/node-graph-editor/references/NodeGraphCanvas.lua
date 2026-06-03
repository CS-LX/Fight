-- ============================================================================
-- NodeGraphCanvas.lua - 通用节点图可视化编辑画布
-- ============================================================================
-- 无限画布组件：NanoVG 自绘节点 + 贝塞尔连线 + 缩放/平移 + 交互
-- 基于 Widget:Extend 模式
--
-- 使用方式：
--   1. 复制到项目 scripts/ 目录
--   2. 自定义 NODE_TYPES 和 TYPE_COLORS
--   3. 可选传入 taskRegistry（叶节点的具体动作注册表）

local Widget = require("urhox-libs/UI/Core/Widget")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")

local NodeGraphCanvas = Widget:Extend("NodeGraphCanvas")

-- ============================================================================
-- 默认常量（使用时可覆盖）
-- ============================================================================

local NODE_W = 160
local NODE_H = 60
local PORT_RADIUS = 6
local HEADER_H = 22
local MIN_ZOOM = 0.3
local MAX_ZOOM = 3.0
local GRID_SIZE = 40

-- 默认节点类型颜色（按 type 名匹配）
local DEFAULT_TYPE_COLORS = {
    Sequence       = { 59, 125, 216, 255 },
    Priority       = { 44, 165, 141, 255 },
    Selector       = { 44, 165, 141, 255 },
    ActivePriority = { 0, 194, 204, 255 },
    Random         = { 224, 123, 57, 255 },
    Task           = { 76, 175, 80, 255 },
    Invert         = { 156, 86, 184, 255 },
    AlwaysFail     = { 156, 86, 184, 255 },
    AlwaysSucceed  = { 156, 86, 184, 255 },
    Repeat         = { 156, 86, 184, 255 },
    -- 对话树常用
    DialogueLine   = { 59, 125, 216, 255 },
    Choice         = { 224, 123, 57, 255 },
    Condition      = { 156, 86, 184, 255 },
    SetVariable    = { 76, 175, 80, 255 },
    TriggerEvent   = { 76, 175, 80, 255 },
    -- 状态机
    State          = { 59, 125, 216, 255 },
    Transition     = { 156, 86, 184, 255 },
    Action         = { 76, 175, 80, 255 },
}

-- 默认节点类型定义（行为树）
local DEFAULT_NODE_TYPES = {
    { type = "Sequence",       category = "composite", label = "序列",       ports = "N" },
    { type = "Priority",       category = "composite", label = "优先级",     ports = "N" },
    { type = "Random",         category = "composite", label = "随机",       ports = "N" },
    { type = "Invert",         category = "decorator", label = "取反",       ports = "1" },
    { type = "AlwaysFail",     category = "decorator", label = "强制失败",   ports = "1" },
    { type = "AlwaysSucceed",  category = "decorator", label = "强制成功",   ports = "1" },
    { type = "Task",           category = "leaf",      label = "任务",       ports = "0" },
}

-- ============================================================================
-- 初始化
-- ============================================================================

function NodeGraphCanvas:Init(props)
    props = props or {}
    props.overflow = "hidden"
    props.backgroundColor = props.backgroundColor or { 30, 30, 35, 255 }

    -- 可配置项
    self.nodeTypes_ = props.nodeTypes or DEFAULT_NODE_TYPES
    self.typeColors_ = props.typeColors or DEFAULT_TYPE_COLORS
    self.taskRegistry_ = props.taskRegistry or {}  -- { {name, label, category}, ... }

    -- 构建 taskRegistry 快速查找表
    self.taskLookup_ = {}
    for _, task in ipairs(self.taskRegistry_) do
        self.taskLookup_[task.name] = task
    end

    -- 画布状态
    self.zoom_ = 1.0
    self.panX_ = 0
    self.panY_ = 0

    -- 节点数据: { id -> { id, type, name, x, y, taskName } }
    self.nodes_ = {}
    -- 连线数据: { { from, to, order } }
    self.edges_ = {}
    -- ID 计数器
    self.nextId_ = 1
    -- 根节点 ID
    self.rootId_ = nil

    -- 交互状态
    self.isPanning_ = false
    self.lastPanX_ = 0
    self.lastPanY_ = 0
    self.isDraggingNode_ = false
    self.dragNodeId_ = nil
    self.dragOffsetX_ = 0
    self.dragOffsetY_ = 0
    self.isConnecting_ = false
    self.connectFromId_ = nil
    self.connectEndX_ = 0
    self.connectEndY_ = 0
    self.selectedId_ = nil
    self.hoveredId_ = nil
    self.time_ = 0

    -- 回调
    self.onSelectionChanged_ = props.onSelectionChanged
    self.onTreeChanged_ = props.onTreeChanged

    Widget.Init(self, props)
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 获取所有节点数据（用于序列化）
function NodeGraphCanvas:GetTreeData()
    return {
        rootId = self.rootId_,
        nodes = self.nodes_,
        edges = self.edges_,
    }
end

--- 加载树数据
function NodeGraphCanvas:LoadTreeData(data)
    self.nodes_ = data.nodes or {}
    self.edges_ = data.edges or {}
    self.rootId_ = data.rootId
    -- 计算 nextId_
    local maxId = 0
    for id, _ in pairs(self.nodes_) do
        local num = tonumber(id:match("node_(%d+)"))
        if num and num > maxId then maxId = num end
    end
    self.nextId_ = maxId + 1
    self.selectedId_ = nil
end

--- 清空画布
function NodeGraphCanvas:ClearAll()
    self.nodes_ = {}
    self.edges_ = {}
    self.rootId_ = nil
    self.nextId_ = 1
    self.selectedId_ = nil
end

--- 添加节点
---@param nodeType string
---@param x number 画布坐标
---@param y number 画布坐标
---@param name string|nil
---@param taskName string|nil 叶节点的注册名
---@return string nodeId
function NodeGraphCanvas:AddNode(nodeType, x, y, name, taskName)
    local id = "node_" .. self.nextId_
    self.nextId_ = self.nextId_ + 1

    local label = name
    if not label then
        for _, info in ipairs(self.nodeTypes_) do
            if info.type == nodeType then label = info.label break end
        end
    end

    self.nodes_[id] = {
        id = id,
        type = nodeType,
        name = label or nodeType,
        x = x,
        y = y,
        taskName = taskName,
    }

    -- 第一个节点自动设为根
    if not self.rootId_ then
        self.rootId_ = id
    end

    self:FireTreeChanged()
    return id
end

--- 删除节点
function NodeGraphCanvas:RemoveNode(nodeId)
    if not self.nodes_[nodeId] then return end
    self.nodes_[nodeId] = nil
    local newEdges = {}
    for _, e in ipairs(self.edges_) do
        if e.from ~= nodeId and e.to ~= nodeId then
            newEdges[#newEdges + 1] = e
        end
    end
    self.edges_ = newEdges
    if self.rootId_ == nodeId then self.rootId_ = nil end
    if self.selectedId_ == nodeId then self.selectedId_ = nil end
    self:FireTreeChanged()
end

--- 添加连线
function NodeGraphCanvas:AddEdge(fromId, toId)
    for _, e in ipairs(self.edges_) do
        if e.from == fromId and e.to == toId then return end
    end
    if fromId == toId then return end
    local order = 1
    for _, e in ipairs(self.edges_) do
        if e.from == fromId then order = order + 1 end
    end
    self.edges_[#self.edges_ + 1] = { from = fromId, to = toId, order = order }
    self:FireTreeChanged()
end

--- 删除连线
function NodeGraphCanvas:RemoveEdge(fromId, toId)
    local newEdges = {}
    for _, e in ipairs(self.edges_) do
        if not (e.from == fromId and e.to == toId) then
            newEdges[#newEdges + 1] = e
        end
    end
    self.edges_ = newEdges
    self:FireTreeChanged()
end

--- 获取选中节点
function NodeGraphCanvas:GetSelectedNode()
    return self.selectedId_ and self.nodes_[self.selectedId_] or nil
end

--- 设置选中节点
function NodeGraphCanvas:SetSelected(nodeId)
    self.selectedId_ = nodeId
    if self.onSelectionChanged_ then
        self.onSelectionChanged_(self.nodes_[nodeId])
    end
end

--- 设为根节点
function NodeGraphCanvas:SetAsRoot(nodeId)
    if self.nodes_[nodeId] then
        self.rootId_ = nodeId
        self:FireTreeChanged()
    end
end

--- 获取节点类型定义列表
function NodeGraphCanvas:GetNodeTypes()
    return self.nodeTypes_
end

--- 获取任务注册表
function NodeGraphCanvas:GetTaskRegistry()
    return self.taskRegistry_
end

-- ============================================================================
-- 坐标转换
-- ============================================================================

function NodeGraphCanvas:ScreenToCanvas(screenX, screenY)
    local layout = self:GetAbsoluteLayout()
    if not layout then return 0, 0 end
    local cx = (screenX - layout.x - self.panX_) / self.zoom_
    local cy = (screenY - layout.y - self.panY_) / self.zoom_
    return cx, cy
end

function NodeGraphCanvas:CanvasToScreen(cx, cy)
    local layout = self:GetAbsoluteLayout()
    if not layout then return 0, 0 end
    local sx = cx * self.zoom_ + self.panX_ + layout.x
    local sy = cy * self.zoom_ + self.panY_ + layout.y
    return sx, sy
end

-- ============================================================================
-- 命中检测
-- ============================================================================

function NodeGraphCanvas:FindNodeAtCanvas(cx, cy)
    for id, node in pairs(self.nodes_) do
        if cx >= node.x and cx <= node.x + NODE_W
            and cy >= node.y and cy <= node.y + NODE_H then
            return id
        end
    end
    return nil
end

function NodeGraphCanvas:HitOutputPort(cx, cy)
    for id, node in pairs(self.nodes_) do
        local px = node.x + NODE_W
        local py = node.y + NODE_H * 0.5
        local dx = cx - px
        local dy = cy - py
        if dx * dx + dy * dy <= (PORT_RADIUS + 4) * (PORT_RADIUS + 4) then
            return id
        end
    end
    return nil
end

function NodeGraphCanvas:HitInputPort(cx, cy)
    for id, node in pairs(self.nodes_) do
        local px = node.x
        local py = node.y + NODE_H * 0.5
        local dx = cx - px
        local dy = cy - py
        if dx * dx + dy * dy <= (PORT_RADIUS + 4) * (PORT_RADIUS + 4) then
            return id
        end
    end
    return nil
end

-- ============================================================================
-- 交互事件
-- ============================================================================

function NodeGraphCanvas:OnPointerDown(event)
    Widget.OnPointerDown(self, event)

    local cx, cy = self:ScreenToCanvas(event.x, event.y)

    if event.button == PointerEvent.Button.Right or event.button == PointerEvent.Button.Middle then
        self.isPanning_ = true
        self.lastPanX_ = event.x
        self.lastPanY_ = event.y
        return true
    end

    if event.button == PointerEvent.Button.Left then
        local portId = self:HitOutputPort(cx, cy)
        if portId then
            local nodeInfo = self.nodes_[portId]
            if nodeInfo then
                local maxChildren = self:GetMaxChildren(nodeInfo.type)
                local currentChildren = self:CountChildren(portId)
                if maxChildren > 0 and currentChildren >= maxChildren then
                    return true
                end
            end
            self.isConnecting_ = true
            self.connectFromId_ = portId
            self.connectEndX_ = cx
            self.connectEndY_ = cy
            return true
        end

        local nodeId = self:FindNodeAtCanvas(cx, cy)
        if nodeId then
            self:SetSelected(nodeId)
            self.isDraggingNode_ = true
            self.dragNodeId_ = nodeId
            local node = self.nodes_[nodeId]
            self.dragOffsetX_ = cx - node.x
            self.dragOffsetY_ = cy - node.y
            return true
        end

        self:SetSelected(nil)
        return true
    end
end

function NodeGraphCanvas:OnPointerMove(event)
    Widget.OnPointerMove(self, event)

    if self.isPanning_ then
        local dx = event.x - self.lastPanX_
        local dy = event.y - self.lastPanY_
        self.panX_ = self.panX_ + dx
        self.panY_ = self.panY_ + dy
        self.lastPanX_ = event.x
        self.lastPanY_ = event.y
        return true
    end

    if self.isDraggingNode_ then
        local cx, cy = self:ScreenToCanvas(event.x, event.y)
        local node = self.nodes_[self.dragNodeId_]
        if node then
            node.x = cx - self.dragOffsetX_
            node.y = cy - self.dragOffsetY_
        end
        return true
    end

    if self.isConnecting_ then
        local cx, cy = self:ScreenToCanvas(event.x, event.y)
        self.connectEndX_ = cx
        self.connectEndY_ = cy
        return true
    end

    local cx, cy = self:ScreenToCanvas(event.x, event.y)
    self.hoveredId_ = self:FindNodeAtCanvas(cx, cy)
end

function NodeGraphCanvas:OnPointerUp(event)
    Widget.OnPointerUp(self, event)

    if self.isPanning_ then
        self.isPanning_ = false
        return true
    end

    if self.isDraggingNode_ then
        self.isDraggingNode_ = false
        self.dragNodeId_ = nil
        self:FireTreeChanged()
        return true
    end

    if self.isConnecting_ then
        local cx, cy = self:ScreenToCanvas(event.x, event.y)
        local targetId = self:HitInputPort(cx, cy)
        if not targetId then
            targetId = self:FindNodeAtCanvas(cx, cy)
        end
        if targetId and targetId ~= self.connectFromId_ then
            self:AddEdge(self.connectFromId_, targetId)
        end
        self.isConnecting_ = false
        self.connectFromId_ = nil
        return true
    end
end

function NodeGraphCanvas:OnPointerLeave(event)
    Widget.OnPointerLeave(self, event)
    self.hoveredId_ = nil
    if self.isPanning_ then self.isPanning_ = false end
end

function NodeGraphCanvas:OnWheel(dx, dy)
    local factor = dy > 0 and 1.15 or (1.0 / 1.15)
    local newZoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, self.zoom_ * factor))

    local layout = self:GetAbsoluteLayout()
    if layout then
        local centerX = layout.w * 0.5
        local centerY = layout.h * 0.5
        local scale = newZoom / self.zoom_
        self.panX_ = centerX - (centerX - self.panX_) * scale
        self.panY_ = centerY - (centerY - self.panY_) * scale
    end

    self.zoom_ = newZoom
end


-- ============================================================================
-- 辅助
-- ============================================================================

function NodeGraphCanvas:GetMaxChildren(nodeType)
    for _, info in ipairs(self.nodeTypes_) do
        if info.type == nodeType then
            if info.ports == "0" then return 0 end
            if info.ports == "1" then return 1 end
            return 999
        end
    end
    return 999
end

function NodeGraphCanvas:CountChildren(nodeId)
    local count = 0
    for _, e in ipairs(self.edges_) do
        if e.from == nodeId then count = count + 1 end
    end
    return count
end

function NodeGraphCanvas:GetSortedChildren(nodeId)
    local children = {}
    for _, e in ipairs(self.edges_) do
        if e.from == nodeId then
            children[#children + 1] = { id = e.to, order = e.order }
        end
    end
    table.sort(children, function(a, b) return a.order < b.order end)
    local result = {}
    for _, c in ipairs(children) do result[#result + 1] = c.id end
    return result
end

function NodeGraphCanvas:FireTreeChanged()
    if self.onTreeChanged_ then
        self.onTreeChanged_(self:GetTreeData())
    end
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function NodeGraphCanvas:Update(dt)
    self.time_ = (self.time_ or 0) + dt
end

-- ============================================================================
-- 渲染
-- ============================================================================

function NodeGraphCanvas:Render(nvg)
    local layout = self:GetAbsoluteLayout()
    if not layout or layout.w <= 0 or layout.h <= 0 then return end

    self:RenderFullBackground(nvg)

    nvgSave(nvg)
    nvgIntersectScissor(nvg, layout.x, layout.y, layout.w, layout.h)

    self:RenderGrid(nvg, layout)

    nvgTranslate(nvg, layout.x + self.panX_, layout.y + self.panY_)
    nvgScale(nvg, self.zoom_, self.zoom_)

    self:RenderEdges(nvg)

    if self.isConnecting_ and self.connectFromId_ then
        self:RenderPendingEdge(nvg)
    end

    self:RenderNodes(nvg)

    nvgRestore(nvg)
end

function NodeGraphCanvas:RenderGrid(nvg, layout)
    local zoom = self.zoom_
    local gridSize = GRID_SIZE * zoom
    if gridSize < 10 then return end

    local ox = (self.panX_ % gridSize)
    local oy = (self.panY_ % gridSize)

    nvgBeginPath(nvg)
    local alpha = math.floor(math.min(255, 30 * (gridSize / 40)))
    nvgStrokeColor(nvg, nvgRGBA(60, 60, 70, alpha))
    nvgStrokeWidth(nvg, 0.5)

    local x = layout.x + ox
    while x < layout.x + layout.w do
        nvgMoveTo(nvg, x, layout.y)
        nvgLineTo(nvg, x, layout.y + layout.h)
        x = x + gridSize
    end

    local y = layout.y + oy
    while y < layout.y + layout.h do
        nvgMoveTo(nvg, layout.x, y)
        nvgLineTo(nvg, layout.x + layout.w, y)
        y = y + gridSize
    end
    nvgStroke(nvg)
end

function NodeGraphCanvas:RenderEdges(nvg)
    for _, edge in ipairs(self.edges_) do
        local fromNode = self.nodes_[edge.from]
        local toNode = self.nodes_[edge.to]
        if fromNode and toNode then
            local x1 = fromNode.x + NODE_W
            local y1 = fromNode.y + NODE_H * 0.5
            local x2 = toNode.x
            local y2 = toNode.y + NODE_H * 0.5

            local cpDist = math.abs(x2 - x1) * 0.4 + 30
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgBezierTo(nvg, x1 + cpDist, y1, x2 - cpDist, y2, x2, y2)
            nvgStrokeColor(nvg, nvgRGBA(180, 180, 80, 200))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
        end
    end
end

function NodeGraphCanvas:RenderPendingEdge(nvg)
    local fromNode = self.nodes_[self.connectFromId_]
    if not fromNode then return end
    local x1 = fromNode.x + NODE_W
    local y1 = fromNode.y + NODE_H * 0.5
    local x2 = self.connectEndX_
    local y2 = self.connectEndY_

    local cpDist = math.abs(x2 - x1) * 0.4 + 30
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x1, y1)
    nvgBezierTo(nvg, x1 + cpDist, y1, x2 - cpDist, y2, x2, y2)
    nvgStrokeColor(nvg, nvgRGBA(255, 255, 100, 150))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
end

function NodeGraphCanvas:RenderNodes(nvg)
    for id, node in pairs(self.nodes_) do
        self:RenderNode(nvg, id, node)
    end
end

function NodeGraphCanvas:RenderNode(nvg, id, node)
    local x, y = node.x, node.y
    local isSelected = (id == self.selectedId_)
    local isHovered = (id == self.hoveredId_)
    local isRoot = (id == self.rootId_)
    local color = self.typeColors_[node.type] or { 100, 100, 100, 255 }

    -- 选中/根节点发光边框
    if isSelected or isRoot then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - 3, y - 3, NODE_W + 6, NODE_H + 6, 8)
        if isSelected then
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 180))
        else
            nvgStrokeColor(nvg, nvgRGBA(240, 180, 40, 160))
        end
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end

    -- 节点背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, NODE_W, NODE_H, 6)
    local bgAlpha = isHovered and 240 or 220
    nvgFillColor(nvg, nvgRGBA(45, 45, 50, bgAlpha))
    nvgFill(nvg)

    -- Header 色条
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, NODE_W, HEADER_H, 6)
    nvgRect(nvg, x, y + HEADER_H - 6, NODE_W, 6)
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgFill(nvg)

    -- 类型标签
    nvgFontSize(nvg, 11)
    nvgFontFace(nvg, "sans")
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 220))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, x + 8, y + HEADER_H * 0.5, node.type)

    -- 节点名称
    nvgFontSize(nvg, 13)
    nvgFillColor(nvg, nvgRGBA(220, 220, 220, 255))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local displayName = node.name
    if node.taskName and self.taskLookup_[node.taskName] then
        displayName = self.taskLookup_[node.taskName].label
    end
    nvgText(nvg, x + 8, y + HEADER_H + (NODE_H - HEADER_H) * 0.5, displayName)

    -- 输入端口 (左侧)
    nvgBeginPath(nvg)
    nvgCircle(nvg, x, y + NODE_H * 0.5, PORT_RADIUS)
    nvgFillColor(nvg, nvgRGBA(200, 200, 200, 200))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(80, 80, 80, 255))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    -- 输出端口 (右侧，叶节点没有)
    local hasOutput = true
    for _, info in ipairs(self.nodeTypes_) do
        if info.type == node.type and info.ports == "0" then
            hasOutput = false
            break
        end
    end
    if hasOutput then
        nvgBeginPath(nvg)
        nvgCircle(nvg, x + NODE_W, y + NODE_H * 0.5, PORT_RADIUS)
        nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], 200))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(80, 80, 80, 255))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
    end

    -- 根节点标记
    if isRoot then
        nvgFontSize(nvg, 9)
        nvgFillColor(nvg, nvgRGBA(240, 180, 40, 255))
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(nvg, x + NODE_W - 6, y + HEADER_H * 0.5, "ROOT")
    end
end

-- 导出节点类型信息供外部面板使用
NodeGraphCanvas.NODE_TYPES = DEFAULT_NODE_TYPES

return NodeGraphCanvas
