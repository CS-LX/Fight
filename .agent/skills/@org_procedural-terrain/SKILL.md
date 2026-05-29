---
name: procedural-terrain
description: >
  程序化地形/地图/地牢生成算法完整指南（Lua / 任意2D瓦片地图项目）。
  当用户需要以下内容时触发：瓦片地图生成、洞穴/地牢随机生成、
  随机游走地图、Perlin 噪声地形、元胞自动机、BSP 树分割、
  洪水填充连通性验证、可破坏地形、地形随机化、程序化生成算法选型、
  procedural generation、dungeon generation、cave generation、
  terrain map algorithm、2D tile map generation。
---

# Procedural Terrain Generation

完整指南见 `references/guide.md`（1142 行，含所有算法实现代码）。

## 算法选型速查

| 需求 | 推荐算法 | 指南章节 |
|------|---------|---------|
| 自然洞穴、矿脉 | 随机游走 (Random Walk) | 第 2 章 |
| 自然地形高度图 | Perlin 噪声 | 第 3 章 |
| 洞穴/地牢生成 | 元胞自动机 (CA) | 第 4 章 |
| 房间+走廊地牢 | BSP 树 | 第 5 章 |
| 区域连通验证 | 洪水填充 | 第 6 章 |
| 混合真实感地形 | 混合策略 | 第 7 章 |
| 破坏/挖掘效果 | 可破坏地形 | 第 9 章 |
| 性能/大地图 | 分块加载 | 第 10 章 |

## 使用方式

遇到程序化地形需求时：

1. 用上表选择算法
2. 读取 `references/guide.md` 对应章节获取完整实现
3. 按指南中的代码模板实现，根据项目需求调整参数

> 指南代码为 Lua，但算法逻辑适用于任何语言。
