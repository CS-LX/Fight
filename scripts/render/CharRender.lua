-- ============================================================================
-- render/CharRender.lua - 角色表现层（Spine 渲染、位置/缩放/排序/翻转）
-- ============================================================================
-- 职责：根据逻辑层数据驱动 Spine 控件的视觉表现
-- 不修改角色逻辑数据，只读取

local UI = require("urhox-libs/UI")
local Config = require("Config")
local CharRegistry = require("characters.CharRegistry")

local M = {}

-- 渲染数据（与逻辑数据分离）
-- key = char (引用), value = { spine, currentAnim, lastFlip }
local renderData_ = {}

-- 调试：仅打印一次
local debugPrinted_ = false
-- 调试：帧计数
local frameCount_ = 0

--- 获取角色的美术配置（从 CharRegistry 模块读取）
---@param moduleId string
---@return table 兼容旧 def 格式的 art 数据
local function GetArtDef(moduleId)
    local mod = CharRegistry.Get(moduleId)
    if mod then
        return {
            spineSrc = mod.art.spineSrc,
            pma = mod.art.pma,
            anims = mod.art.anims,
            renderScale = mod.art.renderScale,
        }
    end
    -- fallback：返回默认值
    return {
        spineSrc = "spine/build_char_1035_wisdel_game_9/build_char_1035_wisdel_game_9.skel",
        pma = true,
        anims = { idle = "Default", move = "Move", attack = "Interact", hit = "Interact", die = "Sleep", relax = "Relax" },
        renderScale = 0.30,
    }
end

-- 血条配置
local HP_BAR_WIDTH = 40    -- 血条宽度 (base pixels)
local HP_BAR_HEIGHT = 5    -- 血条高度
local HP_BAR_OFFSET_Y = -2 -- 血条在角色上方的偏移

--- 为角色列表创建 Spine 控件
---@param characters table[] 逻辑数据列表
---@return Widget spineContainer
function M.CreateSpines(characters)
    local children = {}

    for _, char in ipairs(characters) do
        local def = GetArtDef(char.defId)

        local initFlip = (char.team == "blue")

        local spine = UI.Spine {
            src = def.spineSrc,
            animation = def.anims.idle,
            loop = true,
            width = 10,   -- 初始占位，Update 会在第一帧覆盖
            height = 10,
            position = "absolute",
            left = 0,
            top = 0,
            flipX = initFlip,
            pma = def.pma,
        }

        -- 血条背景（深灰底）
        local hpBg = UI.Panel {
            width = HP_BAR_WIDTH,
            height = HP_BAR_HEIGHT,
            position = "absolute",
            left = 0, top = 0,
            backgroundColor = "#333333",
            borderRadius = 2,
        }

        -- 血条前景（绿色填充）
        local hpFill = UI.Panel {
            width = "100%",
            height = "100%",
            backgroundColor = "#44cc44",
            borderRadius = 2,
        }
        hpBg:AddChild(hpFill)

        -- 存储渲染数据（与逻辑数据分离）
        renderData_[char] = {
            spine = spine,
            currentAnim = def.anims.idle,
            lastFlip = initFlip,
            hpBar = hpBg,
            hpFill = hpFill,
        }

        table.insert(children, spine)
        table.insert(children, hpBg)
    end

    local container = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        pointerEvents = "none",
        children = children,
    }

    print("[CharRender] CreateSpines: created " .. #children .. " widgets (spine + hp bars)")

    return container
end

--- 更新动画状态（根据逻辑层的 animState 切换 Spine 动画）
---@param char table 逻辑数据
local function UpdateAnimation(char)
    local rd = renderData_[char]
    if not rd then return end

    local def = GetArtDef(char.defId)
    local targetAnim = def.anims[char.animState] or def.anims.idle
    local loop = (char.animState == "idle" or char.animState == "move")

    if rd.currentAnim ~= targetAnim then
        rd.spine:SetAnimation(targetAnim, loop)
        rd.currentAnim = targetAnim
    end
end

--- 更新死亡表现（淡出效果）
---@param char table
local function UpdateDyingVisual(char)
    local rd = renderData_[char]
    if not rd then return end
    local Battle = require("logic.Battle")

    if char.state == "dying" then
        local progress = 1.0 - math.max(0, char.deathTimer / Battle.DEATH_DURATION)
        local alpha = 1.0 - progress * 0.8
        rd.spine:SetColor(1, 1, 1, alpha)
    elseif char.state == "dead" then
        rd.spine:SetVisible(false)
    end
end

--- 每帧更新所有角色的表现（位置、缩放、排序、动画、翻转）
---@param characters table[] 逻辑数据列表
---@param camera Camera
function M.Update(characters, camera)
    frameCount_ = frameCount_ + 1

    -- 使用 UI 系统的 base pixel 坐标空间
    local uiScale = UI.GetScale()
    local screenW = graphics:GetWidth() / uiScale
    local screenH = graphics:GetHeight() / uiScale

    local cameraNode = camera:GetNode()
    local cameraPos = cameraNode:GetWorldPosition()

    -- 基准距离（竞技场中心到相机）
    local refDist = (cameraPos - Vector3(0, 0, 0)):Length()

    -- 调试：前几帧打印关键信息（frame 1 和 frame 5 分别打印不同信息）
    if frameCount_ <= 5 and not debugPrinted_ then
        print(string.format("[CharRender] Frame#%d | uiScale=%.2f screenW=%.0f screenH=%.0f refDist=%.2f cameraPos=%s",
            frameCount_, uiScale, screenW, screenH, refDist, tostring(cameraPos)))
        local rdCount = 0
        for _ in pairs(renderData_) do rdCount = rdCount + 1 end
        print(string.format("[CharRender] renderData_ count=%d characters count=%d", rdCount, #characters))

        -- 打印 Spine 实例的 DataWidth/DataHeight（延迟到 frame 3 确保加载完成）
        if frameCount_ >= 3 then
            for _, char in ipairs(characters) do
                local rd = renderData_[char]
                if rd and rd.spine.spineInstance_ and rd.spine.spineInstance_:IsLoaded() then
                    local dw = rd.spine.spineInstance_:GetDataWidth()
                    local dh = rd.spine.spineInstance_:GetDataHeight()
                    local dx = rd.spine.spineInstance_:GetDataX()
                    local dy = rd.spine.spineInstance_:GetDataY()
                    print(string.format("[CharRender] Spine DATA: team=%s dataW=%.1f dataH=%.1f dataX=%.1f dataY=%.1f | props.flipX=%s",
                        char.team, dw, dh, dx, dy, tostring(rd.spine.props.flipX)))
                    break -- 只打印一个就够了
                end
            end
        end
    end

    -- 收集排序数据
    local sortList = {}

    for _, char in ipairs(characters) do
        local rd = renderData_[char]
        if not rd then goto continue end

        -- 更新动画
        UpdateAnimation(char)
        UpdateDyingVisual(char)

        if char.state == "dead" then goto continue end

        -- 世界坐标 → 屏幕归一化坐标 (0~1)
        local screenPos = camera:WorldToScreenPoint(char.worldPos)

        -- 相机距离（用于透视缩放）
        local toChar = char.worldPos - cameraPos
        local dist = toChar:Length()

        -- 透视缩放：远的小，近的大
        local def = GetArtDef(char.defId)
        local perspScale = refDist / math.max(dist, 0.1)
        perspScale = math.max(0.5, math.min(perspScale, 1.5))

        -- 翻转：facingRight=true → flipX=false; facingRight=false → flipX=true
        local shouldFlip = not char.facingRight

        -- 直接 scale 系数 = renderScale × perspScale
        local scaleVal = def.renderScale * perspScale

        -- 屏幕坐标（归一化 → base pixel）
        local sx = screenPos.x * screenW
        local sy = screenPos.y * screenH

        table.insert(sortList, {
            char = char,
            rd = rd,
            dist = dist,
            sx = sx,
            sy = sy,
            flip = shouldFlip,
            scaleVal = scaleVal,
        })

        ::continue::
    end

    -- 按距离降序排列（远的 zIndex 小，先画；近的 zIndex 大，后画覆盖）
    table.sort(sortList, function(a, b) return a.dist > b.dist end)

    -- 应用：直接控制 spineInstance_ 的 scale（绕过 widget objectFit 机制）
    -- 策略：widget 定位到角色屏幕位置（供 Render 的 else 分支计算 position）
    --        直接设置 spineInstance_ 的 scale（else 分支不碰 scale）
    for i, info in ipairs(sortList) do
        local spine = info.rd.spine
        local si = spine.spineInstance_

        -- 定位 widget 并控制 spine scale
        if si and si:IsLoaded() then
            local dw = si:GetDataWidth()
            local dh = si:GetDataHeight()
            local flipSign = info.flip and -1 or 1

            if dw > 0 and dh > 0 then
                -- dataW > 0：Render 内部会用 widget 尺寸计算 scale
                -- 反推：为了让 Render 计算出我们想要的 scaleVal，需要设 widget 尺寸 = scaleVal * dataW/H
                local targetW = math.max(1, math.floor(dw * info.scaleVal))
                local targetH = math.max(1, math.floor(dh * info.scaleVal))
                spine:SetWidth(targetW)
                spine:SetHeight(targetH)
                spine:SetStyle({
                    left = math.floor(info.sx - targetW / 2),
                    top = math.floor(info.sy - targetH),
                    zIndex = i,
                })
            else
                -- dataW = 0：Render 只设 position（不碰 scale），我们直接控制 scale
                spine:SetWidth(1)
                spine:SetHeight(1)
                spine:SetStyle({
                    left = math.floor(info.sx),
                    top = math.floor(info.sy),
                    zIndex = i,
                })
                si:SetScale(flipSign * info.scaleVal, -info.scaleVal)
            end
        else
            -- spineInstance 未加载，占位
            spine:SetStyle({ left = math.floor(info.sx), top = math.floor(info.sy), zIndex = i })
        end

        -- 也设置 props.flipX（备份：当 dataW > 0 时 Render 内部会用它）
        spine.props.flipX = info.flip

        -- 更新血条位置和填充
        local rd = info.rd
        if rd.hpBar then
            local hpRatio = math.max(0, info.char.hp / info.char.maxHP)
            local barX = math.floor(info.sx - HP_BAR_WIDTH / 2)
            local barY = math.floor(info.sy - HP_BAR_OFFSET_Y)
            rd.hpBar:SetStyle({
                left = barX,
                top = barY,
                zIndex = 100 + i,  -- 血条始终在角色上层
            })
            -- 更新填充宽度
            local fillW = math.floor(HP_BAR_WIDTH * hpRatio)
            rd.hpFill:SetWidth(math.max(0, fillW))
            -- 队伍颜色
            local color = info.char.team == "red" and "#e84040" or "#4080e8"
            rd.hpFill:SetStyle({ backgroundColor = color })
            -- 死亡/濒死时隐藏血条
            if info.char.state == "dying" or info.char.state == "dead" then
                rd.hpBar:SetVisible(false)
            end
        end

        -- 调试
        if not debugPrinted_ and frameCount_ >= 3 and i <= 2 then
            print(string.format(
                "[CharRender] #%d team=%s | scaleVal=%.4f flip=%s | screenPos=(%.0f, %.0f)",
                i, info.char.team, info.scaleVal, tostring(info.flip), info.sx, info.sy
            ))
        end
    end

    -- 在 frame 5 后标记调试完成
    if not debugPrinted_ and frameCount_ >= 5 and #sortList > 0 then
        debugPrinted_ = true
    end
end

--- 清除所有渲染数据
---@param characters table[]
function M.Clear(characters)
    for _, char in ipairs(characters) do
        local rd = renderData_[char]
        if rd then
            rd.spine:SetVisible(false)
            if rd.hpBar then rd.hpBar:SetVisible(false) end
            renderData_[char] = nil
        end
    end
    debugPrinted_ = false  -- 重置后允许再次打印调试
    frameCount_ = 0
end

--- 获取角色的 Spine 控件（供外部极少数场景使用）
---@param char table
---@return Widget|nil
function M.GetSpine(char)
    local rd = renderData_[char]
    return rd and rd.spine or nil
end

return M
