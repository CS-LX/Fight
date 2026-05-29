-- ============================================================
-- Pill Toggle 水平切换模板（NanoVG）
-- 两个选项的胶囊切换按钮，选中侧超出中线一个圆弧半径
-- ============================================================
-- 按可配置项标记修改即可使用。

-- ======================== 可配置项 ========================

-- 标签定义（id / 显示文字 / 选中颜色 RGB）
local tabs = {
    { id = "left",  label = "选项A", color = {80, 200, 120} },
    { id = "right", label = "选项B", color = {200, 160, 80} },
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

--- 计算胶囊布局
-- @param containerX  容器左边界
-- @param containerW  容器宽度
-- @return pillX, pillW, pillR, selW
local function calcLayout(containerX, containerW)
    local pillW = math.floor(containerW * PILL_W_RATIO)
    local pillR = PILL_H * 0.5
    local pillX = containerX + math.floor((containerW - pillW) * 0.5)
    -- 选中胶囊宽度 = 半宽 + 一个圆弧半径（覆盖超出中线 = 一个圆）
    local selW  = math.floor(pillW * 0.5 + pillR)
    return pillX, pillW, pillR, selW
end

--- 绘制 Pill Toggle
-- @param ctx       NanoVG context
-- @param containerX 容器左边界 X
-- @param containerW 容器宽度
function drawPillToggle(ctx, containerX, containerW)
    local pillX, pillW, pillR, selW = calcLayout(containerX, containerW)

    -- 1) 底层：暗色背景胶囊（track）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, pillX, PILL_Y, pillW, PILL_H, pillR)
    nvgFillColor(ctx, nvgRGBA(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4]))
    nvgFill(ctx)

    -- 2) 上层：彩色胶囊覆盖选中侧
    local sel = activeConfig()
    local c = sel.color
    local selX
    if activeTab == tabs[1].id then
        selX = pillX
    else
        selX = pillX + pillW - selW
    end
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, selX, PILL_Y, selW, PILL_H, pillR)
    nvgFillColor(ctx, nvgRGBA(c[1], c[2], c[3], SEL_FILL_A))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(c[1], c[2], c[3], SEL_STROKE_A))
    nvgStrokeWidth(ctx, 1.0)
    nvgStroke(ctx)

    -- 3) 文字（各自在所属区域内居中）
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, FONT_SIZE)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local midY  = PILL_Y + PILL_H * 0.5
    local unselW = pillW - selW

    for i, tab in ipairs(tabs) do
        local cx
        if activeTab == tabs[1].id then
            -- tabs[1] 选中在左
            cx = (i == 1) and (selX + selW * 0.5) or (selX + selW + unselW * 0.5)
        else
            -- tabs[2] 选中在右
            cx = (i == 2) and (selX + selW * 0.5) or (pillX + unselW * 0.5)
        end
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
function handlePillClick(tx, ty, containerX, containerW)
    local pillX, pillW = calcLayout(containerX, containerW)
    if tx >= pillX and tx <= pillX + pillW and ty >= PILL_Y and ty <= PILL_Y + PILL_H then
        local half = pillW * 0.5
        local newTab = (tx - pillX < half) and tabs[1].id or tabs[2].id
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

    -- 传入容器区域（这里示例用全屏宽度居中）
    drawPillToggle(vg, 0, screenW)

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
    handlePillClick(x, y, 0, screenW)
end

function HandleTouchBegin(eventType, eventData)
    local x = eventData["X"]:GetInt() / graphics:GetDPR()
    local y = eventData["Y"]:GetInt() / graphics:GetDPR()
    handlePillClick(x, y, 0, screenW)
end
