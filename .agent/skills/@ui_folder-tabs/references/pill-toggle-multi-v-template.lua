-- ============================================================
-- Pill Toggle 垂直多按钮切换模板（NanoVG）
-- 支持 2 个及以上选项，选中胶囊滑动到对应位置，文字逐字竖排
-- 选中高度 = 每段高度 + 一个圆弧半径，边缘自动钳位
-- ============================================================
-- 按可配置项注释修改即可使用。

-- ======================== 可配置项 ========================

-- 标签定义（id / 显示文字 / 选中颜色 RGB），数量不限
local tabs = {
    { id = "a", label = "选项A", color = {80, 200, 120} },
    { id = "b", label = "选项B", color = {200, 160, 80} },
    { id = "c", label = "选项C", color = {100, 160, 220} },
}

local PILL_H_RATIO  = 0.5    -- 胶囊高度占容器高度比例（0.3-0.8）
local PILL_W        = 30     -- 胶囊宽度（像素）
local PILL_X        = 40     -- 胶囊左边界 X 坐标
local FONT_SIZE     = 13     -- 字体大小
local CHAR_SPACING  = 16     -- 竖排文字每字间距（像素）
local BG_COLOR      = {35, 38, 48, 180}   -- 底色（暗色 track）
local UNSEL_TEXT    = {130, 132, 150, 160} -- 未选中文字颜色
local SEL_FILL_A    = 60     -- 选中胶囊填充透明度
local SEL_STROKE_A  = 130    -- 选中胶囊描边透明度
local SEL_TEXT_A    = 240    -- 选中文字透明度

-- ======================== 内部状态 ========================

local activeTab = tabs[1].id
local vg = nil
local screenW, screenH = 0, 0

-- ======================== 核心函数 ========================

--- 获取当前选中 tab 的索引
local function activeIndex()
    for i, tab in ipairs(tabs) do
        if tab.id == activeTab then return i end
    end
    return 1
end

--- 获取当前选中 tab 的配置
local function activeConfig()
    return tabs[activeIndex()]
end

--- 将字符串拆分为单个 UTF-8 字符
local function utf8Chars(s)
    local chars = {}
    local i = 1
    local len = #s
    while i <= len do
        local b = string.byte(s, i)
        local charLen = 1
        if b >= 0xF0 then charLen = 4
        elseif b >= 0xE0 then charLen = 3
        elseif b >= 0xC0 then charLen = 2
        end
        chars[#chars + 1] = string.sub(s, i, i + charLen - 1)
        i = i + charLen
    end
    return chars
end

--- 竖排绘制文字（逐字居中）
local function drawVerticalText(ctx, cx, centerY, text, spacing)
    local chars = utf8Chars(text)
    local totalH = (#chars - 1) * spacing
    local startY = centerY - totalH * 0.5
    for i, ch in ipairs(chars) do
        nvgText(ctx, cx, startY + (i - 1) * spacing, ch, nil)
    end
end

--- 计算胶囊布局（垂直方向）
-- @param containerY  容器顶部边界
-- @param containerH  容器高度
-- @return pillY, pillH, pillR, segH, selH
local function calcLayout(containerY, containerH)
    local N = #tabs
    local pillH = math.floor(containerH * PILL_H_RATIO)
    local pillR = PILL_W * 0.5
    local pillY = containerY + math.floor((containerH - pillH) * 0.5)
    local segH  = pillH / N
    -- 选中胶囊高度 = 每段高 + 一个圆弧半径
    local selH  = math.floor(segH + pillR)
    return pillY, pillH, pillR, segH, selH
end

--- 计算选中胶囊的 Y 坐标（居中于对应段，边缘钳位）
local function getSelY(pillY, pillH, segH, selH, idx)
    local segCenter = pillY + (idx - 0.5) * segH
    local selY = math.floor(segCenter - selH * 0.5)
    selY = math.max(pillY, selY)
    selY = math.min(math.floor(pillY + pillH - selH), selY)
    return selY
end

--- 绘制 Pill Toggle（垂直多按钮）
-- @param ctx        NanoVG context
-- @param containerY 容器顶部 Y
-- @param containerH 容器高度
function drawPillToggleMultiV(ctx, containerY, containerH)
    local pillY, pillH, pillR, segH, selH = calcLayout(containerY, containerH)
    local idx = activeIndex()

    -- 1) 底层：暗色背景胶囊（track）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, PILL_X, pillY, PILL_W, pillH, pillR)
    nvgFillColor(ctx, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4]))
    nvgFill(ctx)

    -- 2) 上层：彩色胶囊覆盖选中段
    local sel = activeConfig()
    local c = sel.color
    local selY = getSelY(pillY, pillH, segH, selH, idx)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, PILL_X, selY, PILL_W, selH, pillR)
    nvgFillColor(ctx, nvgRGBA(c[1], c[2], c[3], SEL_FILL_A))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(c[1], c[2], c[3], SEL_STROKE_A))
    nvgStrokeWidth(ctx, 1.0)
    nvgStroke(ctx)

    -- 3) 竖排文字（每个按钮居中于自己的等分段）
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, FONT_SIZE)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local midX = PILL_X + PILL_W * 0.5
    for i, tab in ipairs(tabs) do
        local cy = pillY + (i - 0.5) * segH
        if tab.id == activeTab then
            nvgFillColor(ctx, nvgRGBA(tab.color[1], tab.color[2], tab.color[3], SEL_TEXT_A))
        else
            nvgFillColor(ctx, nvgRGBA(UNSEL_TEXT[1], UNSEL_TEXT[2], UNSEL_TEXT[3], UNSEL_TEXT[4]))
        end
        drawVerticalText(ctx, midX, cy, tab.label, CHAR_SPACING)
    end
end

--- 处理点击（垂直方向），返回 true 表示命中
-- @param tx, ty     点击坐标
-- @param containerY 容器顶部 Y
-- @param containerH 容器高度
function handlePillClickMultiV(tx, ty, containerY, containerH)
    local pillY, pillH, _, segH = calcLayout(containerY, containerH)
    if tx >= PILL_X and tx <= PILL_X + PILL_W and ty >= pillY and ty <= pillY + pillH then
        local idx = math.floor((ty - pillY) / segH) + 1
        idx = math.max(1, math.min(#tabs, idx))
        local newTab = tabs[idx].id
        if activeTab ~= newTab then
            activeTab = newTab
            -- 在这里添加切换回调，例如播放音效
        end
        return true
    end
    return false
end

-- ======================== UrhoX 生命周期（演示用） ========================

function Start()
    vg = nvgCreate(1)
    nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    screenW = screenW / dpr
    screenH = screenH / dpr

    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
end

function HandleNanoVGRender()
    nvgBeginFrame(vg, screenW, screenH, graphics:GetDPR())

    drawPillToggleMultiV(vg, 0, screenH)

    -- 根据 activeTab 绘制对应面板内容
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
    nvgText(vg, screenW * 0.5, screenH * 0.5, "当前: " .. activeConfig().label, nil)

    nvgEndFrame(vg)
end

function HandleMouseDown(eventType, eventData)
    local x = eventData["X"]:GetInt() / graphics:GetDPR()
    local y = eventData["Y"]:GetInt() / graphics:GetDPR()
    handlePillClickMultiV(x, y, 0, screenH)
end

function HandleTouchBegin(eventType, eventData)
    local x = eventData["X"]:GetInt() / graphics:GetDPR()
    local y = eventData["Y"]:GetInt() / graphics:GetDPR()
    handlePillClickMultiV(x, y, 0, screenH)
end
