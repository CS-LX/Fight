-- ============================================================================
-- ui/AppearanceEditor.lua - 外观编辑器（Phase 3）
-- ============================================================================
-- 职责：提供角色外观调整 UI（染色、缩放、动画速率、光环）+ 实时 Spine 预览
-- 数据写回 CharRegistry，CharRender 会在下次战斗自动读取

local UI = require("urhox-libs/UI")
local CharModule = require("characters.CharModule")
local CharRegistry = require("characters.CharRegistry")

local M = {}

-- 状态
local visible_ = false
---@type Widget|nil
local root_ = nil
---@type Widget|nil
local previewSpine_ = nil

-- 当前编辑的模块 ID
local editModuleId_ = nil

-- 控件引用
local sliderR_ = nil
local sliderG_ = nil
local sliderB_ = nil
local sliderScaleX_ = nil
local sliderScaleY_ = nil
local sliderAnimSpeed_ = nil
local glowToggle_ = nil
local sliderGlowR_ = nil
local sliderGlowG_ = nil
local sliderGlowB_ = nil
local previewColorLabel_ = nil

-- 回调
local onSave_ = nil
local onClose_ = nil

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取当前滑块值组成的 art 扩展数据
local function ReadArtFromUI()
    return {
        tint = {
            r = sliderR_:GetValue() / 100,
            g = sliderG_:GetValue() / 100,
            b = sliderB_:GetValue() / 100,
        },
        scaleX = sliderScaleX_:GetValue() / 100,
        scaleY = sliderScaleY_:GetValue() / 100,
        animSpeed = sliderAnimSpeed_:GetValue() / 100,
        glowColor = glowToggle_ and glowToggle_.checked and {
            r = sliderGlowR_:GetValue() / 100,
            g = sliderGlowG_:GetValue() / 100,
            b = sliderGlowB_:GetValue() / 100,
        } or nil,
    }
end

--- 更新 Spine 预览控件的颜色
local function UpdatePreview()
    if not previewSpine_ then return end
    local r = sliderR_:GetValue() / 100
    local g = sliderG_:GetValue() / 100
    local b = sliderB_:GetValue() / 100
    previewSpine_:SetColor(r, g, b, 1.0)

    -- 更新颜色预览标签
    if previewColorLabel_ then
        local hexR = string.format("%02X", math.floor(r * 255))
        local hexG = string.format("%02X", math.floor(g * 255))
        local hexB = string.format("%02X", math.floor(b * 255))
        previewColorLabel_:SetText("#" .. hexR .. hexG .. hexB)
    end

    -- 更新动画速率
    local speed = sliderAnimSpeed_:GetValue() / 100
    previewSpine_:SetTimeScale(speed)
end

--- 创建分组标题
local function SectionLabel(text)
    return UI.Label {
        text = text,
        fontSize = 13,
        fontColor = { 150, 200, 255, 255 },
        marginTop = 10,
    }
end

--- 创建属性标签
local function PropLabel(text)
    return UI.Label {
        text = text,
        fontSize = 11,
        fontColor = { 180, 180, 180, 255 },
        marginTop = 2,
    }
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 打开外观编辑器
---@param opts { moduleId: string, onSave: function|nil, onClose: function|nil }
function M.Open(opts)
    if visible_ then M.Close() end

    editModuleId_ = opts.moduleId or "custom_default"
    onSave_ = opts.onSave
    onClose_ = opts.onClose

    -- 读取当前角色数据
    local mod = CharRegistry.Get(editModuleId_)
    if not mod then
        mod = CharModule.CreateDefault(editModuleId_, "Unknown")
    end
    local art = mod.art

    -- 初始值（百分制 → 滑块值）
    local initR = math.floor((art.tint and art.tint.r or 1.0) * 100)
    local initG = math.floor((art.tint and art.tint.g or 1.0) * 100)
    local initB = math.floor((art.tint and art.tint.b or 1.0) * 100)
    local initSX = math.floor((art.scaleX or 1.0) * 100)
    local initSY = math.floor((art.scaleY or 1.0) * 100)
    local initAnimSpeed = math.floor((art.animSpeed or 1.0) * 100)
    local hasGlow = art.glowColor ~= nil
    local initGR = hasGlow and math.floor(art.glowColor.r * 100) or 100
    local initGG = hasGlow and math.floor(art.glowColor.g * 100) or 80
    local initGB = hasGlow and math.floor(art.glowColor.b * 100) or 20

    -- 创建 Spine 实时预览
    previewSpine_ = UI.Spine {
        src = art.spineSrc,
        animation = art.anims.idle,
        loop = true,
        width = 200,
        height = 240,
        pma = art.pma,
    }

    -- 颜色预览标签
    previewColorLabel_ = UI.Label {
        text = "#FFFFFF",
        fontSize = 11,
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
        width = "100%",
    }

    -- 染色滑块
    local onColorChange = function() UpdatePreview() end

    sliderR_ = UI.Slider { value = initR, min = 0, max = 100, step = 1, width = "100%", onChange = onColorChange }
    sliderG_ = UI.Slider { value = initG, min = 0, max = 100, step = 1, width = "100%", onChange = onColorChange }
    sliderB_ = UI.Slider { value = initB, min = 0, max = 100, step = 1, width = "100%", onChange = onColorChange }

    -- 缩放滑块
    sliderScaleX_ = UI.Slider { value = initSX, min = 50, max = 200, step = 5, width = "100%" }
    sliderScaleY_ = UI.Slider { value = initSY, min = 50, max = 200, step = 5, width = "100%" }

    -- 动画速率
    sliderAnimSpeed_ = UI.Slider {
        value = initAnimSpeed, min = 20, max = 300, step = 5, width = "100%",
        onChange = function() UpdatePreview() end,
    }

    -- 光环开关 (用 Button 模拟 toggle)
    local glowEnabled = hasGlow
    local glowBtnText = hasGlow and "ON" or "OFF"
    glowToggle_ = { checked = hasGlow }

    local glowBtn = UI.Button {
        text = glowBtnText,
        width = 60, height = 28,
        variant = hasGlow and "primary" or "default",
        onClick = function(self)
            glowToggle_.checked = not glowToggle_.checked
            self:SetText(glowToggle_.checked and "ON" or "OFF")
        end,
    }

    sliderGlowR_ = UI.Slider { value = initGR, min = 0, max = 100, step = 5, width = "100%" }
    sliderGlowG_ = UI.Slider { value = initGG, min = 0, max = 100, step = 5, width = "100%" }
    sliderGlowB_ = UI.Slider { value = initGB, min = 0, max = 100, step = 5, width = "100%" }

    -- 主面板
    root_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        backgroundColor = { 15, 15, 25, 240 },
        flexDirection = "row",
        children = {
            -- 左侧：Spine 预览区
            UI.Panel {
                width = 240,
                height = "100%",
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 30, 30, 45, 255 },
                borderRadius = 0,
                children = {
                    UI.Label { text = "实时预览", fontSize = 14, fontColor = { 200, 200, 200, 255 }, marginBottom = 8 },
                    previewSpine_,
                    previewColorLabel_,
                },
            },
            -- 右侧：控制面板
            UI.Panel {
                flexGrow = 1,
                height = "100%",
                padding = 14,
                gap = 4,
                overflow = "scroll",
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 8,
                        children = {
                            UI.Label { text = "外观编辑器", fontSize = 18, fontColor = { 255, 220, 100, 255 } },
                            UI.Button {
                                text = "X",
                                width = 32, height = 32,
                                onClick = function() M.Close() end,
                            },
                        },
                    },

                    -- 染色
                    SectionLabel("── 角色染色 ──"),
                    PropLabel("红 (R)"),
                    sliderR_,
                    PropLabel("绿 (G)"),
                    sliderG_,
                    PropLabel("蓝 (B)"),
                    sliderB_,

                    -- 体型缩放
                    SectionLabel("── 体型缩放 ──"),
                    PropLabel("水平缩放 (50%~200%)"),
                    sliderScaleX_,
                    PropLabel("垂直缩放 (50%~200%)"),
                    sliderScaleY_,

                    -- 动画速率
                    SectionLabel("── 动画速率 ──"),
                    PropLabel("播放速度 (20%~300%)"),
                    sliderAnimSpeed_,

                    -- 光环
                    SectionLabel("── 特效光环 ──"),
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            PropLabel("启用光环"),
                            glowBtn,
                        },
                    },
                    PropLabel("光环 R"),
                    sliderGlowR_,
                    PropLabel("光环 G"),
                    sliderGlowG_,
                    PropLabel("光环 B"),
                    sliderGlowB_,

                    -- 操作按钮
                    UI.Panel {
                        width = "100%", flexDirection = "row", gap = 8, marginTop = 16,
                        children = {
                            UI.Button {
                                text = "保存",
                                variant = "primary",
                                flexGrow = 1,
                                onClick = function() M.Save() end,
                            },
                            UI.Button {
                                text = "重置",
                                flexGrow = 1,
                                onClick = function() M.ResetToDefault() end,
                            },
                            UI.Button {
                                text = "关闭",
                                flexGrow = 1,
                                onClick = function() M.Close() end,
                            },
                        },
                    },
                },
            },
        },
    }

    UI.SetRoot(root_)
    visible_ = true

    -- 初始预览
    UpdatePreview()
    print("[AppearanceEditor] Opened for module: " .. editModuleId_)
end

--- 保存当前外观设置
function M.Save()
    if not editModuleId_ then return end

    local mod = CharRegistry.Get(editModuleId_)
    if not mod then
        print("[AppearanceEditor] Module not found: " .. editModuleId_)
        return
    end

    -- 读取 UI 值写入 mod.art
    local artData = ReadArtFromUI()
    mod.art.tint = artData.tint
    mod.art.scaleX = artData.scaleX
    mod.art.scaleY = artData.scaleY
    mod.art.animSpeed = artData.animSpeed
    mod.art.glowColor = artData.glowColor

    -- 保存到 Registry
    local ok, err = CharRegistry.SaveCustom(mod)
    if ok then
        print("[AppearanceEditor] Saved appearance for: " .. editModuleId_)
        if onSave_ then onSave_(mod) end
    else
        print("[AppearanceEditor] Save failed: " .. tostring(err))
    end
end

--- 重置为默认外观
function M.ResetToDefault()
    sliderR_:SetValue(100)
    sliderG_:SetValue(100)
    sliderB_:SetValue(100)
    sliderScaleX_:SetValue(100)
    sliderScaleY_:SetValue(100)
    sliderAnimSpeed_:SetValue(100)
    glowToggle_.checked = false
    sliderGlowR_:SetValue(100)
    sliderGlowG_:SetValue(80)
    sliderGlowB_:SetValue(20)
    UpdatePreview()
end

--- 关闭编辑器
function M.Close()
    if not visible_ then return end
    visible_ = false
    root_ = nil
    previewSpine_ = nil
    if onClose_ then onClose_() end
    print("[AppearanceEditor] Closed")
end

--- 是否正在显示
---@return boolean
function M.IsVisible()
    return visible_
end

return M
