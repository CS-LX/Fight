-- ============================================================================
-- GameUI.lua - 游戏UI层（HUD + Spine角色渲染）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local Character = require("Character")

local M = {}

-- UI 引用
---@type Widget|nil
local statusLabel_ = nil
---@type Widget|nil
local redCountLabel_ = nil
---@type Widget|nil
local blueCountLabel_ = nil
---@type Widget|nil
local spineContainer_ = nil

-- 重置回调
local onResetCallback_ = nil

--- 初始化UI系统
function M.Init()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

--- 关闭UI系统
function M.Shutdown()
    UI.Shutdown()
end

--- 为角色列表创建 Spine 控件
---@param characters table[]
function M.CreateSpines(characters)
    local children = {}

    for i, char in ipairs(characters) do
        local tint = nil
        if char.team == "red" then
            tint = { 1.0, 0.85, 0.85, 1.0 }
        else
            tint = { 0.85, 0.85, 1.0, 1.0 }
        end

        local spine = UI.Spine {
            src = Character.SPINE_SRC,
            animation = Character.Anim.Idle,
            loop = true,
            width = Character.SPINE_WIDTH,
            height = Character.SPINE_HEIGHT,
            position = "absolute",
            flipX = (char.team == "blue"),
            pma = true,
        }

        -- 着色区分队伍
        if tint then
            spine:SetColor(tint[1], tint[2], tint[3], tint[4])
        end

        char.spine = spine
        table.insert(children, spine)
    end

    spineContainer_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        pointerEvents = "none",
        children = children,
    }

    return spineContainer_
end

--- 创建完整游戏HUD（含 Spine 角色层）
---@param characters table[]
---@param onReset function 重置回调
function M.CreateHUD(characters, onReset)
    onResetCallback_ = onReset

    -- Spine 角色容器
    local spineLayer = M.CreateSpines(characters)

    -- 红队计数
    redCountLabel_ = UI.Label {
        text = "Red: " .. Config.TeamSize,
        fontSize = 18,
        fontColor = { 255, 80, 80, 255 },
        position = "absolute",
        top = 12,
        left = 16,
    }

    -- 蓝队计数
    blueCountLabel_ = UI.Label {
        text = "Blue: " .. Config.TeamSize,
        fontSize = 18,
        fontColor = { 80, 120, 255, 255 },
        position = "absolute",
        top = 12,
        right = 16,
    }

    -- 中间状态
    statusLabel_ = UI.Label {
        text = "FIGHT!",
        fontSize = 28,
        fontColor = { 255, 255, 100, 255 },
        position = "absolute",
        top = 10,
        left = 0,
        right = 0,
        textAlign = "center",
    }

    -- 重新开始按钮
    local resetBtn = UI.Button {
        text = "Restart",
        width = 100,
        height = 36,
        position = "absolute",
        bottom = 20,
        right = 16,
        onClick = function(self)
            if onResetCallback_ then
                onResetCallback_()
            end
        end,
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            spineLayer,
            redCountLabel_,
            blueCountLabel_,
            statusLabel_,
            resetBtn,
        }
    }

    UI.SetRoot(root)
end

--- 更新 Spine 角色屏幕位置（每帧调用）
--- 包含：透视缩放（近大远小）+ 图层排序（近处在前）
---@param characters table[]
---@param camera Camera
function M.UpdateSpinePositions(characters, camera)
    local screenW = graphics:GetWidth() / graphics:GetDPR()
    local screenH = graphics:GetHeight() / graphics:GetDPR()
    local cameraNode = camera:GetNode()
    local cameraPos = cameraNode:GetWorldPosition()

    -- 基准距离：用于确定 scale=1.0 时的相机距离
    -- 取竞技场中心点到相机的距离作为参考
    local refDist = (cameraPos - Vector3(0, 0, 0)):Length()

    -- 收集每个活着角色的排序信息
    local sortList = {}

    for _, char in ipairs(characters) do
        if char.spine and char.state ~= "dead" then
            -- 世界坐标 → 屏幕坐标 (0~1 范围)
            local screenPos = camera:WorldToScreenPoint(char.worldPos)

            -- 计算角色到相机的距离（用于透视缩放和排序）
            local toChar = char.worldPos - cameraPos
            local dist = toChar:Length()

            -- 透视缩放：距离越近越大，距离越远越小
            local scale = refDist / math.max(dist, 0.1)
            -- 限制缩放范围防止极端值
            scale = math.max(0.4, math.min(scale, 2.0))

            local w = math.floor(Character.SPINE_WIDTH * scale)
            local h = math.floor(Character.SPINE_HEIGHT * scale)

            -- 像素坐标（角色脚底居中对齐）
            local px = screenPos.x * screenW - w / 2
            local py = screenPos.y * screenH - h

            table.insert(sortList, {
                char = char,
                dist = dist,
                px = math.floor(px),
                py = math.floor(py),
                w = w,
                h = h,
            })
        end
    end

    -- 按距离降序排序（远的先渲染/zIndex小，近的后渲染/zIndex大）
    table.sort(sortList, function(a, b) return a.dist > b.dist end)

    -- 应用位置、尺寸、zIndex
    for i, info in ipairs(sortList) do
        info.char.spine:SetStyle({
            left = info.px,
            top = info.py,
            width = info.w,
            height = info.h,
            zIndex = i,  -- 远的 zIndex 小，近的 zIndex 大
        })
    end
end

--- 更新队伍存活计数
---@param redAlive number
---@param blueAlive number
function M.UpdateCounts(redAlive, blueAlive)
    if redCountLabel_ then
        redCountLabel_:SetText("Red: " .. redAlive)
    end
    if blueCountLabel_ then
        blueCountLabel_:SetText("Blue: " .. blueAlive)
    end
end

--- 显示胜利信息
---@param message string
function M.ShowResult(message)
    if statusLabel_ then
        statusLabel_:SetText(message)
    end
end

--- 重置状态文字
function M.ResetStatus()
    if statusLabel_ then
        statusLabel_:SetText("FIGHT!")
    end
end

--- 清除 Spine 控件（重置时调用）
---@param characters table[]
function M.ClearSpines(characters)
    for _, char in ipairs(characters) do
        if char.spine then
            char.spine:SetVisible(false)
            char.spine = nil
        end
    end
end

--- 重建 Spine 层（重置游戏时）
---@param characters table[]
function M.RebuildHUD(characters, onReset)
    M.CreateHUD(characters, onReset)
end

return M
