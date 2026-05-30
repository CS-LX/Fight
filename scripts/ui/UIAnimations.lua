-- ============================================================================
-- ui/UIAnimations.lua - 基于 flux 的 UI 动效工具库
-- ============================================================================
-- 使用 flux tween 驱动 UI widget 的 style 属性动画
-- 原理：flux 补间普通 Lua table → onupdate 中 SetStyle 同步到 widget

local flux = require("libs.flux")

local M = {}

-- flux 动画组（UI 专用，暂停游戏时仍可播放）
local uiGroup = flux.group()

--- 每帧更新（必须在 HandleUpdate 中调用）
---@param dt number
function M.Update(dt)
    uiGroup:update(dt)
end

-- ============================================================================
-- 面板/卡片动画
-- ============================================================================

--- 从顶部滑入 + 淡入
---@param widget Widget
---@param opts? { duration?: number, distance?: number, delay?: number, ease?: string }
function M.SlideInFromTop(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.4
    local dist = opts.distance or 40
    local delay = opts.delay or 0
    local ease = opts.ease or "backout"

    local proxy = { y = -dist, opacity = 0 }
    widget:SetStyle({ translateY = -dist, opacity = 0 })

    uiGroup:to(proxy, dur, { y = 0, opacity = 1 })
        :ease(ease)
        :delay(delay)
        :onupdate(function()
            widget:SetStyle({ translateY = proxy.y, opacity = proxy.opacity })
        end)
end

--- 从底部滑入 + 淡入
---@param widget Widget
---@param opts? { duration?: number, distance?: number, delay?: number, ease?: string }
function M.SlideInFromBottom(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.4
    local dist = opts.distance or 40
    local delay = opts.delay or 0
    local ease = opts.ease or "backout"

    local proxy = { y = dist, opacity = 0 }
    widget:SetStyle({ translateY = dist, opacity = 0 })

    uiGroup:to(proxy, dur, { y = 0, opacity = 1 })
        :ease(ease)
        :delay(delay)
        :onupdate(function()
            widget:SetStyle({ translateY = proxy.y, opacity = proxy.opacity })
        end)
end

--- 从左侧滑入 + 淡入
---@param widget Widget
---@param opts? { duration?: number, distance?: number, delay?: number, ease?: string }
function M.SlideInFromLeft(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.4
    local dist = opts.distance or 60
    local delay = opts.delay or 0
    local ease = opts.ease or "backout"

    local proxy = { x = -dist, opacity = 0 }
    widget:SetStyle({ translateX = -dist, opacity = 0 })

    uiGroup:to(proxy, dur, { x = 0, opacity = 1 })
        :ease(ease)
        :delay(delay)
        :onupdate(function()
            widget:SetStyle({ translateX = proxy.x, opacity = proxy.opacity })
        end)
end

--- 从右侧滑入 + 淡入
---@param widget Widget
---@param opts? { duration?: number, distance?: number, delay?: number, ease?: string }
function M.SlideInFromRight(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.4
    local dist = opts.distance or 60
    local delay = opts.delay or 0
    local ease = opts.ease or "backout"

    local proxy = { x = dist, opacity = 0 }
    widget:SetStyle({ translateX = dist, opacity = 0 })

    uiGroup:to(proxy, dur, { x = 0, opacity = 1 })
        :ease(ease)
        :delay(delay)
        :onupdate(function()
            widget:SetStyle({ translateX = proxy.x, opacity = proxy.opacity })
        end)
end

--- 弹入效果（缩放 + 淡入，带 back 回弹）
---@param widget Widget
---@param opts? { duration?: number, delay?: number, ease?: string }
function M.PopIn(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.35
    local delay = opts.delay or 0
    local ease = opts.ease or "backout"

    local proxy = { scale = 0.3, opacity = 0 }
    widget:SetStyle({ scale = 0.3, opacity = 0 })

    uiGroup:to(proxy, dur, { scale = 1.0, opacity = 1 })
        :ease(ease)
        :delay(delay)
        :onupdate(function()
            widget:SetStyle({ scale = proxy.scale, opacity = proxy.opacity })
        end)
end

--- 弹出效果（缩放 + 淡出）
---@param widget Widget
---@param opts? { duration?: number, delay?: number, onComplete?: function }
function M.PopOut(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.25
    local delay = opts.delay or 0

    local proxy = { scale = 1.0, opacity = 1 }

    uiGroup:to(proxy, dur, { scale = 0.3, opacity = 0 })
        :ease("backin")
        :delay(delay)
        :onupdate(function()
            widget:SetStyle({ scale = proxy.scale, opacity = proxy.opacity })
        end)
        :oncomplete(function()
            if opts.onComplete then opts.onComplete() end
        end)
end

--- 淡入
---@param widget Widget
---@param opts? { duration?: number, delay?: number }
function M.FadeIn(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.3
    local delay = opts.delay or 0

    local proxy = { opacity = 0 }
    widget:SetStyle({ opacity = 0 })

    uiGroup:to(proxy, dur, { opacity = 1 })
        :ease("sineout")
        :delay(delay)
        :onupdate(function()
            widget:SetStyle({ opacity = proxy.opacity })
        end)
end

-- ============================================================================
-- 交错入场
-- ============================================================================

--- 一组 widget 按序播放同一动画，每个间隔 stagger 时间
---@param widgets Widget[]
---@param animFn function 动画函数（如 M.PopIn）
---@param opts? { stagger?: number, baseDelay?: number }
function M.Stagger(widgets, animFn, opts)
    opts = opts or {}
    local stagger = opts.stagger or 0.06
    local baseDelay = opts.baseDelay or 0
    for i, widget in ipairs(widgets) do
        animFn(widget, { delay = baseDelay + (i - 1) * stagger })
    end
end

-- ============================================================================
-- 数字滚动
-- ============================================================================

--- 数字从 from 滚动到 to，每帧更新 Label 文本
---@param label Widget Label widget
---@param from number 起始值
---@param to number 目标值
---@param opts? { duration?: number, prefix?: string, suffix?: string, ease?: string, onComplete?: function }
function M.CountUp(label, from, to, opts)
    opts = opts or {}
    local dur = opts.duration or 0.6
    local prefix = opts.prefix or ""
    local suffix = opts.suffix or ""
    local ease = opts.ease or "cubicout"

    if from == to then
        label:SetText(prefix .. tostring(to) .. suffix)
        return
    end

    local proxy = { value = from }

    uiGroup:to(proxy, dur, { value = to })
        :ease(ease)
        :onupdate(function()
            label:SetText(prefix .. tostring(math.floor(proxy.value)) .. suffix)
        end)
        :oncomplete(function()
            label:SetText(prefix .. tostring(to) .. suffix)
            if opts.onComplete then opts.onComplete() end
        end)
end

-- ============================================================================
-- 特殊效果
-- ============================================================================

--- 抖动效果（错误/受击反馈）
---@param widget Widget
---@param opts? { duration?: number, intensity?: number }
function M.Shake(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.3
    local intensity = opts.intensity or 4

    local proxy = { x = intensity }
    widget:SetStyle({ translateX = intensity })

    -- 用 elastic 快速衰减回零
    uiGroup:to(proxy, dur, { x = 0 })
        :ease("elasticout")
        :onupdate(function()
            widget:SetStyle({ translateX = proxy.x })
        end)
end

--- 脉冲呼吸（循环缩放）— 注意：flux 不支持原生循环，用 oncomplete 递归
---@param widget Widget
---@param opts? { duration?: number, minScale?: number, maxScale?: number }
---@return table handle 返回控制句柄 { stop: function }
function M.Pulse(widget, opts)
    opts = opts or {}
    local dur = opts.duration or 0.8
    local minS = opts.minScale or 0.95
    local maxS = opts.maxScale or 1.05

    local handle = { running = true }
    local proxy = { scale = 1.0 }

    local function animateUp()
        if not handle.running then return end
        uiGroup:to(proxy, dur * 0.5, { scale = maxS })
            :ease("sineinout")
            :onupdate(function()
                widget:SetStyle({ scale = proxy.scale })
            end)
            :oncomplete(function()
                if not handle.running then return end
                uiGroup:to(proxy, dur * 0.5, { scale = minS })
                    :ease("sineinout")
                    :onupdate(function()
                        widget:SetStyle({ scale = proxy.scale })
                    end)
                    :oncomplete(animateUp)
            end)
    end

    animateUp()

    function handle.stop()
        handle.running = false
        widget:SetStyle({ scale = 1.0 })
    end

    return handle
end

return M
