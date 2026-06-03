---
name: ui-widget-tabs
description: "基于 urhox-libs/UI Widget 的标签页与胶囊切换组件（声明式、开箱即用）。Use when users need to (1) 在 UI 组件项目中创建标签页/tab 切换, (2) 使用 Widget 系统实现 folder tabs 而非 raw NanoVG, (3) 创建 pill toggle / 胶囊切换 / segmented control, (4) 标签页带底部指示条, (5) 用户使用 urhox-libs/UI 并需要 tab/toggle 组件, (6) 多面板切换的容器组件, (7) 用户提到 tabs widget / UI tabs / 标签切换组件。注意：如果用户项目是纯 NanoVG 项目（无 UI 组件），应该用 @ui_folder-tabs skill（NanoVG 绘制版）。本 skill 适用于所有使用 urhox-libs/UI 的项目。"
---

# Widget Tabs & Pill Toggle 组件

基于 `urhox-libs/UI` 声明式 Widget 系统的标签页和胶囊切换组件。与 `@ui_folder-tabs`（raw NanoVG 绘制版）的区别：本组件直接用 Widget 树构建，自动响应布局，无需手写坐标计算和命中检测。

## 何时使用本 skill vs @ui_folder-tabs

| 项目类型 | 选择 |
|---------|------|
| 使用 `urhox-libs/UI` 的项目（大多数新项目） | **本 skill** |
| 纯 NanoVG 渲染项目（无 UI 组件） | `@ui_folder-tabs` |

## 两种组件

### 1. FolderTabs — 文件夹标签页

选中 Tab 背景与下方面板同色融合，底部彩色指示条强调当前选项。适合多面板内容切换（如编辑器的"外观/行为/属性"选项卡）。

### 2. PillToggle — 胶囊切换按钮

圆角轨道背景 + 选中段独立高亮（填充+描边），支持每个选项自定义颜色。适合模式切换、状态筛选（如"攻击/防御"、"全部/已完成/进行中"）。

## 完整实现

参考 `references/FolderTabs.lua` 获取完整可用代码。下面是使用指南。

## 使用方法

```lua
local FolderTabs = require("ui.components.FolderTabs")
-- 或者直接将 references/FolderTabs.lua 内容复制到项目中

-- ┌─────────────────────────────────────────────────┐
-- │  FolderTabs 用法                                 │
-- └─────────────────────────────────────────────────┘

local tabBar, tabApi = FolderTabs.CreateFolderTabs({
    tabs = {
        { id = "appearance", label = "外观" },
        { id = "behaviour",  label = "行为" },
        { id = "stats",      label = "属性" },
    },
    activeId = "appearance",
    height = 34,           -- 可选，默认 34
    onSwitch = function(id)
        -- id 就是被选中的 tab.id
        print("切换到: " .. id)
        -- 这里切换对应面板的显示/隐藏
    end,
})

-- API:
tabApi.SetActive("behaviour")      -- 程序化切换
local current = tabApi.GetActive()  -- 获取当前选中

-- ┌─────────────────────────────────────────────────┐
-- │  PillToggle 用法                                 │
-- └─────────────────────────────────────────────────┘

local pill, pillApi = FolderTabs.CreatePillToggle({
    tabs = {
        { id = "attack",  label = "攻击", color = { 255, 80, 80 } },
        { id = "defense", label = "防御", color = { 80, 180, 255 } },
    },
    activeId = "attack",
    height = 30,           -- 可选，默认 30
    fontSize = 12,         -- 可选，默认 12
    trackColor = { 28, 30, 42, 220 },  -- 可选，背景轨道颜色
    onSwitch = function(id)
        print("模式切换: " .. id)
    end,
})

-- API（同 FolderTabs）:
pillApi.SetActive("defense")
pillApi.GetActive()
```

## 集成到界面

两个组件都返回 `(widget, api)`，widget 直接作为 children 放入任何 UI 容器：

```lua
local UI = require("urhox-libs/UI")
local FolderTabs = require("ui.components.FolderTabs")

-- 内容面板（按 tab 显示/隐藏）
local panels = {}
panels.appearance = UI.Panel { width = "100%", children = { --[[ ... ]] } }
panels.behaviour  = UI.Panel { width = "100%", children = { --[[ ... ]] } }
panels.stats      = UI.Panel { width = "100%", visible = false, children = { --[[ ... ]] } }

local activePanel = "appearance"

local tabBar, tabApi = FolderTabs.CreateFolderTabs({
    tabs = {
        { id = "appearance", label = "外观" },
        { id = "behaviour",  label = "行为" },
        { id = "stats",      label = "属性" },
    },
    activeId = activePanel,
    onSwitch = function(id)
        -- 隐藏旧面板，显示新面板
        panels[activePanel]:SetVisible(false)
        panels[id]:SetVisible(true)
        activePanel = id
    end,
})

local root = UI.Panel {
    width = 400, height = 500,
    children = {
        tabBar,
        UI.Panel {
            width = "100%", flexGrow = 1,
            backgroundColor = { 30, 30, 42, 255 },  -- 与 Tab 选中色一致以融合
            children = { panels.appearance, panels.behaviour, panels.stats },
        },
    },
}
UI.SetRoot(root)
```

## 自定义样式

两个组件的颜色都在模块顶部的常量表中定义，修改即可全局调整风格：

```lua
-- FolderTabs 配色
local FOLDER_COLORS = {
    panelBg     = { 30, 30, 42, 255 },     -- 面板/选中Tab背景（融合色）
    tabNormal   = { 20, 20, 28, 200 },     -- 未选中Tab背景
    tabBorder   = { 55, 60, 80, 120 },     -- Tab边框色
    accent      = { 80, 180, 255, 255 },   -- 选中指示条颜色
    textActive  = { 240, 240, 250, 255 },  -- 选中文字
    textNormal  = { 130, 135, 150, 200 },  -- 未选中文字
}

-- PillToggle 配色
local PILL_COLORS = {
    trackBg     = { 28, 30, 42, 220 },     -- 底层背景轨道
    selFill     = { 80, 160, 255, 50 },    -- 选中胶囊填充
    selBorder   = { 80, 160, 255, 160 },   -- 选中胶囊描边
    textActive  = { 120, 200, 255, 245 },  -- 选中文字
    textNormal  = { 130, 135, 150, 170 },  -- 未选中文字
}
```

## opts 参数一览

### CreateFolderTabs(opts)

| 字段 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| `tabs` | `{id, label}[]` | 是 | — | 标签定义数组 |
| `activeId` | `string` | 否 | 第一个 tab 的 id | 初始选中 |
| `onSwitch` | `fun(id)` | 否 | — | 切换回调 |
| `height` | `number` | 否 | 34 | Tab 栏高度 |

### CreatePillToggle(opts)

| 字段 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| `tabs` | `{id, label, color?}[]` | 是 | — | 选项定义（color 为 RGB 三元组） |
| `activeId` | `string` | 否 | 第一个 tab 的 id | 初始选中 |
| `onSwitch` | `fun(id)` | 否 | — | 切换回调 |
| `height` | `number` | 否 | 30 | 整体高度 |
| `fontSize` | `number` | 否 | 12 | 文字大小 |
| `trackColor` | `{r,g,b,a}` | 否 | 深色 | 背景轨道颜色 |

## 返回的 API

两个组件返回的 api 对象接口完全一致：

| 方法 | 说明 |
|------|------|
| `api.SetActive(id)` | 程序化切换到指定 tab（触发样式刷新，不触发 onSwitch） |
| `api.GetActive()` | 返回当前选中的 id |
