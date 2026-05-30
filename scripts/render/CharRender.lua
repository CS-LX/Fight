-- ============================================================================
-- render/CharRender.lua - 角色表现层（Spine 渲染、位置/缩放/排序/翻转）
-- ============================================================================
-- 职责：根据逻辑层数据驱动 Spine 控件的视觉表现
-- 不修改角色逻辑数据，只读取

local UI = require("urhox-libs/UI")
local Config = require("Config")
local CharRegistry = require("characters.CharRegistry")
local AssetLibrary = require("data.asset_library")

local M = {}

-- 渲染数据（与逻辑数据分离）
-- key = char (引用), value = { spine, currentAnim, lastFlip }
local renderData_ = {}

-- 调试：仅打印一次
local debugPrinted_ = false
-- 调试：帧计数
local frameCount_ = 0

--- 创建 sprite_bone 模式的显示面板（从帧数据中提取主体素材）
---@param def table art 配置
---@return Widget
local function CreateSpriteBonePanel(def)
    local bgImage = nil
    local bgColor = {100, 130, 200, 220}
    local w, h = 48, 64

    -- 从 idle 帧数据的 body 骨骼获取素材
    if def.frames and def.frames.idle then
        local bones = def.frames.idle.bones
        if bones then
            for _, bone in ipairs(bones) do
                if bone.id == "body" and bone.sprite then
                    local info = AssetLibrary.GetSprite(bone.sprite)
                    if info then
                        if info.image then
                            bgImage = info.image
                            w = info.width or 48
                            h = info.height or 48
                        else
                            bgColor = info.color or bgColor
                            w = info.width or w
                            h = info.height or h
                        end
                    end
                    break
                end
            end
        end
    end

    local props = {
        width = w,
        height = h,
        position = "absolute",
        left = 0, top = 0,
        borderRadius = 4,
    }
    if bgImage then
        props.backgroundImage = bgImage
    else
        props.backgroundColor = bgColor
    end
    local panel = UI.Panel(props)

    -- 覆盖 Render 方法以支持 flipX（UI.Panel 原生不支持非 uniform scale）
    local originalRender = panel.Render
    function panel:Render(nvg)
        if self.props.flipX then
            local l = self:GetAbsoluteLayout()
            local cx = l.x + l.w / 2
            nvgSave(nvg)
            nvgTranslate(nvg, cx, 0)
            nvgScale(nvg, -1, 1)
            nvgTranslate(nvg, -cx, 0)
            self:RenderFullBackground(nvg)
            nvgRestore(nvg)
        else
            self:RenderFullBackground(nvg)
        end
    end

    return panel
end

--- 获取角色的美术配置（从 CharRegistry 模块读取）
---@param moduleId string
---@return table 兼容旧 def 格式的 art 数据（含外观扩展）
local function GetArtDef(moduleId)
    local mod = CharRegistry.Get(moduleId)
    if mod then
        return {
            mode = mod.art.mode or "spine",
            spineSrc = mod.art.spineSrc,
            pma = mod.art.pma,
            anims = mod.art.anims,
            renderScale = mod.art.renderScale,
            tint = mod.art.tint,
            scaleX = mod.art.scaleX or 1.0,
            scaleY = mod.art.scaleY or 1.0,
            animSpeed = mod.art.animSpeed or 1.0,
            glowColor = mod.art.glowColor,
            frames = mod.art.frames,
        }
    end
    -- fallback：返回默认值
    return {
        mode = "spine",
        spineSrc = "spine/build_char_1035_wisdel_game_9/build_char_1035_wisdel_game_9.skel",
        pma = true,
        anims = { idle = "Default", move = "Move", attack = "Interact", hit = "Interact", die = "Sleep", relax = "Relax" },
        renderScale = 0.30,
        tint = nil,
        scaleX = 1.0,
        scaleY = 1.0,
        animSpeed = 1.0,
        glowColor = nil,
        frames = nil,
    }
end

-- 血条配置
local HP_BAR_WIDTH = 40    -- 血条宽度 (base pixels)
local HP_BAR_HEIGHT = 5    -- 血条高度
local HP_BAR_OFFSET_Y = -2 -- 血条在角色上方的偏移

--- Spine 容器引用（供增量 AddOne/RemoveOne 使用）
---@type Widget|nil
local spineContainer_ = nil

--- 创建空容器（部署阶段初始化，无角色时使用）
---@return Widget
function M.CreateEmptyContainer()
    spineContainer_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        pointerEvents = "none",
    }
    return spineContainer_
end

--- 为角色列表创建 Spine 控件
---@param characters table[] 逻辑数据列表
---@return Widget spineContainer
function M.CreateSpines(characters)
    local children = {}

    for _, char in ipairs(characters) do
        local def = GetArtDef(char.defId)

        local initFlip = (char.team == "blue")

        local spine
        if def.mode == "sprite_bone" then
            spine = CreateSpriteBonePanel(def)
        else
            spine = UI.Spine {
                src = def.spineSrc,
                animation = def.anims.idle,
                loop = true,
                width = 10,
                height = 10,
                position = "absolute",
                left = 0,
                top = 0,
                flipX = initFlip,
                pma = def.pma,
            }
        end

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

        -- Spine 专属初始化
        if def.mode ~= "sprite_bone" then
            if def.animSpeed and def.animSpeed ~= 1.0 then
                spine:SetTimeScale(def.animSpeed)
            end
            if def.tint then
                spine:SetColor(def.tint.r, def.tint.g, def.tint.b, 1.0)
            end
        end

        -- 存储渲染数据（与逻辑数据分离）
        renderData_[char] = {
            spine = spine,
            currentAnim = def.anims and def.anims.idle or nil,
            lastFlip = initFlip,
            hpBar = hpBg,
            hpFill = hpFill,
            tintApplied = def.tint ~= nil,
            baseWidth = spine.props.width or 48,
            baseHeight = spine.props.height or 64,
            -- sprite_bone 动画状态
            sbAnimPhase = "idle",
            sbAnimTime = 0,
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

    spineContainer_ = container
    print("[CharRender] CreateSpines: created " .. #children .. " widgets (spine + hp bars)")

    return container
end

--- 增量添加单个角色（部署阶段使用）
---@param char table 逻辑数据
function M.AddOne(char)
    if not spineContainer_ then return end
    local def = GetArtDef(char.defId)
    local initFlip = (char.team == "blue")

    local spine
    if def.mode == "sprite_bone" then
        spine = CreateSpriteBonePanel(def)
    else
        spine = UI.Spine {
            src = def.spineSrc,
            animation = def.anims.idle,
            loop = true,
            width = 10, height = 10,
            position = "absolute",
            left = 0, top = 0,
            flipX = initFlip,
            pma = def.pma,
        }
    end

    local hpBg = UI.Panel {
        width = HP_BAR_WIDTH,
        height = HP_BAR_HEIGHT,
        position = "absolute",
        left = 0, top = 0,
        backgroundColor = "#333333",
        borderRadius = 2,
    }
    local hpFill = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = "#44cc44",
        borderRadius = 2,
    }
    hpBg:AddChild(hpFill)

    if def.mode ~= "sprite_bone" then
        if def.animSpeed and def.animSpeed ~= 1.0 then
            spine:SetTimeScale(def.animSpeed)
        end
        if def.tint then
            spine:SetColor(def.tint.r, def.tint.g, def.tint.b, 1.0)
        end
    end

    renderData_[char] = {
        spine = spine,
        currentAnim = def.anims and def.anims.idle or nil,
        lastFlip = initFlip,
        hpBar = hpBg,
        hpFill = hpFill,
        tintApplied = def.tint ~= nil,
        baseWidth = spine.props.width or 48,
        baseHeight = spine.props.height or 64,
        -- sprite_bone 动画状态
        sbAnimPhase = "idle",
        sbAnimTime = 0,
    }

    spineContainer_:AddChild(spine)
    spineContainer_:AddChild(hpBg)
end

--- 增量删除单个角色（部署阶段使用）
---@param char table 逻辑数据
function M.RemoveOne(char)
    local rd = renderData_[char]
    if not rd then return end
    rd.spine:SetVisible(false)
    if rd.hpBar then rd.hpBar:SetVisible(false) end
    renderData_[char] = nil
end

-- ============================================================================
-- sprite_bone 动画插值系统（独立于 Spine，不耦合）
-- ============================================================================

--- 对 sprite_bone 关键帧进行线性插值
---@param frames table 关键帧数据 { ["0"] = { body = {x,y,rot,scaleX,scaleY} }, ... }
---@param duration number 动画总时长
---@param time number 当前时间
---@return table bodyTransform {x, y, rot, scaleX, scaleY}
local function InterpolateSpriteKeyframes(frames, duration, time)
    -- 收集并排序所有时间点
    local keys = {}
    for k in pairs(frames) do
        table.insert(keys, tonumber(k))
    end
    table.sort(keys)

    if #keys == 0 then
        return { x = 0, y = 0, rot = 0, scaleX = 1, scaleY = 1 }
    end

    -- 限制时间在 [0, duration]
    local t = time % duration

    -- 找到 t 所在的两个关键帧之间
    local prevKey = keys[1]
    local nextKey = keys[1]
    for i = 1, #keys do
        if keys[i] <= t then
            prevKey = keys[i]
            nextKey = keys[math.min(i + 1, #keys)]
        else
            nextKey = keys[i]
            break
        end
    end

    local prevFrame = frames[tostring(prevKey)]
    local nextFrame = frames[tostring(nextKey)]
    if not prevFrame or not nextFrame then
        return { x = 0, y = 0, rot = 0, scaleX = 1, scaleY = 1 }
    end

    -- 取 body 骨骼数据
    local prevBody = prevFrame.body or { x = 0, y = 0, rot = 0, scaleX = 1, scaleY = 1 }
    local nextBody = nextFrame.body or { x = 0, y = 0, rot = 0, scaleX = 1, scaleY = 1 }

    -- 计算插值因子
    local alpha = 0
    if nextKey > prevKey then
        alpha = (t - prevKey) / (nextKey - prevKey)
    end

    -- 线性插值
    return {
        x = prevBody.x + (nextBody.x - prevBody.x) * alpha,
        y = prevBody.y + (nextBody.y - prevBody.y) * alpha,
        rot = prevBody.rot + (nextBody.rot - prevBody.rot) * alpha,
        scaleX = prevBody.scaleX + (nextBody.scaleX - prevBody.scaleX) * alpha,
        scaleY = prevBody.scaleY + (nextBody.scaleY - prevBody.scaleY) * alpha,
    }
end

--- 更新 sprite_bone 角色的动画状态
---@param char table 逻辑数据
---@param rd table 渲染数据
---@param dt number 帧时间
---@param def table art 配置
local function UpdateSpriteBoneAnimation(char, rd, dt, def)
    if not def.frames then return end

    -- 确定目标动画阶段
    local targetPhase = char.animState or "idle"
    if not def.frames[targetPhase] then
        targetPhase = "idle"
    end

    -- 阶段切换时重置时间
    if rd.sbAnimPhase ~= targetPhase then
        rd.sbAnimPhase = targetPhase
        rd.sbAnimTime = 0
    end

    -- 推进时间
    rd.sbAnimTime = rd.sbAnimTime + dt

    -- 获取当前阶段配置
    local phaseData = def.frames[targetPhase]
    if not phaseData then return end

    local duration = phaseData.duration or 1.0
    local keyframes = phaseData.keyframes
    if not keyframes then return end

    -- 循环播放（idle/move/relax 循环，attack/hit/die 不循环但在 animState 切走前保持最后帧）
    local loopPhases = { idle = true, move = true, relax = true }
    if loopPhases[targetPhase] then
        -- 循环：取模
        rd.sbAnimTime = rd.sbAnimTime % duration
    else
        -- 非循环：clamp 到最大时长
        if rd.sbAnimTime > duration then
            rd.sbAnimTime = duration
        end
    end

    -- 插值关键帧
    local transform = InterpolateSpriteKeyframes(keyframes, duration, rd.sbAnimTime)
    rd.sbTransform = transform
end

--- 更新动画状态（根据逻辑层的 animState 切换 Spine 动画）
---@param char table 逻辑数据
local function UpdateAnimation(char)
    local rd = renderData_[char]
    if not rd then return end
    -- sprite_bone 模式无 Spine 组件，跳过动画
    if not rd.spine.SetAnimation then return end

    local def = GetArtDef(char.defId)
    local targetAnim = def.anims[char.animState] or def.anims.idle
    local loop = (char.animState == "idle" or char.animState == "move")

    if rd.currentAnim ~= targetAnim then
        rd.spine:SetAnimation(targetAnim, loop)
        rd.currentAnim = targetAnim
    end
end

--- 更新死亡表现（淡出效果，保留 tint 染色）
---@param char table
local function UpdateDyingVisual(char)
    local rd = renderData_[char]
    if not rd then return end
    local Battle = require("logic.Battle")

    if char.state == "dying" then
        local progress = 1.0 - math.max(0, char.deathTimer / Battle.DEATH_DURATION)
        local alpha = 1.0 - progress * 0.8
        if rd.spine.SetColor then
            -- Spine 模式：保留 tint 染色
            local def = GetArtDef(char.defId)
            local tr = (def.tint and def.tint.r) or 1
            local tg = (def.tint and def.tint.g) or 1
            local tb = (def.tint and def.tint.b) or 1
            rd.spine:SetColor(tr, tg, tb, alpha)
        else
            -- sprite_bone 模式：透明度淡出
            rd.spine:SetStyle({ opacity = alpha })
        end
    elseif char.state == "dead" then
        rd.spine:SetVisible(false)
    end
end

--- 每帧更新所有角色的表现（位置、缩放、排序、动画、翻转）
---@param characters table[] 逻辑数据列表
---@param camera Camera
---@param dt number|nil 帧时间（可选，用于 sprite_bone 动画）
function M.Update(characters, camera, dt)
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

    local frameDt = dt or 0.016  -- 默认 ~60fps

    for _, char in ipairs(characters) do
        local rd = renderData_[char]
        if not rd then goto continue end

        -- 更新动画（Spine / sprite_bone 各走各的路径）
        UpdateAnimation(char)
        if rd.sbAnimPhase then
            local def = GetArtDef(char.defId)
            UpdateSpriteBoneAnimation(char, rd, frameDt, def)
        end
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

        -- 直接 scale 系数 = renderScale × perspScale × 体型缩放
        local baseScale = def.renderScale * perspScale
        local scaleValX = baseScale * (def.scaleX or 1.0)
        local scaleValY = baseScale * (def.scaleY or 1.0)
        local scaleVal = baseScale  -- 用于通用定位计算

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
            scaleValX = scaleValX,
            scaleValY = scaleValY,
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

        -- 定位 widget 并控制 spine scale（含体型缩放 scaleX/scaleY）
        if si and si:IsLoaded() then
            local dw = si:GetDataWidth()
            local dh = si:GetDataHeight()
            local flipSign = info.flip and -1 or 1

            if dw > 0 and dh > 0 then
                -- dataW > 0：Render 内部会用 widget 尺寸计算 scale
                -- 反推：为了让 Render 计算出我们想要的 scale，需要设 widget 尺寸 = scaleVal * dataW/H
                local targetW = math.max(1, math.floor(dw * info.scaleValX))
                local targetH = math.max(1, math.floor(dh * info.scaleValY))
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
                si:SetScale(flipSign * info.scaleValX, -info.scaleValY)
            end
        else
            -- sprite_bone 模式或 spineInstance 未加载
            local bw = info.rd.baseWidth or 48
            local bh = info.rd.baseHeight or 64

            -- 应用动画关键帧变换（scaleX/scaleY 影响尺寸）
            local animSX = 1.0
            local animSY = 1.0
            local animOffX = 0
            local animOffY = 0
            local animRot = 0
            local sbT = info.rd.sbTransform
            if sbT then
                animSX = sbT.scaleX or 1.0
                animSY = sbT.scaleY or 1.0
                animOffX = sbT.x or 0
                animOffY = sbT.y or 0
                animRot = sbT.rot or 0
            end

            local targetW = math.max(1, math.floor(bw * info.scaleValX * animSX))
            local targetH = math.max(1, math.floor(bh * info.scaleValY * animSY))

            -- 偏移量（翻转时 x 方向取反）
            local offX = info.flip and -animOffX or animOffX

            spine:SetStyle({
                width = targetW,
                height = targetH,
                left = math.floor(info.sx - targetW / 2 + offX * info.scaleVal),
                top = math.floor(info.sy - targetH + animOffY * info.scaleVal),
                zIndex = i,
                rotate = animRot ~= 0 and animRot or nil,
                transformOrigin = "center",
            })
            -- flipX 由自定义 Render 处理（nvgScale(-1,1)）
            spine.props.flipX = info.flip
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
    spineContainer_ = nil
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
