---
name: folder-tabs
description: "NanoVG 标签页与 Pill Toggle 绘制模板。Use when users need to (1) 创建文件夹标签页/folder tabs UI, (2) 标签页与面板融合效果, (3) 外圆角/凹形圆角/round-out borders/inverse corners 标签页, (4) NanoVG 绘制带凹弧的统一路径标签页面板, (5) 用户提到 folder tab / card tab 样式, (6) 创建 pill toggle / 胶囊切换按钮 / segmented control / 两选项切换, (7) 用户提到 pill toggle 或胶囊按钮。"
---

# NanoVG 标签页 & Pill Toggle

## 决策流程

```
收到请求
  │
  ├─ 改造已有界面？
  │    读用户代码 → 找到现有 tab/按钮定义 → 确定数量和排列方向
  │
  └─ 创建新的？
       从用户描述提取数量和方向（未指定方向默认水平，未指定数量则询问）
  │
  ↓ 确定数量 + 方向后，选择模板：
  │
  ├─ 需要标签页+面板融合（外圆角） → left / right / top-tabs-template
  │
  └─ 需要胶囊切换按钮
       ├─ 2 个按钮
       │    ├─ 水平 → pill-toggle-h-template.lua
       │    └─ 垂直 → pill-toggle-v-template.lua
       └─ 3+ 个按钮
            ├─ 水平 → pill-toggle-multi-h-template.lua
            └─ 垂直 → pill-toggle-multi-v-template.lua
  │
  ↓ 按下方「集成步骤」提取核心逻辑到用户代码
```

## 集成步骤

模板分为**核心逻辑**和**演示脚手架**两部分：

| 部分 | 包含内容 | 集成时 |
|------|---------|--------|
| 核心逻辑 | 配置项、布局计算、绘制函数、点击处理 | 提取到用户代码中 |
| 演示脚手架 | `Start()`、`HandleNanoVGRender()`、`nvgCreate`、事件订阅 | 不需要，用户项目已有 |

1. 读取对应模板完整内容，学习绘制方法
2. 提取**配置项**（颜色、尺寸、标签定义）放到用户代码的变量区
3. 提取**绘制函数**（`drawPillToggle` / `drawTabs` / `drawTabPanel`）放到用户的绘制流程中
4. 提取**点击处理**（`handlePillClick` / 命中检测逻辑）放到用户的输入处理中
5. 根据用户界面的实际坐标、容器尺寸调整参数

不要整个文件复制为独立入口，不要复制演示脚手架部分（`Start`、`nvgCreate`、事件订阅）。

## 一、外圆角文件夹标签页

将选中 Tab 与 Panel 画成**一个统一路径**，交界处用凹弧实现外圆角效果。

### 模板选择

| Tab 位置 | 模板文件 | 文字方向 |
|---------|----------|----------|
| 左侧竖向 | `left-tabs-template.lua` | 竖排 |
| 右侧竖向 | `right-tabs-template.lua` | 竖排 |
| 顶部横向 | `top-tabs-template.lua` | 横排 |
| 底部横向 | 基于 top-tabs-template 做 Y 镜像 | 横排 |

### 不要外圆角？

搜索模板中的「不要凹弧」注释，把 `nvgBezierTo` 换成两步 `nvgLineTo` 即可。

### 凹弧公式（核心）

固定参数：`R` = 凹弧半径（4-8），`K = 0.5523`（固定值）。控制点拉向角落 = 凹形，拉离角落 = 凸形。

## 二、Pill Toggle 胶囊切换按钮

胶囊切换按钮，选中胶囊覆盖对应段 + 一个圆弧半径的溢出。

### 模板选择

| 按钮数 | 方向 | 模板文件 |
|--------|------|----------|
| 2 个 | 水平 | `pill-toggle-h-template.lua` |
| 2 个 | 垂直 | `pill-toggle-v-template.lua` |
| 3+ 个 | 水平 | `pill-toggle-multi-h-template.lua` |
| 3+ 个 | 垂直 | `pill-toggle-multi-v-template.lua` |

2 按钮和多按钮模板配置项相同，区别在于布局公式：

- **2 按钮**：`selW = pillW/2 + pillR`（左右二分，覆盖超出中线 = 一个圆）
- **多按钮**：`segW = pillW/N`，`selW = segW + pillR`（等分段 + 一个半径溢出，边缘钳位）

### 层级结构

1. 底层：暗色背景胶囊（track）
2. 上层：彩色选中胶囊（半透明填充 + 描边）
3. 文字：选中侧彩色，未选中侧灰色
