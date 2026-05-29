-- ============================================================
-- NanoVG 外圆角文件夹标签页 — 完整自包含模板
-- ============================================================
-- 按 TODO 标记修改颜色、布局、Tab 定义和面板内容。
-- 核心技巧：选中 Tab 与 Panel 画成一个统一路径(nvgBeginPath)，
-- 交界处用 nvgBezierTo 凹弧实现外圆角(round-out / inverse corner)效果。
--
-- 布局示意（左侧竖向标签页）：
--
--    ┌──────┐
--    │ Tab1 │╮  ← 凹弧
--    ├──────┤├────────────────────┐
--    │ Tab2 ││   Panel Content   │ ← Tab2 = 选中，与 Panel 融合
--    ├──────┤├────────────────────┘
--    │ Tab3 │╯  ← 凹弧
--    └──────┘
--
---@diagnostic disable: undefined-global

-- ═══════════════════════════════════════════════════════════
-- TODO: 颜色配置（按你的项目风格调整）
-- ═══════════════════════════════════════════════════════════
local PANEL_BG    = { 25, 28, 40, 250 }    -- 面板背景色 = 选中 Tab 背景色（必须一致才能融合）
local TAB_NORMAL  = { 16, 18, 26, 220 }    -- 未选中 Tab 背景色（应比 PANEL_BG 更暗）
local BORDER_CLR  = { 55, 60, 80, 200 }    -- 边框颜色
local TAB_ACCENT  = { 80, 200, 255, 220 }  -- 选中 Tab 左侧高亮条
local C_WHITE     = { 210, 215, 225 }      -- 选中文字颜色
local C_GRAY      = { 120, 125, 140 }      -- 未选中文字颜色

-- ═══════════════════════════════════════════════════════════
-- TODO: 布局参数（按你的 UI 尺寸调整）
-- ═══════════════════════════════════════════════════════════
local TAB_W       = 38          -- Tab 宽度
local TAB_ITEM_H  = 36          -- 每个 Tab 高度
local TAB_GAP     = 2           -- Tab 之间间距
local PANEL_W     = 240         -- 面板宽度
local PANEL_H     = 200         -- 面板高度
local BORDER_W    = 1           -- 边框粗细
local TAB_R       = 6           -- Tab 左侧圆角半径
local PANEL_R     = 6           -- 面板四角圆角半径
local RC          = 5           -- 凹弧半径（4-8 之间，值越大弧越明显）
local k           = 0.5523      -- Bezier 圆弧近似因子（固定值，不要改！）

-- ═══════════════════════════════════════════════════════════
-- TODO: Tab 定义（改成你需要的标签）
-- ═══════════════════════════════════════════════════════════
local TABS = {
    { label = "标签1" },
    { label = "标签2" },
    { label = "标签3" },
}

local activeTab = 1  -- 当前选中的 Tab 索引（Lua 从 1 开始）

-- ═══════════════════════════════════════════════════════════
-- 竖排文字绘制（中文竖排，每个字单独绘制）
-- ═══════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════
-- 核心渲染函数
-- ctx      : NanoVG 上下文
-- screenW  : 屏幕宽度
-- screenH  : 屏幕高度
-- ═══════════════════════════════════════════════════════════
local function renderFolderTabs(ctx, screenW, screenH)
    -- ─── 计算整体布局（居中） ─────────────────────────
    local tabsTotalH = #TABS * TAB_ITEM_H + (#TABS - 1) * TAB_GAP
    local totalW = TAB_W + PANEL_W
    local totalX = (screenW - totalW) / 2
    local totalY = (screenH - math.max(PANEL_H, tabsTotalH)) / 2

    local panelX    = totalX + TAB_W    -- 面板左边缘（紧接 Tab 右侧）
    local panelY    = totalY
    local tabX      = totalX            -- Tab 左边缘
    local tabStartY = panelY + (PANEL_H - tabsTotalH) / 2  -- Tab 垂直居中于面板

    -- ═══════════════════════════════════════════════════════
    -- 第 1 步：画未选中的 Tab（暗色，在面板后面）
    -- ═══════════════════════════════════════════════════════
    for i, tab in ipairs(TABS) do
        if i ~= activeTab then
            local ty = tabStartY + (i - 1) * (TAB_ITEM_H + TAB_GAP)
            nvgBeginPath(ctx)
            -- 只有左侧两个角有圆角，右侧两个角为直角（被面板遮住）
            nvgRoundedRectVarying(ctx, tabX, ty, TAB_W, TAB_ITEM_H, TAB_R, 0, 0, TAB_R)
            nvgFillColor(ctx, nvgRGBA(TAB_NORMAL[1], TAB_NORMAL[2], TAB_NORMAL[3], TAB_NORMAL[4]))
            nvgFill(ctx)
            nvgStrokeWidth(ctx, BORDER_W)
            nvgStrokeColor(ctx, nvgRGBA(BORDER_CLR[1], BORDER_CLR[2], BORDER_CLR[3], 120))
            nvgStroke(ctx)
            -- 竖排文字
            drawVerticalText(ctx, tab.label, tabX + TAB_W / 2, ty, TAB_ITEM_H,
                12, C_GRAY[1], C_GRAY[2], C_GRAY[3], 180)
        end
    end

    -- ═══════════════════════════════════════════════════════
    -- 第 2 步：统一路径 — Panel + 选中 Tab（外圆角核心）
    -- ═══════════════════════════════════════════════════════
    -- 选中 Tab 的上下边缘
    local aTy = tabStartY + (activeTab - 1) * (TAB_ITEM_H + TAB_GAP)  -- Tab 上边
    local aBy = aTy + TAB_ITEM_H                                       -- Tab 下边

    -- 面板角点
    local pRight  = panelX + PANEL_W
    local pBottom = panelY + PANEL_H

    -- ─── 构造统一路径（顺时针） ─────────────────────
    nvgBeginPath(ctx)

    -- A. 面板顶边：从右上角开始 → 左上圆角
    nvgMoveTo(ctx, pRight - PANEL_R, panelY)
    nvgLineTo(ctx, panelX + PANEL_R, panelY)
    nvgArcTo(ctx, panelX, panelY, panelX, panelY + PANEL_R, PANEL_R)

    -- B. 面板左边向下 → 到 Tab 上方凹弧起点
    nvgLineTo(ctx, panelX, aTy - RC)

    -- C. ★ 上凹弧（核心！）
    --    从 (panelX, aTy-RC) 凹进去到 (panelX-RC, aTy)
    --    控制点拉向角落 = 凹形
    -- 【不要凹弧？换成 nvgLineTo(ctx, panelX, aTy) 再 nvgLineTo(ctx, panelX - RC, aTy)】
    nvgBezierTo(ctx,
        panelX,              aTy - RC * (1 - k),  -- CP1
        panelX - RC * (1-k), aTy,                  -- CP2
        panelX - RC,         aTy)                   -- 终点

    -- D. Tab 上边 → 左上圆角
    nvgLineTo(ctx, tabX + TAB_R, aTy)
    nvgArcTo(ctx, tabX, aTy, tabX, aTy + TAB_R, TAB_R)

    -- E. Tab 左边向下 → 左下圆角
    nvgLineTo(ctx, tabX, aBy - TAB_R)
    nvgArcTo(ctx, tabX, aBy, tabX + TAB_R, aBy, TAB_R)

    -- F. Tab 下边 → 到凹弧起点
    nvgLineTo(ctx, panelX - RC, aBy)

    -- G. ★ 下凹弧（核心！）
    --    从 (panelX-RC, aBy) 凹回去到 (panelX, aBy+RC)
    -- 【不要凹弧？换成 nvgLineTo(ctx, panelX, aBy) 再 nvgLineTo(ctx, panelX, aBy + RC)】
    nvgBezierTo(ctx,
        panelX - RC * (1-k), aBy,                  -- CP1
        panelX,              aBy + RC * (1 - k),    -- CP2
        panelX,              aBy + RC)               -- 终点

    -- H. 面板左边继续向下 → 左下圆角
    nvgLineTo(ctx, panelX, pBottom - PANEL_R)
    nvgArcTo(ctx, panelX, pBottom, panelX + PANEL_R, pBottom, PANEL_R)

    -- I. 面板底边 → 右下圆角
    nvgLineTo(ctx, pRight - PANEL_R, pBottom)
    nvgArcTo(ctx, pRight, pBottom, pRight, pBottom - PANEL_R, PANEL_R)

    -- J. 面板右边向上 → 右上圆角
    nvgLineTo(ctx, pRight, panelY + PANEL_R)
    nvgArcTo(ctx, pRight, panelY, pRight - PANEL_R, panelY, PANEL_R)

    nvgClosePath(ctx)

    -- 填充 + 描边
    nvgFillColor(ctx, nvgRGBA(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], PANEL_BG[4]))
    nvgFill(ctx)
    nvgStrokeWidth(ctx, BORDER_W)
    nvgStrokeColor(ctx, nvgRGBA(BORDER_CLR[1], BORDER_CLR[2], BORDER_CLR[3], BORDER_CLR[4]))
    nvgStroke(ctx)

    -- ═══════════════════════════════════════════════════════
    -- 第 3 步：选中 Tab 装饰
    -- ═══════════════════════════════════════════════════════
    -- 左侧高亮色条
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, tabX + 2, aTy + 6, 3, TAB_ITEM_H - 12, 1.5)
    nvgFillColor(ctx, nvgRGBA(TAB_ACCENT[1], TAB_ACCENT[2], TAB_ACCENT[3], TAB_ACCENT[4]))
    nvgFill(ctx)

    -- 竖排文字（选中态用亮色）
    drawVerticalText(ctx, TABS[activeTab].label, tabX + TAB_W / 2, aTy, TAB_ITEM_H,
        13, C_WHITE[1], C_WHITE[2], C_WHITE[3], 255)

    -- ═══════════════════════════════════════════════════════
    -- TODO: 在这里绘制面板内容
    -- ═══════════════════════════════════════════════════════
    -- 面板内容区域：
    --   左上角 (panelX + BORDER_W + 8, panelY + BORDER_W + 8)
    --   宽度   PANEL_W - 16
    --   高度   PANEL_H - 16
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(C_GRAY[1], C_GRAY[2], C_GRAY[3], 200))
    nvgText(ctx, panelX + PANEL_W / 2, panelY + PANEL_H / 2,
        TABS[activeTab].label .. " 的内容区域", nil)
end

-- ═══════════════════════════════════════════════════════════
-- 以下是集成示例（展示如何在游戏中使用）
-- ═══════════════════════════════════════════════════════════

local vg = nil  -- NanoVG 上下文

function Start()
    -- 创建字体（只调用一次）
    vg = nvgCreate(1)
    nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    -- 订阅 NanoVG 渲染事件
    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
end

function HandleNanoVGRender(eventType, eventData)
    local w = graphics:GetWidth() / graphics:GetDPR()
    local h = graphics:GetHeight() / graphics:GetDPR()
    nvgBeginFrame(vg, w, h, graphics:GetDPR())

    renderFolderTabs(vg, w, h)

    nvgEndFrame(vg)
end

-- TODO: 添加 Tab 切换的点击处理
-- 在鼠标点击事件中，检测点击位置是否在各 Tab 区域内，
-- 若是则更新 activeTab 变量即可。
