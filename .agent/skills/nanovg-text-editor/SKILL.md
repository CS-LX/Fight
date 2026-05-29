---
name: nanovg-text-editor
description: |
  NanoVG 文本编辑器组件开发指南，涵盖光标定位、文本选区、滚动面板、交互按钮等核心模式。
  Use when users need to (1) 用 NanoVG 构建代码编辑器或文本编辑器, (2) 实现 NanoVG 文本光标定位,
  (3) 实现文本选区/选中高亮, (4) 构建可滚动的日志面板/控制台, (5) 在 NanoVG 中实现可点击按钮和 hover 状态,
  (6) 处理 NanoVG 中的 UTF-8 多字节文本测量, (7) 用户提到 text editor / code editor / IDE / 编辑器。
---

# NanoVG 文本编辑器模式

在 NanoVG 中构建文本编辑器/代码编辑器时，以下模式解决了最常见的陷阱。

## 规则 #1: 光标定位 — 必须逐字符测量 🔴

**不要用等宽假设** `cursorCol * charWidth`，中文/混合字体会导致光标偏移。

```lua
--- 逐字符测量，返回 positions[col] = 第 col 列左边缘像素 X
function GetLineCharPositions(row)
    local lineText = lines[row] or ""
    local positions = { [1] = 0 }
    if #lineText == 0 then return positions end

    nvgFontFaceId(vg, fontMono)
    nvgFontSize(vg, FONT_SIZE)

    local x = 0
    local i = 1
    local len = #lineText
    while i <= len do
        -- UTF-8 多字节检测
        local byte = lineText:byte(i)
        local charLen = 1
        if byte >= 0xF0 then charLen = 4
        elseif byte >= 0xE0 then charLen = 3
        elseif byte >= 0xC0 then charLen = 2
        end
        charLen = math.min(charLen, len - i + 1)

        local ch = lineText:sub(i, i + charLen - 1)
        x = x + nvgTextBounds(vg, 0, 0, ch)

        for j = 1, charLen do
            positions[i + j] = x
        end
        i = i + charLen
    end
    return positions
end

--- 像素 X → 最近列号（用于鼠标点击定位）
function GetColFromPixelX(row, pixelX)
    local positions = GetLineCharPositions(row)
    local lineLen = #(lines[row] or "")
    local bestCol, bestDist = 1, math.abs(pixelX)
    for col = 2, lineLen + 1 do
        if positions[col] then
            local dist = math.abs(pixelX - positions[col])
            if dist < bestDist then bestDist = dist; bestCol = col end
        end
    end
    return bestCol
end
```

**缓存策略**: 用 `lineWidthCache[row]` 缓存结果，编辑时 `InvalidateAllCaches(fromRow)` 清除。

## 规则 #2: 选区管理 — 锚点模型

```lua
local selAnchorRow, selAnchorCol = nil, nil  -- 选区起点
-- cursorRow, cursorCol 作为选区终点

function HasSelection()
    return selAnchorRow ~= nil and selAnchorCol ~= nil
        and (selAnchorRow ~= cursorRow or selAnchorCol ~= cursorCol)
end

function GetSelectionRange()  -- 返回有序的 r1,c1,r2,c2
    if not HasSelection() then return nil end
    local r1, c1, r2, c2 = selAnchorRow, selAnchorCol, cursorRow, cursorCol
    if r1 > r2 or (r1 == r2 and c1 > c2) then
        r1, c1, r2, c2 = r2, c2, r1, c1
    end
    return r1, c1, r2, c2
end

function StartSelection()  -- Shift 按下时调用
    if selAnchorRow == nil then
        selAnchorRow, selAnchorCol = cursorRow, cursorCol
    end
end
```

**选区渲染**: 在文字下方、用 `positions[]` 计算像素范围，行末额外延伸 8px 表示换行符。

## 规则 #3: 选区高亮渲染

```lua
-- 在逐行循环中，文字之前绘制选区背景
if hasSelection and row >= sr1 and row <= sr2 then
    local positions = GetLineCharPositions(row)
    local selStart, selEnd
    if row == sr1 and row == sr2 then
        selStart, selEnd = sc1, sc2
    elseif row == sr1 then
        selStart, selEnd = sc1, #lineText + 1
    elseif row == sr2 then
        selStart, selEnd = 1, sc2
    else
        selStart, selEnd = 1, #lineText + 1
    end
    local px1 = positions[selStart] or 0
    local px2 = positions[selEnd] or 0
    if selEnd > #lineText and row < sr2 then px2 = px2 + 8 end
    if px2 > px1 then
        nvgBeginPath(vg)
        nvgRect(vg, codeX + px1 - scrollX, lineY, px2 - px1, LINE_HEIGHT)
        nvgFillColor(vg, nvgRGBA(62, 68, 81, 180))
        nvgFill(vg)
    end
end
```

## 规则 #4: 可滚动面板 — 区域判定 + 裁剪

```lua
-- 1) 渲染时裁剪
nvgSave(vg)
nvgIntersectScissor(vg, panelX, contentY, panelW, contentH)
-- 渲染内容 ...
nvgRestore(vg)

-- 2) 滚动条
local totalH = #items * ITEM_H
if totalH > contentH then
    local thumbH = math.max(20, contentH * (contentH / totalH))
    local thumbY = contentY + (scrollY / (totalH - contentH)) * (contentH - thumbH)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX + 2, thumbY, barW - 4, thumbH, 3)
    nvgFillColor(vg, nvgRGBA(120, 125, 135, 160))
    nvgFill(vg)
end

-- 3) HandleMouseWheel 区域判定
local dpr = graphics:GetDPR()
local my = input.mousePosition.y / dpr
if my >= panelY then
    scrollY = math.max(0, math.min(scrollY - wheel * ITEM_H * 3, totalH - contentH))
    return
end
```

## 规则 #5: 交互按钮 — DPR 坐标转换 + Hover

```lua
-- HandleUpdate: 更新 hover
local dpr = graphics:GetDPR()
local mx, my = input.mousePosition.x / dpr, input.mousePosition.y / dpr
btnHover = (mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH)

-- HandleMouseDown: 检测点击（必须判断 MOUSEB_LEFT）
if button ~= MOUSEB_LEFT then return end
local dpr = graphics:GetDPR()
local mx, my = input.mousePosition.x / dpr, input.mousePosition.y / dpr
if mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH then
    OnButtonClick(); return
end
```

**关键**: 所有鼠标坐标必须 `/dpr` 转换为逻辑像素后再做碰撞检测。

## 规则 #6: Print 劫持 — 内置控制台

```lua
local _originalPrint = print
local consoleLines = {}

function HookPrint()
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        consoleLines[#consoleLines + 1] = { text = table.concat(parts, "\t"), type = "normal" }
        _originalPrint(...)  -- 保留引擎日志
    end
end
```

## 规则 #7: 剪贴板 — 仅用内部变量

```lua
-- ❌ 禁止: ui.clipboardText（WASM 环境崩溃: copyToClipboard undefined）
-- ❌ 禁止: ui.useSystemClipboard = true
-- ✅ 正确: 纯内部变量
local internalClipboard = ""
function ClipboardCopy() internalClipboard = GetSelectedText() end
```

## 检查清单

- [ ] 光标 X 用 `nvgTextBounds` 逐字符测量？（非 `col * charWidth`）
- [ ] UTF-8 多字节字符正确检测？（0xC0/0xE0/0xF0 前缀）
- [ ] 鼠标坐标除以 `dpr` 后再做碰撞检测？
- [ ] 可滚动区域用 `nvgIntersectScissor` 裁剪？
- [ ] 剪贴板用内部变量而非 `ui.clipboardText`？
