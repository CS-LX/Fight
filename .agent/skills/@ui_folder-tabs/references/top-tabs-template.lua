-- ============================================================
-- NanoVG 外圆角文件夹标签页 — 顶部横向模板
-- ============================================================
-- 布局示意：
--
--   ┌──────┐ ┌──────┐ ┌──────┐
--   │ Tab1 │ │ Tab2 │ │ Tab3 │   ← Tab2 = 选中
--   └──────┘╭┘      └╮└──────┘
--           │        │
--           │ Panel  │
--           │        │
--           └────────┘
--
---@diagnostic disable: undefined-global

-- ═══ TODO: 颜色 ════════════════════════════════════════════
local PANEL_BG    = { 25, 28, 40, 250 }    -- 面板 = 选中 Tab 背景色（必须一致）
local TAB_NORMAL  = { 16, 18, 26, 220 }    -- 未选中 Tab（应更暗）
local BORDER_CLR  = { 55, 60, 80, 200 }
local TAB_ACCENT  = { 80, 200, 255, 220 }  -- 选中 Tab 底部高亮条
local C_WHITE     = { 210, 215, 225 }
local C_GRAY      = { 120, 125, 140 }

-- ═══ TODO: 布局 ════════════════════════════════════════════
local TAB_ITEM_W  = 70          -- 每个 Tab 宽度
local TAB_H       = 30          -- Tab 高度
local TAB_GAP     = 2           -- Tab 水平间距
local PANEL_W     = 280         -- 面板宽度
local PANEL_H     = 200         -- 面板高度
local BORDER_W    = 1
local TAB_R       = 6           -- Tab 顶部圆角
local PANEL_R     = 6           -- 面板圆角
local RC          = 5           -- 凹弧半径（4-8）
local k           = 0.5523      -- 固定 Bezier 因子

-- ═══ TODO: Tab 定义 ════════════════════════════════════════
local TABS = {
    { label = "标签1" },
    { label = "标签2" },
    { label = "标签3" },
}

local activeTab = 1

-- ═══ 核心渲染 ══════════════════════════════════════════════
local function renderFolderTabs(ctx, screenW, screenH)
    local tabsTotalW = #TABS * TAB_ITEM_W + (#TABS - 1) * TAB_GAP
    local totalW = math.max(PANEL_W, tabsTotalW)
    local totalH = TAB_H + PANEL_H
    local totalX = (screenW - totalW) / 2
    local totalY = (screenH - totalH) / 2

    local panelX = totalX + (totalW - PANEL_W) / 2
    local panelY = totalY + TAB_H       -- 面板在 Tab 下方
    local tabStartX = panelX + (PANEL_W - tabsTotalW) / 2  -- Tab 横向居中于面板
    local tabY = totalY                  -- Tab 顶边

    -- ═══ 第 1 步：未选中 Tab ═══
    for i, tab in ipairs(TABS) do
        if i ~= activeTab then
            local tx = tabStartX + (i - 1) * (TAB_ITEM_W + TAB_GAP)
            nvgBeginPath(ctx)
            -- 顶部两角圆角，底部直角
            nvgRoundedRectVarying(ctx, tx, tabY, TAB_ITEM_W, TAB_H, TAB_R, TAB_R, 0, 0)
            nvgFillColor(ctx, nvgRGBA(TAB_NORMAL[1], TAB_NORMAL[2], TAB_NORMAL[3], TAB_NORMAL[4]))
            nvgFill(ctx)
            nvgStrokeWidth(ctx, BORDER_W)
            nvgStrokeColor(ctx, nvgRGBA(BORDER_CLR[1], BORDER_CLR[2], BORDER_CLR[3], 120))
            nvgStroke(ctx)
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 13)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(C_GRAY[1], C_GRAY[2], C_GRAY[3], 180))
            nvgText(ctx, tx + TAB_ITEM_W / 2, tabY + TAB_H / 2, tab.label, nil)
        end
    end

    -- ═══ 第 2 步：统一路径 Panel + 选中 Tab ═══
    local aLx = tabStartX + (activeTab - 1) * (TAB_ITEM_W + TAB_GAP)  -- 选中 Tab 左边
    local aRx = aLx + TAB_ITEM_W                                       -- 选中 Tab 右边

    local pRight  = panelX + PANEL_W
    local pBottom = panelY + PANEL_H

    nvgBeginPath(ctx)

    -- A. 面板底边左起 → 左下圆角
    nvgMoveTo(ctx, panelX + PANEL_R, pBottom)
    nvgArcTo(ctx, panelX, pBottom, panelX, pBottom - PANEL_R, PANEL_R)

    -- B. 面板左边向上 → 左上圆角
    nvgLineTo(ctx, panelX, panelY + PANEL_R)
    nvgArcTo(ctx, panelX, panelY, panelX + PANEL_R, panelY, PANEL_R)

    -- C. 面板顶边向右 → 到左凹弧
    nvgLineTo(ctx, aLx - RC, panelY)

    -- D. ★ 左凹弧：从面板顶 (aLx-RC, panelY) 向上到 Tab 左边 (aLx, panelY-RC)
    -- 【不要凹弧？把这个 BezierTo 换成 nvgLineTo(ctx, aLx, panelY) 再 nvgLineTo(ctx, aLx, panelY - RC)】
    nvgBezierTo(ctx,
        aLx - RC * (1-k), panelY,               -- CP1
        aLx,              panelY - RC * (1-k),   -- CP2
        aLx,              panelY - RC)            -- 终点

    -- E. Tab 左边向上 → 左上圆角
    nvgLineTo(ctx, aLx, tabY + TAB_R)
    nvgArcTo(ctx, aLx, tabY, aLx + TAB_R, tabY, TAB_R)

    -- F. Tab 顶边 → 右上圆角
    nvgLineTo(ctx, aRx - TAB_R, tabY)
    nvgArcTo(ctx, aRx, tabY, aRx, tabY + TAB_R, TAB_R)

    -- G. Tab 右边向下 → 到右凹弧
    nvgLineTo(ctx, aRx, panelY - RC)

    -- H. ★ 右凹弧：从 Tab 右边 (aRx, panelY-RC) 向下到面板顶 (aRx+RC, panelY)
    -- 【不要凹弧？把这个 BezierTo 换成 nvgLineTo(ctx, aRx, panelY) 再 nvgLineTo(ctx, aRx + RC, panelY)】
    nvgBezierTo(ctx,
        aRx,              panelY - RC * (1-k),   -- CP1
        aRx + RC * (1-k), panelY,                -- CP2
        aRx + RC,         panelY)                 -- 终点

    -- I. 面板顶边继续向右 → 右上圆角
    nvgLineTo(ctx, pRight - PANEL_R, panelY)
    nvgArcTo(ctx, pRight, panelY, pRight, panelY + PANEL_R, PANEL_R)

    -- J. 面板右边向下 → 右下圆角
    nvgLineTo(ctx, pRight, pBottom - PANEL_R)
    nvgArcTo(ctx, pRight, pBottom, pRight - PANEL_R, pBottom, PANEL_R)

    nvgClosePath(ctx)

    nvgFillColor(ctx, nvgRGBA(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], PANEL_BG[4]))
    nvgFill(ctx)
    nvgStrokeWidth(ctx, BORDER_W)
    nvgStrokeColor(ctx, nvgRGBA(BORDER_CLR[1], BORDER_CLR[2], BORDER_CLR[3], BORDER_CLR[4]))
    nvgStroke(ctx)

    -- ═══ 第 3 步：选中 Tab 装饰 ═══
    -- 底部高亮条
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, aLx + 8, panelY - 2, TAB_ITEM_W - 16, 3, 1.5)
    nvgFillColor(ctx, nvgRGBA(TAB_ACCENT[1], TAB_ACCENT[2], TAB_ACCENT[3], TAB_ACCENT[4]))
    nvgFill(ctx)

    -- 选中文字
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(C_WHITE[1], C_WHITE[2], C_WHITE[3], 255))
    nvgText(ctx, aLx + TAB_ITEM_W / 2, tabY + TAB_H / 2, TABS[activeTab].label, nil)

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
