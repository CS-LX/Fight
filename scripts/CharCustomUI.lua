-- ============================================================================
-- CharCustomUI.lua - 角色自定义 UI（配置 + 外观 + 保存/导出）
-- ============================================================================
-- 职责：提供角色编辑界面，允许用户自定义角色属性和 AI 行为
-- 支持：创建新角色、编辑现有角色、保存到本地持久化

local UI = require("urhox-libs/UI")
local CharModule = require("characters.CharModule")
local CharRegistry = require("characters.CharRegistry")
local AIProfiles = require("characters.AIProfiles")

local M = {}

-- UI 引用
---@type Widget|nil
local panel_ = nil
---@type boolean
local visible_ = false

-- 编辑中的角色数据
---@type CharModule|nil
local editingMod_ = nil

-- 控件引用
local nameField_ = nil
local speedSlider_ = nil
local hpSlider_ = nil
local damageSlider_ = nil
local rangeSlider_ = nil
local cooldownSlider_ = nil
local profileDropdown_ = nil
local scaleSlider_ = nil

-- 回调
local onSave_ = nil  -- function(mod) 保存完成回调
local onClose_ = nil -- function() 关闭回调

-- ============================================================================
-- 构建 UI
-- ============================================================================

--- 创建自定义面板（悬浮层，初始隐藏）
---@param parentRoot Widget 游戏的根容器
---@param onSave function|nil 保存回调 (mod)
---@param onClose function|nil 关闭回调
function M.Create(parentRoot, onSave, onClose)
    onSave_ = onSave
    onClose_ = onClose

    -- 名称输入
    nameField_ = UI.TextField {
        value = "Custom Hero",
        placeholder = "角色名称",
        width = "100%",
        fontSize = 14,
    }

    -- 速度滑块
    speedSlider_ = UI.Slider {
        value = 25, min = 10, max = 50, step = 1,
        width = "100%",
    }

    -- 血量滑块
    hpSlider_ = UI.Slider {
        value = 100, min = 50, max = 300, step = 10,
        width = "100%",
    }

    -- 攻击伤害
    damageSlider_ = UI.Slider {
        value = 10, min = 5, max = 50, step = 1,
        width = "100%",
    }

    -- 攻击范围
    rangeSlider_ = UI.Slider {
        value = 12, min = 8, max = 25, step = 1,
        width = "100%",
    }

    -- 攻击冷却
    cooldownSlider_ = UI.Slider {
        value = 8, min = 3, max = 20, step = 1,
        width = "100%",
    }

    -- AI 模板下拉
    local profileOptions = {}
    for _, name in ipairs(AIProfiles.GetNames()) do
        table.insert(profileOptions, { value = name, label = name })
    end
    profileDropdown_ = UI.Dropdown {
        options = profileOptions,
        value = "aggressive",
        width = "100%",
    }

    -- 渲染缩放
    scaleSlider_ = UI.Slider {
        value = 30, min = 10, max = 60, step = 1,
        width = "100%",
    }

    -- 主面板
    panel_ = UI.Panel {
        width = 300,
        maxHeight = "90%",
        position = "absolute",
        left = 12,
        top = 12,
        bottom = 12,
        padding = 14,
        gap = 6,
        backgroundColor = { 20, 20, 30, 230 },
        borderRadius = 10,
        overflow = "scroll",
        children = {
            -- 标题
            UI.Label { text = "角色自定义", fontSize = 18, fontColor = { 255, 220, 100, 255 } },

            -- 名称
            UI.Label { text = "名称", fontSize = 12, fontColor = { 180, 180, 180, 255 } },
            nameField_,

            -- 战斗属性
            UI.Label { text = "── 战斗属性 ──", fontSize = 13, fontColor = { 150, 200, 255, 255 }, marginTop = 8 },

            UI.Label { text = "移动速度 (×0.1 m/s)", fontSize = 11, fontColor = { 180, 180, 180, 255 } },
            speedSlider_,

            UI.Label { text = "最大血量", fontSize = 11, fontColor = { 180, 180, 180, 255 } },
            hpSlider_,

            UI.Label { text = "攻击伤害", fontSize = 11, fontColor = { 180, 180, 180, 255 } },
            damageSlider_,

            UI.Label { text = "攻击范围 (×0.1 m)", fontSize = 11, fontColor = { 180, 180, 180, 255 } },
            rangeSlider_,

            UI.Label { text = "攻击冷却 (×0.1 s)", fontSize = 11, fontColor = { 180, 180, 180, 255 } },
            cooldownSlider_,

            -- AI 行为
            UI.Label { text = "── AI 行为 ──", fontSize = 13, fontColor = { 150, 200, 255, 255 }, marginTop = 8 },

            UI.Label { text = "AI 模板", fontSize = 11, fontColor = { 180, 180, 180, 255 } },
            profileDropdown_,

            -- 外观
            UI.Label { text = "── 外观 ──", fontSize = 13, fontColor = { 150, 200, 255, 255 }, marginTop = 8 },

            UI.Label { text = "角色缩放 (×0.01)", fontSize = 11, fontColor = { 180, 180, 180, 255 } },
            scaleSlider_,

            -- 操作按钮
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 8, marginTop = 12,
                children = {
                    UI.Button {
                        text = "保存",
                        variant = "primary",
                        flexGrow = 1,
                        onClick = function(self)
                            M.SaveCurrent()
                        end,
                    },
                    UI.Button {
                        text = "关闭",
                        flexGrow = 1,
                        onClick = function(self)
                            M.Hide()
                            if onClose_ then onClose_() end
                        end,
                    },
                },
            },

            -- 导出按钮
            UI.Button {
                text = "导出 JSON（控制台）",
                width = "100%",
                marginTop = 4,
                onClick = function(self)
                    M.ExportToConsole()
                end,
            },
        },
    }

    panel_:Hide()
    parentRoot:AddChild(panel_)
    visible_ = false
end

-- ============================================================================
-- 数据 ↔ UI 同步
-- ============================================================================

--- 从 UI 控件读取当前值，组装为 CharModule
---@return CharModule
function M.ReadFromUI()
    local name = nameField_:GetValue()
    if name == "" then name = "Custom Hero" end

    -- 生成唯一 ID（基于名称 + 时间戳）
    local id = editingMod_ and editingMod_.id or ("custom_" .. os.time())

    local mod = {
        id = id,
        name = name,
        config = {
            baseSpeed = speedSlider_:GetValue() * 0.1,
            baseHP = hpSlider_:GetValue(),
            attackDamage = damageSlider_:GetValue(),
            attackRange = rangeSlider_:GetValue() * 0.1,
            attackCooldown = cooldownSlider_:GetValue() * 0.1,
        },
        art = {
            -- 目前只有一套 Spine 素材，后续可扩展选择
            spineSrc = "spine/build_char_1035_wisdel_game_9/build_char_1035_wisdel_game_9.skel",
            pma = true,
            anims = {
                idle = "Default",
                move = "Move",
                attack = "Interact",
                hit = "Interact",
                die = "Sleep",
                relax = "Relax",
            },
            renderScale = scaleSlider_:GetValue() * 0.01,
        },
        ai = {
            profile = profileDropdown_:GetValue(),
        },
    }

    return mod
end

--- 将 CharModule 数据写入 UI 控件
---@param mod CharModule
function M.WriteToUI(mod)
    editingMod_ = mod
    nameField_:SetValue(mod.name)
    speedSlider_:SetValue(math.floor(mod.config.baseSpeed * 10 + 0.5))
    hpSlider_:SetValue(mod.config.baseHP)
    damageSlider_:SetValue(mod.config.attackDamage)
    rangeSlider_:SetValue(math.floor(mod.config.attackRange * 10 + 0.5))
    cooldownSlider_:SetValue(math.floor(mod.config.attackCooldown * 10 + 0.5))
    profileDropdown_:SetValue(mod.ai.profile)
    scaleSlider_:SetValue(math.floor(mod.art.renderScale * 100 + 0.5))
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 显示面板（编辑新角色）
function M.ShowNew()
    local default = CharModule.CreateDefault("custom_" .. os.time(), "Custom Hero")
    M.WriteToUI(default)
    panel_:Show()
    visible_ = true
end

--- 显示面板（编辑已有角色）
---@param moduleId string
function M.ShowEdit(moduleId)
    local mod = CharRegistry.Get(moduleId)
    if mod then
        M.WriteToUI(mod)
    else
        M.ShowNew()
        return
    end
    panel_:Show()
    visible_ = true
end

--- 隐藏面板
function M.Hide()
    if panel_ then
        panel_:Hide()
    end
    visible_ = false
end

--- 面板是否可见
---@return boolean
function M.IsVisible()
    return visible_
end

--- 保存当前编辑的角色
function M.SaveCurrent()
    local mod = M.ReadFromUI()
    local ok, err = CharRegistry.SaveCustom(mod)
    if ok then
        print("[CharCustomUI] Saved: " .. mod.id .. " (" .. mod.name .. ")")
        if onSave_ then onSave_(mod) end
    else
        print("[CharCustomUI] Save failed: " .. (err or "unknown"))
    end
end

--- 导出当前角色数据到控制台（JSON 格式）
function M.ExportToConsole()
    local mod = M.ReadFromUI()
    local data = CharModule.Serialize(mod)
    local json = cjson.encode(data)
    print("=== CHARACTER MODULE EXPORT ===")
    print(json)
    print("=== END EXPORT ===")
end

return M
