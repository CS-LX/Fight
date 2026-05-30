-- ============================================================================
-- ui/CharacterMaker.lua - 角色制作器整合面板（Phase 4）
-- ============================================================================
-- 职责：Tab容器+工具栏，整合外观/行为树/属性三个子面板
-- 布局：
--   [返回] 角色制作器: [新建] [加载] [保存] [导出] [测试战斗]
--   [外观]  [行为树]  [属性]  ← 标签切换
--   (当前标签内容, 占满剩余空间)
--   [Spine预览]  摘要: HP=100 SPD=2.5 DMG=10 AI=自定义树

local UI = require("urhox-libs/UI")
local CharModule = require("characters.CharModule")
local CharRegistry = require("characters.CharRegistry")
local BTCompiler = require("logic.BTCompiler")
local AI = require("logic.AI")
local AssetLibrary = require("data.asset_library")
local BoneFrameEditor = require("ui.components.BoneFrameEditor")
local FolderTabs = require("ui.components.FolderTabs")

local M = {}

-- 状态
local visible_ = false
---@type Widget|nil
local root_ = nil
local currentTab_ = "appearance"  -- "appearance" | "behaviour" | "attributes"

-- 当前编辑的角色模块 ID
local editModuleId_ = nil

-- 子面板引用
---@type Widget|nil
local contentArea_ = nil
---@type Widget|nil
local appearancePanel_ = nil
---@type Widget|nil
local behaviourPanel_ = nil
---@type Widget|nil
local attributesPanel_ = nil

-- 底部摘要标签
---@type Widget|nil
local summaryLabel_ = nil


-- Tab 组件引用
local mainTabApi_ = nil         -- FolderTabs API
local modeSwitchApi_ = nil      -- PillToggle API (mode)
local phaseSwitchApi_ = nil     -- PillToggle API (phase)

-- 外部回调
local onClose_ = nil
local onTestBattle_ = nil

-- ============================================================================
-- 子面板数据引用（属性面板控件）
-- ============================================================================
local attr_nameField_ = nil
local attr_speedSlider_ = nil
local attr_hpSlider_ = nil
local attr_damageSlider_ = nil
local attr_rangeSlider_ = nil
local attr_cooldownSlider_ = nil
local attr_stopDistSlider_ = nil
local attr_collisionRadiusSlider_ = nil
local attr_scaleSlider_ = nil

-- 外观面板控件
local app_sliderR_ = nil
local app_sliderG_ = nil
local app_sliderB_ = nil
local app_sliderScaleX_ = nil
local app_sliderScaleY_ = nil
local app_sliderAnimSpeed_ = nil
local app_glowToggle_ = nil
local app_sliderGlowR_ = nil
local app_sliderGlowG_ = nil
local app_sliderGlowB_ = nil

-- 外观模式相关
local app_artMode_ = "spine"       -- "spine" | "sprite_bone"
local app_boneEditorApi_ = nil     -- BoneFrameEditor API
local app_currentPhase_ = "idle"   -- 当前编辑阶段
local app_spineDropdown_ = nil     -- Spine选择下拉
local app_modeContainer_ = nil     -- 模式切换后的内容容器
local app_phaseFrames_ = nil       -- sprite_bone: 各阶段帧数据引用

-- 行为树画布引用
local btCanvasApi_ = nil

-- ============================================================================
-- 辅助
-- ============================================================================

local function SectionLabel(text)
    return UI.Label {
        text = text,
        fontSize = 13,
        fontColor = { 150, 200, 255, 255 },
        marginTop = 10,
    }
end

local function PropLabel(text)
    return UI.Label {
        text = text,
        fontSize = 11,
        fontColor = { 180, 180, 180, 255 },
        marginTop = 2,
    }
end

--- 更新摘要栏
local function UpdateSummary()
    if not summaryLabel_ then return end
    local mod = CharRegistry.Get(editModuleId_)
    if not mod then
        summaryLabel_:SetText("无角色数据")
        return
    end
    local c = mod.config
    local aiStr = mod.ai and mod.ai.profile or "default"
    if AI.GetCustomTreeData() then aiStr = "自定义树" end
    summaryLabel_:SetText(string.format(
        "HP=%d  SPD=%.1f  DMG=%d  RNG=%.1f  AI=%s",
        c.baseHP, c.baseSpeed, c.attackDamage, c.attackRange, aiStr
    ))
end

--- 从属性面板读取 config
local function ReadConfigFromUI()
    if not attr_speedSlider_ then return nil end
    return {
        baseSpeed = attr_speedSlider_:GetValue() * 0.1,
        baseHP = attr_hpSlider_:GetValue(),
        attackDamage = attr_damageSlider_:GetValue(),
        attackRange = attr_rangeSlider_:GetValue() * 0.1,
        attackCooldown = attr_cooldownSlider_:GetValue() * 0.1,
        stopDistance = attr_stopDistSlider_:GetValue() * 0.1,
        collisionRadius = attr_collisionRadiusSlider_:GetValue() * 0.01,
    }
end

--- 从外观面板读取 art 扩展数据
local function ReadArtExtFromUI()
    local result = { mode = app_artMode_ }

    if app_artMode_ == "spine" then
        -- Spine 模式：染色/缩放/光环
        if not app_sliderR_ then return result end
        result.tint = {
            r = app_sliderR_:GetValue() / 100,
            g = app_sliderG_:GetValue() / 100,
            b = app_sliderB_:GetValue() / 100,
        }
        result.scaleX = app_sliderScaleX_:GetValue() / 100
        result.scaleY = app_sliderScaleY_:GetValue() / 100
        result.animSpeed = app_sliderAnimSpeed_:GetValue() / 100
        result.glowColor = (app_glowToggle_ and app_glowToggle_.checked) and {
            r = app_sliderGlowR_:GetValue() / 100,
            g = app_sliderGlowG_:GetValue() / 100,
            b = app_sliderGlowB_:GetValue() / 100,
        } or nil
    elseif app_artMode_ == "sprite_bone" then
        -- 骨骼动画模式：帧数据
        result.frames = app_phaseFrames_
    end

    return result
end

--- 更新预览（底部预览已移除，保留空函数避免调用处报错）
local function UpdatePreviewSpine()
end

-- ============================================================================
-- 子面板创建
-- ============================================================================

--- 创建 Spine 模式子面板（染色/缩放/光环/动画选择）
local function CreateSpineModeContent(art)
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

    local onColorChange = function() UpdatePreviewSpine() end

    app_sliderR_ = UI.Slider { value = initR, min = 0, max = 100, step = 1, width = "100%", onChange = onColorChange }
    app_sliderG_ = UI.Slider { value = initG, min = 0, max = 100, step = 1, width = "100%", onChange = onColorChange }
    app_sliderB_ = UI.Slider { value = initB, min = 0, max = 100, step = 1, width = "100%", onChange = onColorChange }
    app_sliderScaleX_ = UI.Slider { value = initSX, min = 50, max = 200, step = 5, width = "100%" }
    app_sliderScaleY_ = UI.Slider { value = initSY, min = 50, max = 200, step = 5, width = "100%" }
    app_sliderAnimSpeed_ = UI.Slider {
        value = initAnimSpeed, min = 20, max = 300, step = 5, width = "100%",
        onChange = function() UpdatePreviewSpine() end,
    }

    app_glowToggle_ = { checked = hasGlow }
    local glowBtn = UI.Button {
        text = hasGlow and "ON" or "OFF",
        width = 60, height = 28,
        variant = hasGlow and "primary" or "default",
        onClick = function(self)
            app_glowToggle_.checked = not app_glowToggle_.checked
            self:SetText(app_glowToggle_.checked and "ON" or "OFF")
        end,
    }

    app_sliderGlowR_ = UI.Slider { value = initGR, min = 0, max = 100, step = 5, width = "100%" }
    app_sliderGlowG_ = UI.Slider { value = initGG, min = 0, max = 100, step = 5, width = "100%" }
    app_sliderGlowB_ = UI.Slider { value = initGB, min = 0, max = 100, step = 5, width = "100%" }

    -- Spine 文件选择下拉
    local spineOptions = {}
    local spineSelectedIdx = 1
    for i, sp in ipairs(AssetLibrary.spines) do
        spineOptions[#spineOptions + 1] = { label = sp.name, value = sp.id }
        if sp.src == art.spineSrc then spineSelectedIdx = i end
    end

    app_spineDropdown_ = UI.Dropdown {
        options = spineOptions,
        selectedIndex = spineSelectedIdx,
        width = "100%", height = 32,
        fontSize = 12,
        onChange = function(self, value)
            -- 切换 Spine 源和默认动画映射
            local spData
            for _, sp in ipairs(AssetLibrary.spines) do
                if sp.id == value then spData = sp; break end
            end
            if spData then
                local mod = CharRegistry.Get(editModuleId_)
                if mod then
                    mod.art.spineSrc = spData.src
                    mod.art.pma = spData.pma
                    -- 更新动画映射为新Spine的可用动画
                    local animList = spData.anims or {}
                    if #animList > 0 then
                        mod.art.anims.idle = animList[1] or "Default"
                        mod.art.anims.move = animList[2] or animList[1]
                        mod.art.anims.attack = animList[3] or animList[1]
                        mod.art.anims.hit = animList[3] or animList[1]
                        mod.art.anims.die = animList[4] or animList[1]
                        mod.art.anims.relax = animList[5] or animList[1]
                    end
                    UpdatePreviewSpine()
                end
            end
        end,
    }

    return UI.Panel {
        width = "100%", gap = 4,
        children = {
            SectionLabel("── Spine 资源 ──"),
            PropLabel("Spine 文件"), app_spineDropdown_,
            SectionLabel("── 角色染色 ──"),
            PropLabel("红 (R)"), app_sliderR_,
            PropLabel("绿 (G)"), app_sliderG_,
            PropLabel("蓝 (B)"), app_sliderB_,
            SectionLabel("── 体型缩放 ──"),
            PropLabel("水平缩放 (50%~200%)"), app_sliderScaleX_,
            PropLabel("垂直缩放 (50%~200%)"), app_sliderScaleY_,
            SectionLabel("── 动画速率 ──"),
            PropLabel("播放速度 (20%~300%)"), app_sliderAnimSpeed_,
            SectionLabel("── 特效光环 ──"),
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = { PropLabel("启用光环"), glowBtn },
            },
            PropLabel("光环 R"), app_sliderGlowR_,
            PropLabel("光环 G"), app_sliderGlowG_,
            PropLabel("光环 B"), app_sliderGlowB_,
        },
    }
end

--- 创建 SpriteBone 模式子面板（阶段切换 + 骨骼帧编辑器）
local function CreateSpriteBoneModeContent(art)
    -- 初始化帧数据
    app_phaseFrames_ = art.frames or CharModule.CreateDefaultFrames()
    app_currentPhase_ = "idle"

    -- 阶段切换 PillToggle（多按钮）
    local phaseTabs = {}
    for _, p in ipairs(CharModule.PHASES) do
        phaseTabs[#phaseTabs + 1] = { id = p, label = CharModule.PHASE_NAMES[p], color = { 100, 220, 180 } }
    end

    local phasePill
    phasePill, phaseSwitchApi_ = FolderTabs.CreatePillToggle({
        tabs = phaseTabs,
        activeId = app_currentPhase_,
        height = 28,
        fontSize = 11,
        onSwitch = function(id)
            app_currentPhase_ = id
            -- 切换编辑器数据
            if app_boneEditorApi_ then
                local phaseD = app_phaseFrames_[id]
                if not phaseD then
                    phaseD = CharModule.CreateDefaultPhase(id)
                    app_phaseFrames_[id] = phaseD
                end
                app_boneEditorApi_.SetPhaseData(phaseD, id)
            end
        end,
    })

    -- 创建骨骼帧编辑器
    local initPhaseData = app_phaseFrames_[app_currentPhase_]
    if not initPhaseData then
        initPhaseData = CharModule.CreateDefaultPhase(app_currentPhase_)
        app_phaseFrames_[app_currentPhase_] = initPhaseData
    end

    local editorWidget, editorApi = BoneFrameEditor.Create({
        phaseData = initPhaseData,
        phase = app_currentPhase_,
        onChange = function()
            -- 数据已原地修改，标记脏
        end,
    })
    app_boneEditorApi_ = editorApi

    return UI.Panel {
        width = "100%", gap = 6,
        children = {
            SectionLabel("── 动画阶段 ──"),
            phasePill,
            UI.Divider { marginTop = 4, marginBottom = 4 },
            editorWidget,
        },
    }
end

--- 创建外观面板 Widget（带模式切换）
local function CreateAppearancePanel(art)
    app_artMode_ = art.mode or "spine"

    -- 模式切换 PillToggle
    local modePill
    modePill, modeSwitchApi_ = FolderTabs.CreatePillToggle({
        tabs = {
            { id = "spine",       label = "Spine模式",   color = { 80, 180, 255 } },
            { id = "sprite_bone", label = "骨骼动画模式", color = { 200, 140, 255 } },
        },
        activeId = app_artMode_,
        height = 32,
        fontSize = 12,
        onSwitch = function(id)
            app_artMode_ = id
            -- 重建模式内容
            if app_modeContainer_ then
                app_modeContainer_:RemoveAllChildren()
                if id == "sprite_bone" then
                    app_modeContainer_:AddChild(CreateSpriteBoneModeContent(art))
                else
                    app_modeContainer_:AddChild(CreateSpineModeContent(art))
                end
            end
        end,
    })

    -- 模式内容容器
    app_modeContainer_ = UI.Panel { width = "100%" }

    -- 根据当前模式初始化内容
    local initContent
    if app_artMode_ == "sprite_bone" then
        initContent = CreateSpriteBoneModeContent(art)
    else
        initContent = CreateSpineModeContent(art)
    end
    app_modeContainer_:AddChild(initContent)

    return UI.Panel {
        width = "100%", height = "100%",
        overflow = "hidden",
        children = {
            UI.ScrollView {
                scrollY = true,
                bounces = false,
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexShrink = 0,
                        padding = 14,
                        gap = 6,
                        children = {
                            -- 模式切换（Pill Toggle）
                            UI.Panel {
                                width = "100%", flexDirection = "row", gap = 8, alignItems = "center",
                                children = {
                                    UI.Label { text = "渲染模式", fontSize = 11, fontColor = {140,145,160,200}, marginRight = 4 },
                                    UI.Panel { flexGrow = 1, children = { modePill } },
                                },
                            },
                            UI.Divider { marginTop = 4, marginBottom = 4 },
                            -- 模式内容
                            app_modeContainer_,
                        },
                    },
                },
            },
        },
    }
end

--- 创建属性面板 Widget
local function CreateAttributesPanel(mod)
    local c = mod.config
    attr_nameField_ = UI.TextField {
        value = mod.name,
        placeholder = "角色名称",
        width = "100%", fontSize = 14,
    }
    attr_speedSlider_ = UI.Slider { value = math.floor(c.baseSpeed * 10 + 0.5), min = 10, max = 50, step = 1, width = "100%" }
    attr_hpSlider_ = UI.Slider { value = c.baseHP, min = 50, max = 300, step = 10, width = "100%" }
    attr_damageSlider_ = UI.Slider { value = c.attackDamage, min = 5, max = 50, step = 1, width = "100%" }
    attr_rangeSlider_ = UI.Slider { value = math.floor(c.attackRange * 10 + 0.5), min = 8, max = 25, step = 1, width = "100%" }
    attr_cooldownSlider_ = UI.Slider { value = math.floor(c.attackCooldown * 10 + 0.5), min = 3, max = 20, step = 1, width = "100%" }
    attr_stopDistSlider_ = UI.Slider { value = math.floor((c.stopDistance or 0.6) * 10 + 0.5), min = 2, max = 15, step = 1, width = "100%" }
    attr_collisionRadiusSlider_ = UI.Slider { value = math.floor((c.collisionRadius or 0.4) * 100 + 0.5), min = 10, max = 80, step = 1, width = "100%" }
    attr_scaleSlider_ = UI.Slider { value = math.floor(mod.art.renderScale * 100 + 0.5), min = 10, max = 60, step = 1, width = "100%" }

    return UI.Panel {
        width = "100%", height = "100%",
        overflow = "hidden",
        children = {
            UI.ScrollView {
                scrollY = true,
                bounces = false,
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexShrink = 0,
                        padding = 14,
                        gap = 6,
                        children = {
                            SectionLabel("── 基本信息 ──"),
                            PropLabel("名称"), attr_nameField_,
                            SectionLabel("── 战斗属性 ──"),
                            PropLabel("移动速度 (×0.1 m/s)"), attr_speedSlider_,
                            PropLabel("最大血量"), attr_hpSlider_,
                            PropLabel("攻击伤害"), attr_damageSlider_,
                            PropLabel("攻击范围 (×0.1 m)"), attr_rangeSlider_,
                            PropLabel("攻击冷却 (×0.1 s)"), attr_cooldownSlider_,
                            SectionLabel("── 距离判定 ──"),
                            PropLabel("停止距离 (×0.1 m)"), attr_stopDistSlider_,
                            PropLabel("碰撞半径 (×0.01 m)"), attr_collisionRadiusSlider_,
                            SectionLabel("── 渲染 ──"),
                            PropLabel("角色缩放 (×0.01)"), attr_scaleSlider_,
                        },
                    },
                },
            },
        },
    }
end

--- 创建行为树面板 Widget（嵌入式）
local function CreateBehaviourPanel()
    local BTCanvas = require("ui.components.BTCanvas")
    local BTNodePalette = require("ui.components.BTNodePalette")
    local BTInspector = require("ui.components.BTInspector")
    local BTPresets = require("data.bt_presets")

    local inspectorApi = nil
    local canvas = nil

    canvas = BTCanvas {
        flexGrow = 1,
        height = "100%",
        onSelectionChanged = function(node)
            if inspectorApi then inspectorApi.UpdateSelection(node) end
        end,
    }

    -- 预设下拉选项
    local presetOptions = {}
    for _, p in ipairs(BTPresets.list) do
        presetOptions[#presetOptions + 1] = { label = p.name, value = p.id }
    end

    local presetDropdown = UI.Dropdown {
        width = 180,
        placeholder = "载入预设...",
        options = presetOptions,
        onChange = function(self, value)
            local presetData = BTPresets.Get(value)
            if presetData and canvas then
                canvas:ClearAll()
                canvas:LoadTreeData(presetData)
            end
        end,
    }

    local palette = BTNodePalette.Create({
        width = 150,
        onAddNode = function(nodeType, taskName)
            local layout = canvas:GetAbsoluteLayout()
            local cx, cy = 0, 0
            if layout then
                cx, cy = canvas:ScreenToCanvas(
                    layout.x + layout.w * 0.5,
                    layout.y + layout.h * 0.5
                )
            end
            cx = cx + (math.random() - 0.5) * 80
            cy = cy + (math.random() - 0.5) * 60
            local name = nil
            if taskName then
                local info = require("logic.BTTaskLibrary").registry[taskName]
                if info then name = info.label end
            end
            canvas:AddNode(nodeType, cx, cy, name, taskName)
        end,
    })

    local inspectorPanel
    inspectorPanel, inspectorApi = BTInspector.Create({
        width = 170,
        onDelete = function(nodeId)
            canvas:RemoveNode(nodeId)
            inspectorApi.UpdateSelection(nil)
        end,
        onSetRoot = function(nodeId) canvas:SetAsRoot(nodeId) end,
        onRename = function(nodeId, newName)
            local node = canvas.nodes_[nodeId]
            if node then node.name = newName end
        end,
    })

    -- 存储 canvas api 供保存/加载使用
    btCanvasApi_ = canvas

    -- 加载已有数据：优先自定义树，否则加载默认树
    local existingData = AI.GetCustomTreeData()
    if existingData then
        canvas:LoadTreeData(existingData)
    else
        -- 加载默认行为树到画布（让用户看到当前逻辑并可修改）
        local defaultData = AI.GetDefaultTreeData()
        if defaultData then
            canvas:LoadTreeData(defaultData)
        end
    end

    return UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        children = {
            -- 顶部工具栏：预设选择
            UI.Panel {
                width = "100%", height = 36,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 8,
                gap = 8,
                backgroundColor = {35, 35, 40, 255},
                children = {
                    UI.Label { text = "预设:", fontSize = 12, fontColor = {180, 180, 180, 255} },
                    presetDropdown,
                },
            },
            -- 主体区域
            UI.Panel {
                width = "100%", flexGrow = 1,
                flexDirection = "row",
                children = {
                    palette,
                    canvas,
                    inspectorPanel,
                },
            },
        },
    }
end

-- ============================================================================
-- Tab 切换逻辑
-- ============================================================================

local function SwitchTab(tab)
    if currentTab_ == tab then return end
    currentTab_ = tab

    if appearancePanel_ then appearancePanel_:Hide() end
    if behaviourPanel_ then behaviourPanel_:Hide() end
    if attributesPanel_ then attributesPanel_:Hide() end

    if tab == "appearance" and appearancePanel_ then
        appearancePanel_:Show()
    elseif tab == "behaviour" and behaviourPanel_ then
        behaviourPanel_:Show()
    elseif tab == "attributes" and attributesPanel_ then
        attributesPanel_:Show()
    end
end

-- ============================================================================
-- 工具栏动作
-- ============================================================================

--- 保存角色（整合所有子面板数据）
local function DoSave()
    local mod = CharRegistry.Get(editModuleId_)
    if not mod then
        print("[CharacterMaker] No module to save: " .. tostring(editModuleId_))
        return false
    end

    -- 读取属性面板
    local cfg = ReadConfigFromUI()
    if cfg then
        mod.config = cfg
    end
    if attr_nameField_ then
        mod.name = attr_nameField_:GetValue()
        if mod.name == "" then mod.name = "Custom Hero" end
    end
    if attr_scaleSlider_ then
        mod.art.renderScale = attr_scaleSlider_:GetValue() * 0.01
    end

    -- 读取外观面板
    local artExt = ReadArtExtFromUI()
    mod.art.mode = artExt.mode or "spine"
    if artExt.mode == "spine" then
        if artExt.tint then
            mod.art.tint = artExt.tint
            mod.art.scaleX = artExt.scaleX
            mod.art.scaleY = artExt.scaleY
            mod.art.animSpeed = artExt.animSpeed
            mod.art.glowColor = artExt.glowColor
        end
    elseif artExt.mode == "sprite_bone" then
        mod.art.frames = artExt.frames
    end

    -- 保存行为树
    if btCanvasApi_ then
        local treeData = btCanvasApi_:GetTreeData()
        if treeData and treeData.nodes and next(treeData.nodes) ~= nil then
            -- 保存到文件
            local jsonStr = cjson.encode(treeData)
            local file = File("bt_" .. editModuleId_ .. ".json", FILE_WRITE)
            if file:IsOpen() then
                file:WriteString(jsonStr)
                file:Close()
            end
            -- 编译并设到 AI
            AI.SetCustomTree(treeData)
        end
    end

    -- 写入注册表
    local ok, err = CharRegistry.SaveCustom(mod)
    if ok then
        print("[CharacterMaker] Saved: " .. mod.id .. " (" .. mod.name .. ")")
        UI.Toast { text = "角色已保存", duration = 2000 }
        UpdateSummary()
        return true
    else
        print("[CharacterMaker] Save failed: " .. tostring(err))
        UI.Toast { text = "保存失败: " .. tostring(err), duration = 3000 }
        return false
    end
end

--- 导出 JSON - 弹窗展示可复制文本
local exportModal_ = nil
local function DoExport()
    local mod = CharRegistry.Get(editModuleId_)
    if not mod then return end
    local data = CharModule.Serialize(mod)
    -- 将画布中的完整行为树数据嵌入导出配置
    local treeData = nil
    if btCanvasApi_ then
        treeData = btCanvasApi_:GetTreeData()
    end
    -- 如果画布未初始化，从自定义或默认数据获取
    if not treeData or not treeData.nodes or next(treeData.nodes) == nil then
        treeData = AI.GetCustomTreeData() or AI.GetDefaultTreeData()
    end
    if treeData and treeData.nodes and next(treeData.nodes) ~= nil then
        -- 通过 encode+decode 做深拷贝，避免引用问题
        local ok2, copy = pcall(function()
            return cjson.decode(cjson.encode(treeData))
        end)
        data.ai.behaviourTree = ok2 and copy or treeData
    end
    data.ai.profile = nil  -- 移除旧的 profile 字段
    local json = cjson.encode(data)

    -- 关闭已有弹窗
    if exportModal_ then
        exportModal_:Close()
    end

    local jsonLabel = UI.Label {
        text = json,
        fontSize = 11,
        fontFamily = "sans",
        color = {220, 220, 220, 255},
        width = "100%",
    }

    exportModal_ = UI.Modal {
        title = "角色配置导出",
        size = "lg",
        onClose = function(self) self:Close() end,
        children = {
            UI.Panel {
                width = "100%", height = 280,
                backgroundColor = {30, 30, 30, 255},
                borderRadius = 6,
                padding = 10,
                overflow = "scroll",
                children = { jsonLabel },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "flex-end",
                gap = 8,
                marginTop = 12,
                children = {
                    UI.Button {
                        text = "复制",
                        variant = "primary",
                        size = "small",
                        onClick = function()
                            ui:SetClipboardText(json)
                            UI.Toast { text = "已复制到剪贴板", duration = 1500 }
                        end,
                    },
                    UI.Button {
                        text = "关闭",
                        size = "small",
                        variant = "outlined",
                        onClick = function()
                            exportModal_:Close()
                        end,
                    },
                },
            },
        },
    }
    exportModal_:Open()
end

--- 新建角色
local function DoNew()
    local newId = "custom_" .. os.time()
    local newMod = CharModule.CreateDefault(newId, "New Hero")
    CharRegistry.SaveCustom(newMod)
    CharRegistry.SetCurrentId(newId)
    -- 重新打开制作器
    M.Close()
    M.Open({ moduleId = newId, onClose = onClose_, onTestBattle = onTestBattle_ })
end

--- 加载现有角色（切换到下一个自定义角色）
local function DoLoad()
    local allIds = CharRegistry.GetAllIds()
    if #allIds == 0 then
        UI.Toast { text = "无可加载角色", duration = 2000 }
        return
    end
    -- 找到当前角色在列表中的位置，切换到下一个
    local nextId = allIds[1]
    for i, id in ipairs(allIds) do
        if id == editModuleId_ and i < #allIds then
            nextId = allIds[i + 1]
            break
        end
    end
    if nextId == editModuleId_ then
        UI.Toast { text = "只有一个角色", duration = 2000 }
        return
    end
    CharRegistry.SetCurrentId(nextId)
    M.Close()
    M.Open({ moduleId = nextId, onClose = onClose_, onTestBattle = onTestBattle_ })
end

--- 测试战斗
local function DoTestBattle()
    -- 先保存
    if not DoSave() then return end
    -- 关闭制作器并触发战斗
    M.Close()
    if onTestBattle_ then
        onTestBattle_(editModuleId_)
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 打开角色制作器
---@param opts { moduleId: string|nil, onClose: function|nil, onTestBattle: function|nil }
function M.Open(opts)
    opts = opts or {}
    if visible_ then M.Close() end

    editModuleId_ = opts.moduleId or CharRegistry.GetCurrentId() or "wisdel"
    onClose_ = opts.onClose
    onTestBattle_ = opts.onTestBattle

    CharRegistry.SetCurrentId(editModuleId_)

    local mod = CharRegistry.Get(editModuleId_)
    if not mod then
        mod = CharModule.CreateDefault(editModuleId_, "Unknown")
        CharRegistry.SaveCustom(mod)
    end

    -- 创建子面板
    appearancePanel_ = CreateAppearancePanel(mod.art)
    behaviourPanel_ = CreateBehaviourPanel()
    attributesPanel_ = CreateAttributesPanel(mod)

    -- 初始隐藏非激活面板
    behaviourPanel_:Hide()
    attributesPanel_:Hide()

    -- Tab 栏（Folder Tabs 风格）
    local mainTabBar
    mainTabBar, mainTabApi_ = FolderTabs.CreateFolderTabs({
        tabs = {
            { id = "appearance", label = "外观" },
            { id = "behaviour",  label = "行为树" },
            { id = "attributes", label = "属性" },
        },
        activeId = "appearance",
        height = 36,
        onSwitch = function(id) SwitchTab(id) end,
    })

    -- 底部摘要
    summaryLabel_ = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 200, 200, 200, 255 },
        flexGrow = 1,
    }
    UpdateSummary()

    -- 组装主布局
    root_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = { 18, 18, 28, 250 },
        children = {
            -- 顶部工具栏
            UI.Panel {
                width = "100%", height = 42,
                flexDirection = "row",
                alignItems = "center",
                backgroundColor = { 28, 28, 36, 255 },
                paddingLeft = 10, paddingRight = 10,
                gap = 8,
                children = {
                    UI.Button {
                        text = "← 返回", size = "small", variant = "text",
                        onClick = function() M.Close() end,
                    },
                    UI.Label {
                        text = "角色制作器",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = { 255, 220, 100, 255 },
                        marginRight = 12,
                    },
                    UI.Button { text = "新建", size = "small", variant = "outlined", onClick = function() DoNew() end },
                    UI.Button { text = "加载", size = "small", variant = "outlined", onClick = function() DoLoad() end },
                    UI.Button { text = "保存", size = "small", variant = "primary", onClick = function() DoSave() end },
                    UI.Button { text = "导出", size = "small", variant = "outlined", onClick = function() DoExport() end },
                    UI.Panel { flexGrow = 1 },
                    UI.Button {
                        text = "测试战斗", size = "small",
                        variant = "primary",
                        backgroundColor = { 220, 80, 60 },
                        onClick = function() DoTestBattle() end,
                    },
                },
            },
            -- Tab 栏（Folder Tabs）
            mainTabBar,
            -- 内容区
            UI.Panel {
                width = "100%", flexGrow = 1,
                overflow = "hidden",
                children = {
                    appearancePanel_,
                    behaviourPanel_,
                    attributesPanel_,
                },
            },
            -- 底部状态栏
            UI.Panel {
                width = "100%", height = 40,
                flexDirection = "row",
                alignItems = "center",
                backgroundColor = { 25, 25, 35, 255 },
                paddingLeft = 10, paddingRight = 10,
                children = {
                    summaryLabel_,
                },
            },
        },
    }

    UI.SetRoot(root_)
    visible_ = true
    currentTab_ = "appearance"

    print("[CharacterMaker] Opened for: " .. editModuleId_ .. " (" .. mod.name .. ")")
end

--- 关闭制作器
function M.Close()
    if not visible_ then return end
    visible_ = false
    root_ = nil
    appearancePanel_ = nil
    behaviourPanel_ = nil
    attributesPanel_ = nil
    contentArea_ = nil
    summaryLabel_ = nil
    btCanvasApi_ = nil
    mainTabApi_ = nil
    modeSwitchApi_ = nil
    phaseSwitchApi_ = nil
    -- 清空控件引用
    attr_nameField_ = nil
    attr_speedSlider_ = nil
    attr_hpSlider_ = nil
    attr_damageSlider_ = nil
    attr_rangeSlider_ = nil
    attr_cooldownSlider_ = nil
    attr_stopDistSlider_ = nil
    attr_collisionRadiusSlider_ = nil
    attr_scaleSlider_ = nil
    app_sliderR_ = nil
    app_sliderG_ = nil
    app_sliderB_ = nil
    app_sliderScaleX_ = nil
    app_sliderScaleY_ = nil
    app_sliderAnimSpeed_ = nil
    app_glowToggle_ = nil
    app_sliderGlowR_ = nil
    app_sliderGlowG_ = nil
    app_sliderGlowB_ = nil

    if onClose_ then onClose_() end
    print("[CharacterMaker] Closed")
end

--- 是否可见
---@return boolean
function M.IsVisible()
    return visible_
end

return M
