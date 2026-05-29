-- ============================================================
-- Pill Toggle 水平多按钮切换模板（NanoVG）
-- 支持 2 个及以上选项，选中胶囊滑动到对应位置
-- 选中宽度 = 每段宽度 + 一个圆弧半径，边缘自动钳位
-- ============================================================
-- 按可配置项注释修改即可使用。

-- ======================== 可配置项 ========================

-- 标签定义（id / 显示文字 / 选中颜色 RGB），数量不限
local tabs = {
    { id = "a", label = "选项A", color = {80, 200, 120} },
    { id = "b", label = "选项B", color = {200, 160, 80} },
    { id = "c", label = "选项C", color = {100, 160, 220} },
}

local PILL_W_RATIO  = 0.7    -- 胶囊宽度占容器比例（0.5-1.0）
local PILL_H        = 30     -- 胶囊高度（像素）
local PILL_Y        = 40     -- 胶囊顶部 Y 坐标
local FONT_SIZE     = 13     -- 字体大小
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

--- 计算胶囊布局
-- @param containerX  容器左边界
-- @param containerW  容器宽度
-- @return pillX, pillW, pillR, segW, selW
local function calcLayout(containerX, containerW)
    local N = #tabs
    local pillW = math.floor(containerW * PILL_W_RATIO)
    local pillR = PILL_H * 0.5
    local pillX = containerX + math.floor((containerW - pillW) * 0.5)
    local segW  = pillW / N
    -- 选中胶囊宽度 = 每段宽 + 一个圆弧半径
    local selW  = math.floor(segW + pillR)
    return pillX, pillW, pillR, segW, selW
end

--- 计算选中胶囊的 X 坐标（居中于对应段，边缘钳位）
local function getSelX(pillX, pillW, segW, selW, idx)
    local segCenter = pillX + (idx - 0.5) * segW
    local selX = math.floor(segCenter - selW * 0.5)
    -- 钳位：不超出 pill 边界
    selX = math.max(pillX, selX)
    selX = math.min(math.floor(pillX + pillW - selW), selX)
    return selX
end

--- 绘制 Pill Toggle（多按钮）
-- @param ctx        NanoVG context
-- @param containerX 容器左边界 X
-- @param containerW 容器宽度
function drawPillToggleMulti(ctx, containerX, containerW)
    local pillX, pillW, pillR, segW, selW = calcLayout(containerX, containerW)
    local idx = activeIndex()

    -- 1) 底层：暗色背景胶囊（track）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, pillX, PILL_Y, pillW, PILL_H, pillR)
    nvgFillColor(ctx, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4]))
    nvgFill(ctx)

    -- 2) 上层：彩色胶囊覆盖选中段
    local sel = activeConfig()
    local c = sel.color
    local selX = getSelX(pillX, pillW, segW, selW, idx)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, selX, PILL_Y, selW, PILL_H, pillR)
    nvgFillColor(ctx, nvgRGBA(c[1], c[2], c[3], SEL_FILL_A))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(c[1], c[2], c[3], SEL_STROKE_A))
    nvgStrokeWidth(ctx, 1.0)
    nvgStroke(ctx)

    -- 3) 文字（每个按钮居中于自己的等分段）
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, FONT_SIZE)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local midY = PILL_Y + PILL_H * 0.5
    for i, tab in ipairs(tabs) do
        local cx = pillX + (i - 0.5) * segW
        if tab.id == activeTab then
            nvgFillColor(ctx, nvgRGBA(tab.color[1], tab.color[2], tab.color[3], SEL_TEXT_A))
        else
            nvgFillColor(ctx, nvgRGBA(UNSEL_TEXT[1], UNSEL_TEXT[2], UNSEL_TEXT[3], UNSEL_TEXT[4]))
        end
        nvgText(ctx, cx, midY, tab.label, nil)
    end
end

--- 处理点击，返回 true 表示命中
-- @param tx, ty     点击坐标
-- @param containerX 容器左边界 X
-- @param containerW 容器宽度
function handlePillClickMulti(tx, ty, containerX, containerW)
    local pillX, pillW, _, segW = calcLayout(containerX, containerW)
    if tx >= pillX and tx <= pillX + pillW and ty >= PILL_Y and ty <= PILL_Y + PILL_H then
        local idx = math.floor((tx - pillX) / segW) + 1
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

    drawPillToggleMulti(vg, 0, screenW)

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
    handlePillClickMulti(x, y, 0, screenW)
end

function HandleTouchBegin(eventType, eventData)
    local x = eventData["X"]:GetInt() / graphics:GetDPR()
    local y = eventData["Y"]:GetInt() / graphics:GetDPR()
    handlePillClickMulti(x, y, 0, screenW)
end
