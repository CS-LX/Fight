-- ============================================================================
-- ui/components/BoneFrameEditor.lua - 骨骼帧编辑器（关键帧时间轴）
-- ============================================================================
-- 职责：
--   1. 显示当前阶段的骨骼列表（可添加/删除骨骼）
--   2. 时间轴：显示关键帧位置，可选中/添加/删除关键帧
--   3. 属性编辑：选中某帧某骨骼后编辑 x/y/rot/scale
--   4. 素材选择：为每根骨骼绑定素材（从asset_library选择）
--   5. 动画预览：通过NanoVG绘制色块骨骼的实时预览

local UI = require("urhox-libs/UI")
local CharModule = require("characters.CharModule")
local AssetLibrary = require("data.asset_library")

-- ============================================================================
-- Module
-- ============================================================================
local BoneFrameEditor = {}

--- 创建骨骼帧编辑器
---@param opts {phaseData: SpritePhaseData, phase: string, onChange: fun()|nil}
---@return Widget editorWidget, table api
function BoneFrameEditor.Create(opts)
    local phaseData = opts.phaseData
    local phase = opts.phase or "idle"
    local onChange = opts.onChange

    -- 内部状态
    local selectedBoneIdx = 1
    local selectedKeyTime = 0.0
    local keyTimes = {}  -- 排序后的关键帧时间列表

    -- ========================================================================
    -- 辅助
    -- ========================================================================
    local function NotifyChange()
        if onChange then onChange() end
    end

    local function RebuildKeyTimes()
        keyTimes = {}
        for t, _ in pairs(phaseData.keyframes) do
            keyTimes[#keyTimes + 1] = t
        end
        table.sort(keyTimes)
    end
    RebuildKeyTimes()

    local function GetBoneKF(boneId, time)
        local frame = phaseData.keyframes[time]
        if frame and frame[boneId] then
            return frame[boneId]
        end
        return { x = 0, y = 0, rot = 0, scaleX = 1, scaleY = 1 }
    end

    local function SetBoneKF(boneId, time, kf)
        if not phaseData.keyframes[time] then
            phaseData.keyframes[time] = {}
        end
        phaseData.keyframes[time][boneId] = kf
        NotifyChange()
    end

    -- ========================================================================
    -- UI 引用（需要动态更新）
    -- ========================================================================
    local boneListPanel = nil
    local keyframeBar = nil
    local propPanel = nil
    local timeLabel = nil
    local durationSlider = nil

    -- ========================================================================
    -- 骨骼列表区
    -- ========================================================================
    local function BuildBoneItem(bone, idx)
        local isSelected = (idx == selectedBoneIdx)
        return UI.Button {
            text = bone.id .. " [" .. bone.sprite .. "]",
            width = "100%", height = 28,
            fontSize = 11,
            variant = isSelected and "primary" or "default",
            onClick = function()
                selectedBoneIdx = idx
                RefreshAll()
            end,
        }
    end

    local function BuildBoneList()
        local items = {}
        for i, bone in ipairs(phaseData.bones) do
            items[#items + 1] = BuildBoneItem(bone, i)
        end
        -- 添加骨骼按钮
        items[#items + 1] = UI.Button {
            text = "+ 添加骨骼",
            width = "100%", height = 26,
            fontSize = 11, variant = "outline",
            marginTop = 4,
            onClick = function()
                local newId = "bone_" .. (#phaseData.bones + 1)
                local newBone = {
                    id = newId,
                    sprite = "body_rect",
                    parent = phaseData.bones[1] and phaseData.bones[1].id or nil,
                    pivotX = 0, pivotY = 0,
                }
                phaseData.bones[#phaseData.bones + 1] = newBone
                -- 为所有已有关键帧添加此骨骼默认值
                for t, frame in pairs(phaseData.keyframes) do
                    if not frame[newId] then
                        frame[newId] = { x = 0, y = 0, rot = 0, scaleX = 1, scaleY = 1 }
                    end
                end
                selectedBoneIdx = #phaseData.bones
                NotifyChange()
                RefreshAll()
            end,
        }
        return items
    end

    -- ========================================================================
    -- 时间轴关键帧区
    -- ========================================================================
    local function BuildKeyframeButtons()
        local btns = {}
        for i, t in ipairs(keyTimes) do
            local isSelected = (math.abs(t - selectedKeyTime) < 0.001)
            local label = string.format("%.2fs", t)
            btns[#btns + 1] = UI.Button {
                text = label,
                width = 56, height = 26,
                fontSize = 10,
                variant = isSelected and "primary" or "default",
                onClick = function()
                    selectedKeyTime = t
                    RefreshAll()
                end,
            }
        end
        -- 添加关键帧按钮
        btns[#btns + 1] = UI.Button {
            text = "+帧",
            width = 42, height = 26,
            fontSize = 10, variant = "outline",
            onClick = function()
                -- 在最后一帧后0.25s添加新帧
                local lastT = keyTimes[#keyTimes] or 0.0
                local newT = math.floor((lastT + 0.25) * 100 + 0.5) / 100
                -- 复制最后一帧数据作为新帧
                local lastFrame = phaseData.keyframes[lastT]
                local newFrame = {}
                if lastFrame then
                    for boneId, kf in pairs(lastFrame) do
                        newFrame[boneId] = { x = kf.x, y = kf.y, rot = kf.rot, scaleX = kf.scaleX or 1, scaleY = kf.scaleY or 1 }
                    end
                else
                    for _, bone in ipairs(phaseData.bones) do
                        newFrame[bone.id] = { x = 0, y = 0, rot = 0, scaleX = 1, scaleY = 1 }
                    end
                end
                phaseData.keyframes[newT] = newFrame
                RebuildKeyTimes()
                selectedKeyTime = newT
                NotifyChange()
                RefreshAll()
            end,
        }
        -- 删除当前帧按钮（至少保留1帧）
        if #keyTimes > 1 then
            btns[#btns + 1] = UI.Button {
                text = "-帧",
                width = 42, height = 26,
                fontSize = 10, variant = "danger",
                onClick = function()
                    phaseData.keyframes[selectedKeyTime] = nil
                    RebuildKeyTimes()
                    selectedKeyTime = keyTimes[1] or 0.0
                    NotifyChange()
                    RefreshAll()
                end,
            }
        end
        return btns
    end

    -- ========================================================================
    -- 属性编辑区（选中骨骼 + 选中帧时显示）
    -- ========================================================================
    local prop_x, prop_y, prop_rot, prop_sx, prop_sy
    local prop_spriteDropdown, prop_parentDropdown
    local prop_pivotX, prop_pivotY

    local function BuildPropPanel()
        local bone = phaseData.bones[selectedBoneIdx]
        if not bone then
            return UI.Label { text = "无骨骼选中", fontSize = 12, fontColor = {120,120,120,255} }
        end

        local kf = GetBoneKF(bone.id, selectedKeyTime)

        -- 属性 slider 绑定
        local function MakeKFSlider(label, value, min, max, step, field)
            return UI.Panel {
                width = "100%", gap = 2,
                children = {
                    UI.Label { text = label .. ": " .. tostring(value), fontSize = 10, fontColor = {170,170,170,255} },
                    UI.Slider {
                        value = value, min = min, max = max, step = step,
                        width = "100%", height = 24,
                        onChange = function(self, v)
                            local curKF = GetBoneKF(bone.id, selectedKeyTime)
                            curKF[field] = v
                            SetBoneKF(bone.id, selectedKeyTime, curKF)
                        end,
                    },
                },
            }
        end

        -- 素材选择下拉
        local spriteOptions = {}
        local spriteIdx = 1
        local allSprites = AssetLibrary.sprites
        for i, sp in ipairs(allSprites) do
            spriteOptions[#spriteOptions + 1] = { label = sp.name .. " (" .. sp.category .. ")", value = sp.id }
            if sp.id == bone.sprite then spriteIdx = i end
        end

        -- 父骨骼选择
        local parentOptions = { { label = "(无/根)", value = "__none__" } }
        local parentIdx = 1
        for i, b in ipairs(phaseData.bones) do
            if b.id ~= bone.id then
                parentOptions[#parentOptions + 1] = { label = b.id, value = b.id }
                if b.id == bone.parent then parentIdx = #parentOptions end
            end
        end

        return UI.Panel {
            width = "100%", gap = 4,
            children = {
                UI.Label { text = "骨骼: " .. bone.id, fontSize = 12, fontColor = {200,220,255,255} },
                -- 素材选择
                UI.Label { text = "素材", fontSize = 10, fontColor = {150,150,150,255} },
                UI.Dropdown {
                    options = spriteOptions,
                    selectedIndex = spriteIdx,
                    width = "100%", height = 30,
                    fontSize = 11,
                    onChange = function(self, idx)
                        bone.sprite = spriteOptions[idx].value
                        NotifyChange()
                    end,
                },
                -- 父骨骼
                UI.Label { text = "父骨骼", fontSize = 10, fontColor = {150,150,150,255} },
                UI.Dropdown {
                    options = parentOptions,
                    selectedIndex = parentIdx,
                    width = "100%", height = 30,
                    fontSize = 11,
                    onChange = function(self, idx)
                        local val = parentOptions[idx].value
                        bone.parent = (val == "__none__") and nil or val
                        NotifyChange()
                    end,
                },
                -- 锚点
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 6,
                    children = {
                        UI.Panel { width = "48%", children = {
                            UI.Label { text = "锚点X: " .. (bone.pivotX or 0), fontSize = 10, fontColor = {150,150,150,255} },
                            UI.Slider { value = bone.pivotX or 0, min = -50, max = 50, step = 1, width = "100%",
                                onChange = function(self, v) bone.pivotX = v; NotifyChange() end },
                        }},
                        UI.Panel { width = "48%", children = {
                            UI.Label { text = "锚点Y: " .. (bone.pivotY or 0), fontSize = 10, fontColor = {150,150,150,255} },
                            UI.Slider { value = bone.pivotY or 0, min = -50, max = 50, step = 1, width = "100%",
                                onChange = function(self, v) bone.pivotY = v; NotifyChange() end },
                        }},
                    },
                },
                -- 关键帧变换
                UI.Divider { marginTop = 6, marginBottom = 6 },
                UI.Label { text = string.format("帧 %.2fs 变换", selectedKeyTime), fontSize = 11, fontColor = {180,220,180,255} },
                MakeKFSlider("X偏移", kf.x, -60, 60, 1, "x"),
                MakeKFSlider("Y偏移", kf.y, -60, 60, 1, "y"),
                MakeKFSlider("旋转°", kf.rot, -180, 180, 5, "rot"),
                MakeKFSlider("缩放X%", math.floor((kf.scaleX or 1) * 100), 20, 200, 5, "scaleX"),
                MakeKFSlider("缩放Y%", math.floor((kf.scaleY or 1) * 100), 20, 200, 5, "scaleY"),
                -- 删除骨骼按钮
                UI.Button {
                    text = "删除此骨骼",
                    width = "100%", height = 28,
                    fontSize = 11, variant = "danger",
                    marginTop = 10,
                    onClick = function()
                        if #phaseData.bones <= 1 then return end
                        local removeId = bone.id
                        table.remove(phaseData.bones, selectedBoneIdx)
                        -- 从所有关键帧中移除
                        for t, frame in pairs(phaseData.keyframes) do
                            frame[removeId] = nil
                        end
                        -- 清除子骨骼的 parent 引用
                        for _, b in ipairs(phaseData.bones) do
                            if b.parent == removeId then b.parent = nil end
                        end
                        selectedBoneIdx = math.max(1, selectedBoneIdx - 1)
                        NotifyChange()
                        RefreshAll()
                    end,
                },
            },
        }
    end

    -- ========================================================================
    -- 整体布局
    -- ========================================================================
    local mainPanel = nil
    local boneListContainer = nil
    local kfBarContainer = nil
    local propContainer = nil
    local durationLabel = nil

    function RefreshAll()
        if not mainPanel then return end
        -- 重建骨骼列表
        if boneListContainer then
            boneListContainer:RemoveAllChildren()
            local items = BuildBoneList()
            for _, item in ipairs(items) do
                boneListContainer:AddChild(item)
            end
        end
        -- 重建时间轴
        if kfBarContainer then
            kfBarContainer:RemoveAllChildren()
            local btns = BuildKeyframeButtons()
            for _, btn in ipairs(btns) do
                kfBarContainer:AddChild(btn)
            end
        end
        -- 重建属性面板
        if propContainer then
            propContainer:RemoveAllChildren()
            local pp = BuildPropPanel()
            propContainer:AddChild(pp)
        end
        -- 更新时长标签
        if durationLabel then
            durationLabel:SetText(string.format("时长: %.2fs", phaseData.duration))
        end
    end

    -- 时长控制
    local durationRow = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
        children = {
            UI.Label { text = string.format("时长: %.2fs", phaseData.duration), fontSize = 11, fontColor = {200,200,200,255} },
            UI.Slider {
                value = math.floor(phaseData.duration * 100),
                min = 25, max = 300, step = 25,
                width = 140, height = 24,
                onChange = function(self, v)
                    phaseData.duration = v / 100.0
                    NotifyChange()
                    RefreshAll()
                end,
            },
        },
    }
    durationLabel = durationRow:GetChildren()[1]

    -- 骨骼列表容器
    boneListContainer = UI.Panel {
        width = "100%", gap = 2,
    }

    -- 关键帧条容器
    kfBarContainer = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 4, alignItems = "center",
    }

    -- 属性容器
    propContainer = UI.Panel {
        width = "100%",
    }

    -- 主面板
    mainPanel = UI.Panel {
        width = "100%", height = "100%",
        padding = 8, gap = 6,
        overflow = "scroll",
        children = {
            -- 阶段和时长
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Label {
                        text = "阶段: " .. (CharModule.PHASE_NAMES[phase] or phase),
                        fontSize = 13, fontColor = {150,200,255,255},
                    },
                },
            },
            durationRow,
            -- 时间轴关键帧
            UI.Divider {},
            UI.Label { text = "关键帧时间轴", fontSize = 11, fontColor = {180,180,180,255} },
            kfBarContainer,
            -- 骨骼列表
            UI.Divider {},
            UI.Label { text = "骨骼列表", fontSize = 11, fontColor = {180,180,180,255} },
            boneListContainer,
            -- 属性编辑
            UI.Divider {},
            propContainer,
        },
    }

    -- 初始化填充
    RefreshAll()

    -- ========================================================================
    -- API
    -- ========================================================================
    local api = {}

    --- 获取当前阶段数据
    function api.GetPhaseData()
        return phaseData
    end

    --- 替换阶段数据（切换阶段时调用）
    function api.SetPhaseData(newData, newPhase)
        phaseData = newData
        phase = newPhase or phase
        selectedBoneIdx = 1
        selectedKeyTime = 0.0
        RebuildKeyTimes()
        if #keyTimes > 0 then selectedKeyTime = keyTimes[1] end
        RefreshAll()
    end

    return mainPanel, api
end

return BoneFrameEditor
