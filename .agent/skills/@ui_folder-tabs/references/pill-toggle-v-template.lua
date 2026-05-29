-- ============================================================
-- Pill Toggle 垂直切换模板（NanoVG）
-- 两个选项的竖向胶囊切换按钮，文字垂直排列
-- 选中侧超出中线一个圆弧半径（与水平版同理，轴向互换）
-- ============================================================
-- 按可配置项标记修改即可使用。

-- ======================== 可配置项 ========================

-- 标签定义（id / 显示文字 / 选中颜色 RGB）
-- 注意：文字会逐字竖排，建议用短文字（2-4字）
local tabs = {
    { id = "top",    label = "选项A", color = {80, 200, 120} },
    { id = "bottom", label = "选项B", color = {200, 160, 80} },
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

local activeTab = tabs[1].id  -- 当前选中
local vg = nil                -- NanoVG context
local screenW, screenH = 0, 0

-- ======================== 核心函数 ========================

--- 获取当前选中 tab 的索引（1 或 2）
local function activeIndex()
    return activeTab == tabs[1].id and 1 or 2
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
local function drawVerticalText(ctx, cx, topY, text, spacing)
    local chars = utf8Chars(text)
    local totalH = (#chars - 1) * spacing
    local startY = topY - totalH * 0.5
    for i, ch in ipairs(chars) do
        nvgText(ctx, cx, startY + (i - 1) * spacing, ch, nil)
    end
end

--- 计算胶囊布局（垂直方向）
-- @param containerY  容器顶部边界
-- @param containerH  容器高度
-- @return pillY, pillH, pillR, selH
local function calcLayout(containerY, containerH)
    local pillH = math.floor(containerH * PILL_H_RATIO)
    local pillR = PILL_W * 0.5  -- 半径基于宽度（竖向胶囊的圆弧在上下）
    local pillY = containerY + math.floor((containerH - pillH) * 0.5)
    -- 选中胶囊高度 = 半高 + 一个圆弧半径（覆盖超出中线 = 一个圆）
    local selH  = math.floor(pillH * 0.5 + pillR)
    return pillY, pillH, pillR, selH
end

--- 绘制 Pill Toggle（垂直方向）
-- @param ctx        NanoVG context
-- @param containerY 容器顶部 Y
-- @param containerH 容器高度
function drawPillToggleV(ctx, containerY, containerH)
    local pillY, pillH, pillR, selH = calcLayout(containerY, containerH)

    -- 1) 底层：暗色背景胶囊（track）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, PILL_X, pillY, PILL_W, pillH, pillR)
    nvgFillColor(ctx, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4]))
    nvgFill(ctx)

    -- 2) 上层：彩色胶囊覆盖选中侧
    local sel = activeConfig()
    local c = sel.color
    local selY
    if activeTab == tabs[1].id then
        selY = pillY  -- 选中上半
    else
        selY = pillY + pillH - selH  -- 选中下半
    end
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, PILL_X, selY, PILL_W, selH, pillR)
    nvgFillColor(ctx, nvgRGBA(c[1], c[2], c[3], SEL_FILL_A))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(c[1], c[2], c[3], SEL_STROKE_A))
    nvgStrokeWidth(ctx, 1.0)
    nvgStroke(ctx)

    -- 3) 竖排文字（各自在所属区域内居中）
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, FONT_SIZE)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local midX   = PILL_X + PILL_W * 0.5
    local unselH = pillH - selH

    for i, tab in ipairs(tabs) do
        local cy
        if activeTab == tabs[1].id then
            -- tabs[1] 选中在上
            cy = (i == 1) and (selY + selH * 0.5) or (selY + selH + unselH * 0.5)
        else
            -- tabs[2] 选中在下
            cy = (i == 2) and (selY + selH * 0.5) or (pillY + unselH * 0.5)
        end
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
function handlePillClickV(tx, ty, containerY, containerH)
    local pillY, pillH = calcLayout(containerY, containerH)
    if tx >= PILL_X and tx <= PILL_X + PILL_W and ty >= pillY and ty <= pillY + pillH then
        local half = pillH * 0.5
        local newTab = (ty - pillY < half) and tabs[1].id or tabs[2].id
        if activeTab ~= newTab then
            activeTab = newTab
            -- 在这里添加切换回调，例如播放音效
        end
        return true
    end
    return false
end

-- ======================== UrhoX 生命周期 ========================

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

    -- 传入容器区域（这里示例用全屏高度居中）
    drawPillToggleV(vg, 0, screenH)

    -- 根据 activeTab 绘制对应面板内容
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
    local label = activeConfig().label
    nvgText(vg, screenW * 0.5, screenH * 0.5, "当前: " .. label, nil)

    nvgEndFrame(vg)
end

function HandleMouseDown(eventType, eventData)
    local x = eventData["X"]:GetInt() / graphics:GetDPR()
    local y = eventData["Y"]:GetInt() / graphics:GetDPR()
    handlePillClickV(x, y, 0, screenH)
end

function HandleTouchBegin(eventType, eventData)
    local x = eventData["X"]:GetInt() / graphics:GetDPR()
    local y = eventData["Y"]:GetInt() / graphics:GetDPR()
    handlePillClickV(x, y, 0, screenH)
end
