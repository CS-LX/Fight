# 全面战争模拟器 + 自定义角色系统 — 设计方案

## 概述

将现有 3D 竞技场对战游戏升级为类似"全面战争模拟器(TABS)"的游戏，核心特色是**玩家可完全自定义角色**（外观、行为树、属性），同时提供**开发者角色制作器**加速内容生产。

---

## 一、系统架构总览

```
游戏主界面
  ├── 战斗场景 (现有Battle)
  ├── 角色部署编辑器 (放置+开战, TABS核心)
  └── 角色制作器 (3大面板)
        ├── 外观编辑器 (调色/缩放)
        ├── 行为树节点编辑器 (连线画布)
        └── 属性配置面板 (滑条/数值)
```

---

## 二、模块分解

### 模块 1: 外观自定义系统

**现状**: 仅有 1 个 Spine 资源(Wisdel)
**方案**: 通过颜色叠加 + 缩放变形实现差异化外观

| 自定义维度 | 技术手段 |
|-----------|---------|
| 角色染色 | `spineWidget:SetColor(r, g, b, a)` |
| 体型缩放 | `SetScale(scaleX, scaleY)` |
| 动画速率 | `spineWidget:SetAnimSpeed(rate)` |
| 特效光环 | NanoVG 叠加发光圈 |
| 名字标签 | UI.Label 绝对定位跟随 |

**数据结构扩展** (`CharModule.art` 新增字段):
```lua
tint = { r=1.0, g=0.8, b=0.6 },  -- RGB染色
scaleX = 1.0, scaleY = 1.0,       -- 体型
animSpeed = 1.0,                   -- 动画速率
glowColor = nil,                   -- 光环颜色
```

**UI**: ColorPicker + Slider x3 + Toggle + 实时Spine预览

**文件**: `scripts/ui/AppearanceEditor.lua` (~200行)

---

### 模块 2: 行为树节点编辑器 (核心)

类似 Blender 节点编辑器的无限画布。

#### 2.1 画布组件 (BTCanvas)

Widget:Extend 自定义组件:
- 无限画布: 滚轮缩放(0.3x~3.0x), 右键平移
- 节点: NanoVG 绘制的矩形卡片 (非Yoga子元素)
- 连线: 三次贝塞尔曲线
- 交互: 拖拽节点、拖拽端口连线、点击选中、双击添加

#### 2.2 节点类型

| 分类 | 节点 | 颜色 | 端口 |
|------|------|------|------|
| 组合 | Sequence (序列) | 蓝 | 1入+N出 |
| 组合 | Priority (优先级) | 青 | 1入+N出 |
| 组合 | ActivePriority (抢占优先级) | 深青 | 1入+N出 |
| 组合 | Random (随机) | 橙 | 1入+N出 |
| 装饰 | Invert / AlwaysFail / AlwaysSucceed | 紫 | 1入+1出 |
| 叶子 | Task (条件/动作) | 绿 | 1入+0出 |

#### 2.3 预制叶子节点 (Task 库)

**条件**: HasEnemy, InAttackRange, HPLow, HPHigh, EnemyCountHigh, AllyNearby
**动作**: Chase, Attack, Patrol, Flee, Guard, HealAlly(未来)

#### 2.4 交互流程

1. 双击画布 → 弹窗选择节点类型 → 添加
2. 从输出端口拖到输入端口 → 建立连线
3. 点击节点 → Inspector面板显示属性
4. Task节点: Dropdown选择预制行为
5. [保存] → JSON写入文件
6. [测试] → 编译BT → 替换AI → 开战

#### 2.5 数据格式

```json
{
  "name": "我的战士AI",
  "rootId": "node_1",
  "nodes": [
    { "id": "node_1", "type": "ActivePriority", "name": "根节点", "x": 200, "y": 300 },
    { "id": "node_2", "type": "Sequence", "name": "攻击分支", "x": 450, "y": 150 },
    { "id": "node_3", "type": "Task", "name": "HasEnemy", "x": 700, "y": 100 }
  ],
  "edges": [
    { "from": "node_1", "to": "node_2", "order": 1 },
    { "from": "node_2", "to": "node_3", "order": 1 }
  ]
}
```

#### 2.6 编译器 (JSON -> 运行时BT)

递归遍历节点图, Task通过name查找预注册函数, 组合节点递归构造children.

**文件**:
- `scripts/ui/components/BTCanvas.lua` (~400行)
- `scripts/ui/components/BTNodePalette.lua` (~80行)
- `scripts/ui/components/BTInspector.lua` (~120行)
- `scripts/ui/BehaviourTreeEditor.lua` (~150行)
- `scripts/logic/BTCompiler.lua` (~100行)
- `scripts/logic/BTTaskLibrary.lua` (~150行)

---

### 模块 3: 属性配置面板

基于现有 CharCustomUI 扩展:

| 属性 | 范围 |
|------|------|
| 移动速度 | 0.5 ~ 8.0 |
| 最大生命 | 20 ~ 500 |
| 攻击伤害 | 1 ~ 100 |
| 攻击范围 | 0.5 ~ 5.0 |
| 攻击冷却 | 0.1 ~ 3.0 |
| 护甲值(新) | 0 ~ 50 |
| 暴击率(新) | 0% ~ 50% |

**文件**: 扩展 `scripts/CharCustomUI.lua`

---

### 模块 4: 开发者角色制作器 (整合)

```
┌─────────────────────────────────────────────────────────┐
│ [返回] 角色制作器: [新建] [加载] [保存] [导出] [测试战斗] │
├─────────────────────────────────────────────────────────┤
│ [外观]  [行为树]  [属性]  ← 标签切换                      │
├─────────────────────────────────────────────────────────┤
│ (当前标签内容, 占满剩余空间)                               │
├─────────────────────────────────────────────────────────┤
│ [Spine预览]  摘要: HP=100 SPD=2.5 DMG=10 AI=自定义树     │
└─────────────────────────────────────────────────────────┘
```

**文件**: `scripts/ui/CharacterMaker.lua` (~200行)

---

## 三、游戏流程 (玩家视角)

```
主菜单
  ├─ [快速战斗] → 预设角色直接开战
  ├─ [角色工坊] → 角色制作器 (外观/行为树/属性)
  └─ [部署战斗] → TABS核心玩法
        ├─ 左侧: 角色卡牌列表 (预设+自定义)
        ├─ 中间: 战场俯视, 拖拽放置
        └─ [开战\!] → 双方AI自动对打
```

---

## 四、实施阶段

### Phase 1: 行为树编辑器核心 (最高优先)
- BTCanvas — 画布渲染、缩放平移、节点绘制、连线
- BTNodePalette — 节点类型列表
- BTInspector — 属性面板
- BehaviourTreeEditor — 三栏布局
- BTTaskLibrary — 预制Task注册
- 交互: 添加节点、拖拽移动、连线、删除

### Phase 2: 编译与集成
- BTCompiler — JSON → BT对象
- 修改 AI.lua — 热替换支持
- JSON 保存/加载
- "测试战斗"按钮

### Phase 3: 外观编辑器
- AppearanceEditor — 染色/缩放/光环 UI
- 修改 CharRender — 应用 tint/scale/glow
- 实时Spine预览

### Phase 4: 角色制作器整合
- CharacterMaker — Tab容器+工具栏
- 整合三个子面板
- 完善保存/加载

### Phase 5: 部署战斗 (TABS玩法)
- DeploymentEditor — 俯视地图，拖放角色
- 角色卡牌列表
- 双方独立配置阵容

---

## 五、关键文件清单

| 文件 | 类型 | ~行数 |
|------|------|------|
| `scripts/ui/components/BTCanvas.lua` | 新建 | 400 |
| `scripts/ui/components/BTNodePalette.lua` | 新建 | 80 |
| `scripts/ui/components/BTInspector.lua` | 新建 | 120 |
| `scripts/ui/BehaviourTreeEditor.lua` | 新建 | 150 |
| `scripts/logic/BTCompiler.lua` | 新建 | 100 |
| `scripts/logic/BTTaskLibrary.lua` | 新建 | 150 |
| `scripts/ui/AppearanceEditor.lua` | 新建 | 200 |
| `scripts/ui/CharacterMaker.lua` | 新建 | 200 |
| `scripts/ui/DeploymentEditor.lua` | 新建 | 250 |
| `scripts/logic/AI.lua` | 修改 | +30 |
| `scripts/render/CharRender.lua` | 修改 | +40 |
| `scripts/characters/CharModule.lua` | 修改 | +20 |

---

## 六、技术风险与对策

| 风险 | 对策 |
|------|------|
| NanoVG画布节点多时性能 | 视口裁剪+限制最大50节点 |
| 仅1个Spine资源 | 先做染色+缩放; 后续引入更多资源 |
| 编辑器交互复杂 | 先做双击添加+连线, 再加面板拖拽 |
| WASM文件不持久 | 支持JSON导出备份 |

---

## 七、验证方式

每Phase完成后 `build` 并预览:
- Phase 1: 画布可缩放平移, 节点可拖拽, 连线可绘制
- Phase 2: 编辑→保存→开战, AI按编辑的树行动
- Phase 3: 改染色→预览实时变色
- Phase 4: 完整流程(建角色→配属性→编AI→测试)
- Phase 5: 拖放部署→开战

---

## 八、建议首次实现

先做 **Phase 1 + Phase 2**(行为树编辑器+编译集成), 这是最核心的差异化功能。完成后即可体验"可视化编辑AI→立即测试"的核心循环。
