-- ============================================================
-- NanoVG 外圆角文件夹标签页 — 右侧竖向模板
-- ============================================================
-- 布局示意：
--
--                    ┌──────┐
--                    │ Tab1 │
--   ┌────────────────┤      │
--   │                ├──────┤
--   │     Panel     ╶┤ Tab2 │  ← 选中，与 Panel 融合
--   │                ├──────┤
--   └────────────────┤ Tab3 │
--                    │      │
--                    └──────┘
--
---@diagnostic disable: undefined-global

-- ═══ TODO: 颜色 ════════════════════════════════════════════
local PANEL_BG    = { 25, 28, 40, 250 }    -- 面板 = 选中 Tab 背景色（必须一致）
local TAB_NORMAL  = { 16, 18, 26, 220 }
local BORDER_CLR  = { 55, 60, 80, 200 }
local TAB_ACCENT  = { 80, 200, 255, 220 }  -- 选中 Tab 右侧高亮条
local C_WHITE     = { 210, 215, 225 }
local C_GRAY      = { 120, 125, 140 }

-- ═══ TODO: 布局 ════════════════════════════════════════════
local TAB_W       = 38
local TAB_ITEM_H  = 36
local TAB_GAP     = 2
local PANEL_W     = 240
local PANEL_H     = 200
local BORDER_W    = 1
local TAB_R       = 6           -- Tab 右侧圆角
local PANEL_R     = 6
local RC          = 5           -- 凹弧半径（4-8）
local k           = 0.5523

-- ═══ TODO: Tab 定义 ════════════════════════════════════════
local TABS = {
    { label = "标签1" },
    { label = "标签2" },
    { label = "标签3" },
}

local activeTab = 1

-- 竖排文字
local function drawVerticalText(ctx, label, cx, ty, h, fontSize, r, g, b, a)
    local chars = {}
    for _, c in utf8.codes(label) do chars[#chars + 1] = utf8.char(c) end
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, fontSize)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(r, g, b, a))
    local charH = h / (#chars + 1)
    for ci, ch in ipairs(chars) do
        nvgText(ctx, cx, ty + ci * charH, ch, nil)
    end
end

-- ═══ 核心渲染 ══════════════════════════════════════════════
local function renderFolderTabs(ctx, screenW, screenH)
    local tabsTotalH = #TABS * TAB_ITEM_H + (#TABS - 1) * TAB_GAP
    local totalW = PANEL_W + TAB_W
    local totalX = (screenW - totalW) / 2
    local totalY = (screenH - math.max(PANEL_H, tabsTotalH)) / 2

    local panelX    = totalX                -- 面板在左
    local panelY    = totalY
    local pRight    = panelX + PANEL_W      -- 面板右边缘 = Tab 左边缘
    local tabX      = pRight                -- Tab 从面板右边缘开始
    local tabStartY = panelY + (PANEL_H - tabsTotalH) / 2

    -- ═══ 第 1 步：未选中 Tab ═══
    for i, tab in ipairs(TABS) do
        if i ~= activeTab then
            local ty = tabStartY + (i - 1) * (TAB_ITEM_H + TAB_GAP)
            nvgBeginPath(ctx)
            -- 右侧两角圆角，左侧直角
            nvgRoundedRectVarying(ctx, tabX, ty, TAB_W, TAB_ITEM_H, 0, TAB_R, TAB_R, 0)
            nvgFillColor(ctx, nvgRGBA(TAB_NORMAL[1], TAB_NORMAL[2], TAB_NORMAL[3], TAB_NORMAL[4]))
            nvgFill(ctx)
            nvgStrokeWidth(ctx, BORDER_W)
            nvgStrokeColor(ctx, nvgRGBA(BORDER_CLR[1], BORDER_CLR[2], BORDER_CLR[3], 120))
            nvgStroke(ctx)
            drawVerticalText(ctx, tab.label, tabX + TAB_W / 2, ty, TAB_ITEM_H,
                12, C_GRAY[1], C_GRAY[2], C_GRAY[3], 180)
        end
    end

    -- ═══ 第 2 步：统一路径 Panel + 选中 Tab ═══
    local aTy = tabStartY + (activeTab - 1) * (TAB_ITEM_H + TAB_GAP)
    local aBy = aTy + TAB_ITEM_H
    local pBottom = panelY + PANEL_H
    local tabRight = tabX + TAB_W

    nvgBeginPath(ctx)

    -- A. 面板左上圆角
    nvgMoveTo(ctx, panelX + PANEL_R, panelY)
    nvgArcTo(ctx, panelX, panelY, panelX, panelY + PANEL_R, PANEL_R)

    -- B. 面板左边向下 → 左下圆角
    nvgLineTo(ctx, panelX, pBottom - PANEL_R)
    nvgArcTo(ctx, panelX, pBottom, panelX + PANEL_R, pBottom, PANEL_R)

    -- C. 面板底边 → 右下圆角
    nvgLineTo(ctx, pRight - PANEL_R, pBottom)
    nvgArcTo(ctx, pRight, pBottom, pRight, pBottom - PANEL_R, PANEL_R)

    -- D. 面板右边向上 → 到下凹弧
    nvgLineTo(ctx, pRight, aBy + RC)

    -- E. ★ 下凹弧：从面板右边 (pRight, aBy+RC) 向右到 Tab 下边 (pRight+RC, aBy)
    -- 【不要凹弧？换成 nvgLineTo(ctx, pRight, aBy) 再 nvgLineTo(ctx, pRight + RC, aBy)】
    nvgBezierTo(ctx,
        pRight,              aBy + RC * (1-k),  -- CP1
        pRight + RC * (1-k), aBy,               -- CP2
        pRight + RC,         aBy)                -- 终点

    -- F. Tab 下边 → 右下圆角
    nvgLineTo(ctx, tabRight - TAB_R, aBy)
    nvgArcTo(ctx, tabRight, aBy, tabRight, aBy - TAB_R, TAB_R)

    -- G. Tab 右边向上 → 右上圆角
    nvgLineTo(ctx, tabRight, aTy + TAB_R)
    nvgArcTo(ctx, tabRight, aTy, tabRight - TAB_R, aTy, TAB_R)

    -- H. Tab 上边 → 到上凹弧
    nvgLineTo(ctx, pRight + RC, aTy)

    -- I. ★ 上凹弧：从 Tab 上边 (pRight+RC, aTy) 向左到面板右边 (pRight, aTy-RC)
    -- 【不要凹弧？换成 nvgLineTo(ctx, pRight, aTy) 再 nvgLineTo(ctx, pRight, aTy - RC)】
    nvgBezierTo(ctx,
        pRight + RC * (1-k), aTy,               -- CP1
        pRight,              aTy - RC * (1-k),   -- CP2
        pRight,              aTy - RC)            -- 终点

    -- J. 面板右边继续向上 → 右上圆角
    nvgLineTo(ctx, pRight, panelY + PANEL_R)
    nvgArcTo(ctx, pRight, panelY, pRight - PANEL_R, panelY, PANEL_R)

    nvgClosePath(ctx)

    nvgFillColor(ctx, nvgRGBA(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], PANEL_BG[4]))
    nvgFill(ctx)
    nvgStrokeWidth(ctx, BORDER_W)
    nvgStrokeColor(ctx, nvgRGBA(BORDER_CLR[1], BORDER_CLR[2], BORDER_CLR[3], BORDER_CLR[4]))
    nvgStroke(ctx)

    -- ═══ 第 3 步：选中 Tab 装饰 ═══
    -- 右侧高亮条
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, tabRight - 5, aTy + 6, 3, TAB_ITEM_H - 12, 1.5)
    nvgFillColor(ctx, nvgRGBA(TAB_ACCENT[1], TAB_ACCENT[2], TAB_ACCENT[3], TAB_ACCENT[4]))
    nvgFill(ctx)

    drawVerticalText(ctx, TABS[activeTab].label, tabX + TAB_W / 2, aTy, TAB_ITEM_H,
        13, C_WHITE[1], C_WHITE[2], C_WHITE[3], 255)

    -- ═══ TODO: 面板内容 ═══
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(C_GRAY[1], C_GRAY[2], C_GRAY[3], 200))
    nvgText(ctx, panelX + PANEL_W / 2, panelY + PANEL_H / 2,
        TABS[activeTab].label .. " 的内容区域", nil)
end

-- ═══ 集成示例 ══════════════════════════════════════════════
local vg = nil

function Start()
    vg = nvgCreate(1)
    nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
end

function HandleNanoVGRender(eventType, eventData)
    local w = graphics:GetWidth() / graphics:GetDPR()
    local h = graphics:GetHeight() / graphics:GetDPR()
    nvgBeginFrame(vg, w, h, graphics:GetDPR())
    renderFolderTabs(vg, w, h)
    nvgEndFrame(vg)
end
