-- ============================================================================
-- render/ProjectileRender.lua - 投射物渲染系统
-- ============================================================================
-- 职责：消费 char.projectiles 列表，创建飞行 widget 并驱动位移，命中时造成伤害
-- 依赖：UI 系统、Camera（世界坐标 → 屏幕坐标）

local UI = require("urhox-libs/UI")
local CharRender = require("render.CharRender")

local M = {}

--- 活跃投射物列表
---@type table[]
local activeProjectiles_ = {}

--- 投射物尺寸（像素）
local PROJ_SIZE = 24

--- 收集所有角色的 projectiles 数据并生成飞行实体
---@param characters table[]
function M.Collect(characters)
    local container = CharRender.GetContainer()
    if not container then return end

    for _, char in ipairs(characters) do
        if char.projectiles and #char.projectiles > 0 then
            for _, pdata in ipairs(char.projectiles) do
                -- 创建 widget（UI 系统用 Panel + backgroundImage 显示图片）
                local hasBulletImg = pdata.bulletEffect and pdata.bulletEffect ~= ""
                local sprite = UI.Panel {
                    backgroundImage = hasBulletImg and pdata.bulletEffect or nil,
                    backgroundFit = "contain",
                    backgroundColor = (not hasBulletImg) and (pdata.bulletColor or "#ffff00") or nil,
                    width = PROJ_SIZE,
                    height = PROJ_SIZE,
                    borderRadius = PROJ_SIZE / 2,
                    position = "absolute",
                    left = -100,
                    top = -100,
                    zIndex = 999,
                }
                container:AddChild(sprite)

                -- 记录飞行实体
                activeProjectiles_[#activeProjectiles_ + 1] = {
                    widget = sprite,
                    fromPos = pdata.fromPos,
                    targetChar = pdata.targetChar,
                    speed = pdata.speed or 8,
                    damage = pdata.damage or 10,
                    -- 当前位置（从发射点开始）
                    pos = Vector3(pdata.fromPos.x, pdata.fromPos.y, pdata.fromPos.z),
                    alive = true,
                }
            end
            -- 清空已消费数据
            char.projectiles = {}
        end
    end
end

--- 更新所有飞行中的投射物
---@param camera Component 相机
---@param dt number 帧时间
function M.Update(camera, dt)
    if #activeProjectiles_ == 0 then return end

    local uiScale = UI.GetScale()
    local screenW = graphics:GetWidth() / uiScale
    local screenH = graphics:GetHeight() / uiScale

    local i = 1
    while i <= #activeProjectiles_ do
        local proj = activeProjectiles_[i]
        if not proj.alive then
            -- 移除已死亡的投射物
            if proj.widget then
                local parent = proj.widget.parent
                if parent then
                    parent:RemoveChild(proj.widget)
                end
            end
            table.remove(activeProjectiles_, i)
        else
            -- 计算朝目标飞行
            local target = proj.targetChar
            if not target or target.state == "dead" then
                -- 目标死亡，投射物消失
                proj.alive = false
            else
                local targetPos = Vector3(target.worldPos.x, target.worldPos.y + 0.8, target.worldPos.z)
                local dx = targetPos.x - proj.pos.x
                local dy = targetPos.y - proj.pos.y
                local dz = targetPos.z - proj.pos.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                if dist < 0.3 then
                    -- 命中！
                    if target.state ~= "dead" and target.state ~= "dying" then
                        target.hp = target.hp - proj.damage
                        if target.hp <= 0 then
                            target.hp = 0
                            target.state = "dying"
                            target.deathTimer = 1.2
                            target.animState = "die"
                        else
                            target.animState = "hit"
                            target.animTimer = 0.3
                            target.hitFlag = true
                        end
                    end
                    proj.alive = false
                else
                    -- 移动
                    local step = proj.speed * dt
                    local invDist = 1.0 / dist
                    proj.pos = Vector3(
                        proj.pos.x + dx * invDist * step,
                        proj.pos.y + dy * invDist * step,
                        proj.pos.z + dz * invDist * step
                    )

                    -- 世界坐标 → 屏幕坐标
                    local screenPos = camera:WorldToScreenPoint(proj.pos)
                    local sx = screenPos.x * screenW
                    local sy = screenPos.y * screenH



                    proj.widget:SetStyle({
                        left = math.floor(sx - PROJ_SIZE / 2),
                        top = math.floor(sy - PROJ_SIZE / 2),
                    })
                end
            end

            i = i + 1
        end
    end
end

--- 清除所有投射物
function M.Clear()
    for _, proj in ipairs(activeProjectiles_) do
        if proj.widget then
            local parent = proj.widget.parent
            if parent then
                parent:RemoveChild(proj.widget)
            end
        end
    end
    activeProjectiles_ = {}
end

--- 获取活跃投射物数量（调试用）
---@return number
function M.GetActiveCount()
    return #activeProjectiles_
end

return M
