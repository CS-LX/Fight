---
name: node-graph-editor
description: "NanoVG 节点图可视化编辑器组件（Widget:Extend），支持无限画布/缩放平移/贝塞尔连线/节点拖拽。Use when users need to (1) 创建可视化节点编辑器/node graph editor, (2) 行为树/BT 编辑器 UI, (3) 对话树/dialogue tree 编辑器, (4) 技能树/skill tree 编辑器, (5) 状态机可视化编辑, (6) shader graph / 材质节点编辑器, (7) 任务/quest 流程图编辑, (8) 任何需要节点+连线的可视化编辑场景, (9) 用户提到 node editor / graph editor / visual scripting / 连线编辑器。本组件基于 Widget:Extend 模式 + NanoVG 自绘，适用于使用 urhox-libs/UI 的项目。"
---

# NanoVG 节点图编辑器

一个通用的可视化节点图编辑器 Widget 组件，基于 `Widget:Extend` + NanoVG 自绘实现。适用于行为树、对话树、状态机、shader graph、技能树、任务流程等任何需要"节点+连线"可视化编辑的场景。

## 核心能力

- **无限画布**：中键/右键拖拽平移，滚轮缩放（0.3×–3.0×）
- **节点系统**：拖拽移动、选中高亮、hover 反馈、根节点标记
- **连线系统**：输出端口→输入端口贝塞尔曲线连接，支持子节点排序
- **网格背景**：随缩放自适应的辅助网格
- **序列化**：`{rootId, nodes, edges}` JSON 结构，可存盘/加载
- **可配置节点类型**：组合节点（多子）、装饰器（单子）、叶节点（无子）

## 架构设计

组件分为三层，可按需裁剪：

```
┌─────────────────────────────────────┐
│  NodeGraphCanvas (Widget:Extend)     │  ← 核心画布：渲染+交互+数据
├─────────────────────────────────────┤
│  NodePalette                         │  ← 可选：节点类型选择面板
├─────────────────────────────────────┤
│  NodeInspector                       │  ← 可选：选中节点属性面板
└─────────────────────────────────────┘
```

完整实现参见 `references/NodeGraphCanvas.lua`。

## 快速使用

```lua
local Widget = require("urhox-libs/UI/Core/Widget")
local UI = require("urhox-libs/UI")
local NodeGraphCanvas = require("ui.components.NodeGraphCanvas")  -- 复制到项目中

-- 定义你的节点类型（按领域自定义）
local MY_NODE_TYPES = {
    -- 组合节点（可接多个子节点）
    { type = "Sequence",  category = "composite", label = "序列",   ports = "N" },
    { type = "Selector",  category = "composite", label = "选择器", ports = "N" },
    -- 装饰器（只能接 1 个子节点）
    { type = "Invert",    category = "decorator", label = "取反",   ports = "1" },
    { type = "Repeat",    category = "decorator", label = "重复",   ports = "1" },
    -- 叶节点（无子节点，执行具体动作）
    { type = "Task",      category = "leaf",      label = "任务",   ports = "0" },
}

-- 可选：叶节点任务注册表（为 Task 类型节点提供具体行为绑定）
local MY_TASK_REGISTRY = {
    { name = "move_to",  label = "移动到", category = "movement" },
    { name = "attack",   label = "攻击",   category = "combat" },
    { name = "wait",     label = "等待",   category = "utility" },
}

-- 创建画布
local canvas = NodeGraphCanvas {
    width = "100%", height = "100%",
    nodeTypes = MY_NODE_TYPES,        -- 自定义节点类型
    taskRegistry = MY_TASK_REGISTRY,  -- 可选：叶节点注册表
    onSelectionChanged = function(nodeData)
        -- nodeData = { id, type, name, x, y, taskName } 或 nil
    end,
    onTreeChanged = function(treeData)
        -- treeData = { rootId, nodes, edges }
    end,
}

-- 公开 API
canvas:AddNode("Sequence", 100, 100, "根序列")
canvas:AddNode("Task", 300, 100, "攻击", "attack")
canvas:AddEdge("node_1", "node_2")
canvas:RemoveNode("node_2")
canvas:RemoveEdge("node_1", "node_2")
canvas:SetSelected("node_1")
canvas:SetAsRoot("node_1")
canvas:ClearAll()

local data = canvas:GetTreeData()  -- 序列化
canvas:LoadTreeData(data)          -- 反序列化
```

## 数据格式

```lua
-- GetTreeData() 返回 / LoadTreeData() 接受的结构：
{
    rootId = "node_1",  -- 根节点 ID（可为 nil）
    nodes = {
        ["node_1"] = { id = "node_1", type = "Sequence", name = "根序列", x = 100, y = 100 },
        ["node_2"] = { id = "node_2", type = "Task", name = "攻击", x = 300, y = 100, taskName = "attack" },
    },
    edges = {
        { from = "node_1", to = "node_2", order = 1 },
    },
}
```

- `nodes` 是 id→data 的字典，每个节点有唯一 `id`（格式 `"node_N"`）
- `edges` 是有序数组，`order` 决定同一父节点下子节点的执行顺序
- `taskName` 仅 Task 类型使用，引用 taskRegistry 中的 `name`

## 节点类型定义规范

```lua
{
    type = "NodeTypeName",       -- 唯一标识符，用于代码引用
    category = "composite",      -- "composite" | "decorator" | "leaf"
    label = "显示名",            -- UI 中展示的文字
    ports = "N",                 -- "N"=无限子节点, "1"=单子节点, "0"=无子节点
    color = { r, g, b, a },     -- 可选：header 颜色，不填则按 category 自动分配
}
```

**category 决定连线规则**：
- `composite`：输出端口可连接任意数量子节点
- `decorator`：输出端口最多连 1 个子节点（再连会被拒绝）
- `leaf`：无输出端口（不能有子节点）

## 交互操作

| 操作 | 行为 |
|------|------|
| 左键点击节点 | 选中（触发 onSelectionChanged） |
| 左键拖拽节点 | 移动节点位置 |
| 左键点击空白 | 取消选中 |
| 左键拖拽输出端口→输入端口 | 创建连线 |
| 右键/中键拖拽 | 平移画布 |
| 滚轮 | 缩放（0.3×–3.0×） |

## 自定义外观

颜色常量在组件顶部，按需修改：

```lua
-- 节点类型默认颜色（按 type 名匹配，未匹配则用灰色）
local TYPE_COLORS = {
    Sequence       = { 59, 125, 216, 255 },   -- 蓝
    Selector       = { 44, 165, 141, 255 },   -- 青
    Random         = { 224, 123, 57, 255 },   -- 橙
    Task           = { 76, 175, 80, 255 },    -- 绿
    -- 装饰器统一紫色
    Invert         = { 156, 86, 184, 255 },
    Repeat         = { 156, 86, 184, 255 },
}

-- 尺寸常量
local NODE_W = 160       -- 节点宽度
local NODE_H = 60        -- 节点高度
local PORT_RADIUS = 6    -- 端口圆半径
local HEADER_H = 22      -- Header 色条高度
local GRID_SIZE = 40     -- 网格间距
```

## 配套组件（可选）

### NodePalette — 节点类型选择面板

按 category 分组展示所有可用节点类型，点击后调用 canvas:AddNode()：

```lua
-- 实现思路（不是完整代码）
local function CreateNodePalette(canvas, nodeTypes, taskRegistry)
    local categories = { composite = {}, decorator = {}, leaf = {} }
    for _, nt in ipairs(nodeTypes) do
        table.insert(categories[nt.category], nt)
    end
    -- 每个 category 一个分组，每个 nodeType 一个按钮
    -- 点击按钮 → canvas:AddNode(nt.type, centerX, centerY, nt.label, taskName)
end
```

### NodeInspector — 节点属性面板

显示选中节点的详情，支持编辑名称、删除、设为根节点：

```lua
-- 监听选中变化
canvas.onSelectionChanged = function(nodeData)
    if nodeData then
        -- 显示：节点类型标签、名称编辑框、taskName（叶节点）、删除按钮、设为根按钮
    else
        -- 显示：空状态提示
    end
end
```

## 领域适配示例

### 行为树编辑器

```lua
local BT_TYPES = {
    { type = "Sequence",       category = "composite", label = "序列" },
    { type = "Priority",       category = "composite", label = "优先级" },
    { type = "ActivePriority", category = "composite", label = "抢占优先级" },
    { type = "Random",         category = "composite", label = "随机" },
    { type = "Invert",         category = "decorator", label = "取反" },
    { type = "AlwaysFail",     category = "decorator", label = "强制失败" },
    { type = "AlwaysSucceed",  category = "decorator", label = "强制成功" },
    { type = "Task",           category = "leaf",      label = "任务" },
}
```

### 对话树编辑器

```lua
local DIALOGUE_TYPES = {
    { type = "DialogueLine",  category = "composite", label = "对话" },
    { type = "Choice",        category = "composite", label = "选项分支" },
    { type = "Condition",     category = "decorator", label = "条件判断" },
    { type = "SetVariable",   category = "leaf",      label = "设置变量" },
    { type = "TriggerEvent",  category = "leaf",      label = "触发事件" },
}
```

### 状态机编辑器

```lua
local FSM_TYPES = {
    { type = "State",      category = "composite", label = "状态" },
    { type = "Transition", category = "decorator", label = "转换条件" },
    { type = "Action",     category = "leaf",      label = "动作" },
}
```
