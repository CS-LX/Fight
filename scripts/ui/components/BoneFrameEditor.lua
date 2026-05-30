-- ============================================================================
-- ui/components/BoneFrameEditor.lua - 可视化骨骼编辑器 + 时间轴帧编辑
-- ============================================================================
-- 布局设计（类 Spine 编辑器风格）：
--   ┌──────────────────────────────────────────┐
--   │  [可视化骨骼预览区]  色块骨骼实时摆放   │
--   ├──────────────────────────────────────────┤
--   │  时间轴 Dopesheet：                      │
--   │  骨骼1  ●────●────●                     │
--   │  骨骼2  ●─────────●                     │
--   │  骨骼3  ●────●                          │
--   │  [+帧] [-帧] [时长: 1.0s]               │
--   ├──────────────────────────────────────────┤
--   │  选中骨骼属性：素材/父骨骼/锚点/变换    │
--   └──────────────────────────────────────────┘

local UI = require("urhox-libs/UI")
local CharModule = require("characters.CharModule")
local AssetLibrary = require("data.asset_library")

local BoneFrameEditor = {}

-- 颜色配置
local COLORS = {
    previewBg       = { 22, 24, 32, 255 },
    gridLine        = { 40, 42, 52, 120 },
    boneNormal      = { 100, 130, 200, 220 },
    boneSelected    = { 120, 220, 255, 255 },
    boneBorder      = { 200, 220, 255, 100 },
    timelineBg      = { 28, 30, 38, 255 },
    trackBg         = { 36, 38, 48, 255 },
    trackAlt        = { 32, 34, 44, 255 },
    trackSelected   = { 45, 60, 90, 255 },
    keyDot          = { 255, 200, 80, 255 },
    keyDotSelected  = { 255, 120, 80, 255 },
    playhead        = { 255, 80, 80, 200 },
    propBg          = { 30, 32, 40, 255 },
    textDim         = { 130, 135, 150, 200 },
    textBright      = { 220, 225, 240, 255 },
    accent          = { 80, 180, 255, 255 },
}

--- 创建骨骼帧编辑器
---@param opts {phaseData: SpritePhaseData, phase: string, onChange: fun()|nil}
---@return Widget editorWidget, table api
function BoneFrameEditor.Create(opts)
    local phaseData = opts.phaseData
    local phase = opts.phase or "idle"
    local onChange = opts.onChange

    -- 内部状态
    local selectedBoneIdx = 1
    local selectedKeyIdx = 1   -- 在 keyTimes 中的索引
    local keyTimes = {}

    -- ========================================================================
    -- 辅助函数
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
        -- 修正选择索引
        if selectedKeyIdx > #keyTimes then selectedKeyIdx = #keyTimes end
        if selectedKeyIdx < 1 then selectedKeyIdx = 1 end
    end
    RebuildKeyTimes()

    local function GetSelectedTime()
        return keyTimes[selectedKeyIdx] or 0.0
    end

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
    -- 面板引用
    -- ========================================================================
    local mainPanel = nil
    local timelineContainer = nil
    local propContainer = nil
    local previewContainer = nil
    local timeInfoLabel = nil

    -- ========================================================================
    -- 可视化骨骼预览（色块拼接显示当前帧所有骨骼）
    -- ========================================================================
    local function BuildPreviewPanel()
        local time = GetSelectedTime()
        local boneWidgets = {}

        for i, bone in ipairs(phaseData.bones) do
            local kf = GetBoneKF(bone.id, time)
            local spriteInfo = AssetLibrary.GetSprite(bone.sprite)
            local w = spriteInfo and spriteInfo.width or 20
            local h = spriteInfo and spriteInfo.height or 20
            local color = spriteInfo and spriteInfo.color or COLORS.boneNormal
            local isSelected = (i == selectedBoneIdx)

            -- 计算位置（锚点 + 关键帧偏移）
            local px = 90 + (bone.pivotX or 0) + (kf.x or 0)
            local py = 70 + (bone.pivotY or 0) + (kf.y or 0)

            boneWidgets[#boneWidgets + 1] = UI.Panel {
                position = "absolute",
                left = px - w / 2,
                top = py - h / 2,
                width = w,
                height = h,
                backgroundColor = color,
                borderRadius = (bone.sprite and bone.sprite:find("round")) and math.min(w, h) / 2 or 3,
                borderWidth = isSelected and 2 or 0,
                borderColor = COLORS.boneSelected,
                onClick = function()
                    selectedBoneIdx = i
                    RefreshAll()
                end,
            }

            -- 骨骼名标签
            if isSelected then
                boneWidgets[#boneWidgets + 1] = UI.Label {
                    text = bone.id,
                    position = "absolute",
                    left = px - 14,
                    top = py + h / 2 + 2,
                    fontSize = 8,
                    fontColor = COLORS.accent,
                }
            end
        end

        return UI.Panel {
            width = "100%",
            height = 180,
            backgroundColor = COLORS.previewBg,
            borderRadius = 6,
            overflow = "hidden",
            children = boneWidgets,
        }
    end

    -- ========================================================================
    -- 时间轴 Dopesheet（骨骼轨道 + 关键帧圆点）
    -- ========================================================================
    local function BuildTimeline()
        local trackHeight = 26
        local headerW = 60
        local timelineW = 400
        local totalW = headerW + timelineW
        local duration = phaseData.duration

        local tracks = {}

        for i, bone in ipairs(phaseData.bones) do
            local isSelected = (i == selectedBoneIdx)
            local bgColor = isSelected and COLORS.trackSelected or (i % 2 == 0 and COLORS.trackAlt or COLORS.trackBg)

            -- 骨骼名标签（左侧轨道头）
            local trackLabel = UI.Panel {
                width = headerW,
                height = trackHeight,
                justifyContent = "center",
                paddingLeft = 6,
                backgroundColor = bgColor,
                onClick = function()
                    selectedBoneIdx = i
                    RefreshAll()
                end,
                children = {
                    UI.Label {
                        text = bone.id,
                        fontSize = 10,
                        fontColor = isSelected and COLORS.accent or COLORS.textDim,
                    },
                },
            }

            -- 关键帧点（右侧时间区域）
            local dots = {}
            for ki, t in ipairs(keyTimes) do
                local xPos = math.floor(t / duration * (timelineW - 16)) + 4
                local isKeySelected = (ki == selectedKeyIdx)
                local dotColor = isKeySelected and COLORS.keyDotSelected or COLORS.keyDot
                local dotSize = isKeySelected and 10 or 7

                dots[#dots + 1] = UI.Panel {
                    position = "absolute",
                    left = xPos,
                    top = math.floor((trackHeight - dotSize) / 2),
                    width = dotSize,
                    height = dotSize,
                    borderRadius = dotSize / 2,
                    backgroundColor = dotColor,
                    onClick = function()
                        selectedKeyIdx = ki
                        selectedBoneIdx = i
                        RefreshAll()
                    end,
                }
            end

            -- 轨道线条（连接各关键帧）
            local trackLine = UI.Panel {
                width = timelineW,
                height = trackHeight,
                backgroundColor = bgColor,
                position = "relative",
                children = dots,
            }

            -- 一行轨道 = 标签 + 时间区
            tracks[#tracks + 1] = UI.Panel {
                width = "100%",
                height = trackHeight,
                flexDirection = "row",
                children = { trackLabel, trackLine },
            }
        end

        -- 时间刻度头（显示时间标记）
        local scaleMarks = {}
        local numMarks = math.max(2, math.floor(duration / 0.25) + 1)
        numMarks = math.min(numMarks, 9)  -- 最多显示9个标记
        for m = 0, numMarks - 1 do
            local t = m * (duration / (numMarks - 1))
            local xPos = math.floor(t / duration * (timelineW - 16)) + 4
            scaleMarks[#scaleMarks + 1] = UI.Label {
                text = string.format("%.1f", t),
                position = "absolute",
                left = xPos - 6,
                top = 0,
                fontSize = 8,
                fontColor = COLORS.textDim,
            }
        end

        local scaleBar = UI.Panel {
            width = "100%", height = 16,
            flexDirection = "row",
            children = {
                UI.Panel { width = headerW, height = 16 },  -- 空占位对齐
                UI.Panel {
                    width = timelineW, height = 16,
                    position = "relative",
                    children = scaleMarks,
                },
            },
        }

        -- 底部控制栏：帧操作 + 时长
        local controlBar = UI.Panel {
            width = "100%", height = 32,
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            paddingLeft = 4,
            marginTop = 4,
            children = {
                UI.Button {
                    text = "+帧", width = 42, height = 24, fontSize = 10, variant = "outlined", size = "small",
                    onClick = function()
                        local lastT = keyTimes[#keyTimes] or 0.0
                        local newT = math.floor((lastT + 0.25) * 100 + 0.5) / 100
                        -- 复制最后一帧数据
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
                        selectedKeyIdx = #keyTimes
                        NotifyChange()
                        RefreshAll()
                    end,
                },
                (#keyTimes > 1) and UI.Button {
                    text = "-帧", width = 42, height = 24, fontSize = 10, variant = "danger", size = "small",
                    onClick = function()
                        local t = GetSelectedTime()
                        phaseData.keyframes[t] = nil
                        RebuildKeyTimes()
                        NotifyChange()
                        RefreshAll()
                    end,
                } or UI.Panel { width = 1 },
                UI.Panel { flexGrow = 1 },
                UI.Label { text = "时长", fontSize = 10, fontColor = COLORS.textDim },
                UI.Slider {
                    value = math.floor(phaseData.duration * 100),
                    min = 25, max = 300, step = 25,
                    width = 80, height = 20,
                    onChange = function(self, v)
                        phaseData.duration = v / 100.0
                        NotifyChange()
                        RefreshAll()
                    end,
                },
                UI.Label { text = string.format("%.2fs", phaseData.duration), fontSize = 10, fontColor = COLORS.textBright },
            },
        }

        return UI.Panel {
            width = "100%",
            backgroundColor = COLORS.timelineBg,
            borderRadius = 4,
            padding = 4,
            gap = 0,
            children = {
                scaleBar,
                table.unpack(tracks),
            },
        }, controlBar
    end

    -- ========================================================================
    -- 属性面板（选中骨骼 + 选中帧 的变换编辑）
    -- ========================================================================
    local function BuildPropPanel()
        local bone = phaseData.bones[selectedBoneIdx]
        if not bone then
            return UI.Label { text = "无骨骼", fontSize = 11, fontColor = COLORS.textDim }
        end

        local time = GetSelectedTime()
        local kf = GetBoneKF(bone.id, time)

        -- 属性行（紧凑 label + slider 单行）
        local function PropRow(label, value, min, max, step, field, isPercent)
            local displayVal = isPercent and tostring(math.floor(value)) .. "%" or tostring(value)
            return UI.Panel {
                width = "100%", height = 28,
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    UI.Label { text = label, fontSize = 10, fontColor = COLORS.textDim, width = 36 },
                    UI.Slider {
                        value = value, min = min, max = max, step = step,
                        width = 120, height = 18,
                        onChange = function(self, v)
                            local curKF = GetBoneKF(bone.id, time)
                            if isPercent then
                                curKF[field] = v / 100
                            else
                                curKF[field] = v
                            end
                            SetBoneKF(bone.id, time, curKF)
                            -- 刷新预览
                            if previewContainer then
                                previewContainer:RemoveAllChildren()
                                previewContainer:AddChild(BuildPreviewPanel())
                            end
                        end,
                    },
                    UI.Label { text = displayVal, fontSize = 9, fontColor = COLORS.textDim, width = 32 },
                },
            }
        end

        -- 素材下拉
        local spriteOptions = {}
        local spriteIdx = 1
        for i, sp in ipairs(AssetLibrary.sprites) do
            spriteOptions[#spriteOptions + 1] = { label = sp.name, value = sp.id }
            if sp.id == bone.sprite then spriteIdx = i end
        end

        -- 父骨骼下拉
        local parentOptions = { { label = "(根)", value = "__none__" } }
        local parentIdx = 1
        for _, b in ipairs(phaseData.bones) do
            if b.id ~= bone.id then
                parentOptions[#parentOptions + 1] = { label = b.id, value = b.id }
                if b.id == bone.parent then parentIdx = #parentOptions end
            end
        end

        return UI.Panel {
            width = "100%", gap = 4,
            children = {
                -- 骨骼标题行
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
                    children = {
                        UI.Label { text = bone.id, fontSize = 12, fontColor = COLORS.accent },
                        UI.Label { text = string.format("@ %.2fs", time), fontSize = 10, fontColor = COLORS.keyDot },
                    },
                },
                -- 素材 + 父骨骼（单行紧凑）
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 6,
                    children = {
                        UI.Panel { width = "50%", children = {
                            UI.Label { text = "素材", fontSize = 9, fontColor = COLORS.textDim },
                            UI.Dropdown {
                                options = spriteOptions, selectedIndex = spriteIdx,
                                width = "100%", height = 26, fontSize = 10,
                                onChange = function(self, value)
                                    bone.sprite = value
                                    NotifyChange()
                                    if previewContainer then
                                        previewContainer:RemoveAllChildren()
                                        previewContainer:AddChild(BuildPreviewPanel())
                                    end
                                end,
                            },
                        }},
                        UI.Panel { width = "50%", children = {
                            UI.Label { text = "父骨骼", fontSize = 9, fontColor = COLORS.textDim },
                            UI.Dropdown {
                                options = parentOptions, selectedIndex = parentIdx,
                                width = "100%", height = 26, fontSize = 10,
                                onChange = function(self, value)
                                    bone.parent = (value == "__none__") and nil or value
                                    NotifyChange()
                                end,
                            },
                        }},
                    },
                },
                -- 变换属性
                UI.Divider { marginTop = 2, marginBottom = 2 },
                PropRow("X", kf.x, -60, 60, 1, "x", false),
                PropRow("Y", kf.y, -60, 60, 1, "y", false),
                PropRow("旋转", kf.rot, -180, 180, 5, "rot", false),
                PropRow("缩放X", math.floor((kf.scaleX or 1) * 100), 20, 200, 5, "scaleX", true),
                PropRow("缩放Y", math.floor((kf.scaleY or 1) * 100), 20, 200, 5, "scaleY", true),
                -- 操作按钮行
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 6, marginTop = 6,
                    children = {
                        UI.Button {
                            text = "+ 骨骼", height = 24, fontSize = 10, variant = "outlined", size = "small", flexGrow = 1,
                            onClick = function()
                                local newId = "bone_" .. (#phaseData.bones + 1)
                                phaseData.bones[#phaseData.bones + 1] = {
                                    id = newId, sprite = "body_rect",
                                    parent = phaseData.bones[1] and phaseData.bones[1].id or nil,
                                    pivotX = 0, pivotY = 0,
                                }
                                for t, frame in pairs(phaseData.keyframes) do
                                    if not frame[newId] then
                                        frame[newId] = { x = 0, y = 0, rot = 0, scaleX = 1, scaleY = 1 }
                                    end
                                end
                                selectedBoneIdx = #phaseData.bones
                                NotifyChange()
                                RefreshAll()
                            end,
                        },
                        (#phaseData.bones > 1) and UI.Button {
                            text = "删除", height = 24, fontSize = 10, variant = "danger", size = "small", width = 50,
                            onClick = function()
                                local removeId = bone.id
                                table.remove(phaseData.bones, selectedBoneIdx)
                                for t, frame in pairs(phaseData.keyframes) do
                                    frame[removeId] = nil
                                end
                                for _, b in ipairs(phaseData.bones) do
                                    if b.parent == removeId then b.parent = nil end
                                end
                                selectedBoneIdx = math.max(1, selectedBoneIdx - 1)
                                NotifyChange()
                                RefreshAll()
                            end,
                        } or UI.Panel { width = 1 },
                    },
                },
            },
        }
    end

    -- ========================================================================
    -- 刷新所有
    -- ========================================================================
    function RefreshAll()
        if not mainPanel then return end
        if previewContainer then
            previewContainer:RemoveAllChildren()
            previewContainer:AddChild(BuildPreviewPanel())
        end
        if timelineContainer then
            timelineContainer:RemoveAllChildren()
            local timeline, controlBar = BuildTimeline()
            timelineContainer:AddChild(timeline)
            timelineContainer:AddChild(controlBar)
        end
        if propContainer then
            propContainer:RemoveAllChildren()
            propContainer:AddChild(BuildPropPanel())
        end
    end

    -- ========================================================================
    -- 主布局
    -- ========================================================================
    previewContainer = UI.Panel { width = "100%" }
    timelineContainer = UI.Panel { width = "100%", gap = 2 }
    propContainer = UI.Panel { width = "100%" }

    mainPanel = UI.Panel {
        width = "100%",
        gap = 8,
        children = {
            -- 骨骼可视化预览
            previewContainer,
            -- 时间轴 Dopesheet
            timelineContainer,
            -- 属性编辑
            UI.Panel {
                width = "100%",
                backgroundColor = COLORS.propBg,
                borderRadius = 4,
                padding = 8,
                children = { propContainer },
            },
        },
    }

    -- 初始填充
    RefreshAll()

    -- ========================================================================
    -- API
    -- ========================================================================
    local api = {}

    function api.GetPhaseData()
        return phaseData
    end

    function api.SetPhaseData(newData, newPhase)
        phaseData = newData
        phase = newPhase or phase
        selectedBoneIdx = 1
        selectedKeyIdx = 1
        RebuildKeyTimes()
        RefreshAll()
    end

    return mainPanel, api
end

return BoneFrameEditor
