-- ============================================================================
-- main.lua - 3D 竞技场对战游戏（入口）
-- Spine 2D 角色 + 3D 竞技场 | 45度俯视角
-- ============================================================================
-- 架构：逻辑层（logic/）驱动数据 → 表现层（render/）驱动视觉

local Config = require("Config")
local Arena = require("Arena")
local CharRegistry = require("characters.CharRegistry")
local CharLogic = require("logic.CharLogic")
local Battle = require("logic.Battle")
local AI = require("logic.AI")
local CharRender = require("render.CharRender")
local ProjectileRender = require("render.ProjectileRender")
local GameUI = require("GameUI")
local DeploymentEditor = require("ui.DeploymentEditor")
local CharacterMaker = require("ui.CharacterMaker")

-- ============================================================================
-- 全局状态
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
---@type Camera
local camera_ = nil

--- 角色逻辑数据列表
---@type table[]
local characters_ = {}

--- 游戏状态 "deployment" | "playing" | "redWin" | "blueWin"
local gameState_ = "deployment"

--- 当前使用的角色定义ID
local CHAR_DEF_ID = "wisdel"

--- 部署阶段放置的角色列表（{moduleId, team, worldX, worldZ, char}）
---@type table[]
local deployedUnits_ = {}

--- 部署删除距离阈值（米）
local DEPLOY_REMOVE_DIST = 1.5

--- 战斗开始时双方初始总HP（用于渐变条比例计算）
local redInitialHP_ = 0
local blueInitialHP_ = 0

--- 角色默认碰撞半径（米），用于行动时互相排斥（当角色未配置时的 fallback）
local CHAR_COLLISION_RADIUS_DEFAULT = 0.4

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = Config.Title

    -- 初始化角色注册表（加载预设 + 恢复持久化角色）
    CharRegistry.Init()

    GameUI.Init()
    CreateScene()
    SetupCamera()
    Arena.Create(scene_)

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")

    -- 游戏启动直接进入部署阶段（TABS 风格）
    EnterDeployment()

    print("=== TABS Arena - Deployment Phase ===")
    print("Place your units and press START!")
end

function Stop()
    GameUI.Shutdown()
end

-- ============================================================================
-- 场景与相机
-- ============================================================================

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    -- 加载光照预设
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())
end

function SetupCamera()
    cameraNode_ = scene_:CreateChild("Camera")
    cameraNode_.position = Vector3(0, Config.CameraHeight, -Config.CameraDistance)
    cameraNode_.rotation = Quaternion(55, 0, 0)

    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.nearClip = 0.5
    camera_.farClip = 200.0
    camera_.fov = Config.CameraFOV

    local viewport = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true
end

-- ============================================================================
-- 部署阶段
-- ============================================================================

--- 进入部署阶段
function EnterDeployment()
    -- 清除旧战斗数据
    CharRender.Clear(characters_)
    ProjectileRender.Clear()
    AI.Clear()
    characters_ = {}
    deployedUnits_ = {}

    gameState_ = "deployment"

    -- 创建空 Spine 容器（角色将逐步添加）
    local spineLayer = CharRender.CreateEmptyContainer()

    -- 打开部署 UI（spineLayer 作为底层传入）
    DeploymentEditor.Open({
        spineLayer = spineLayer,
        onStartBattle = function()
            StartBattleFromDeployment()
        end,
        onClear = function()
            ClearDeployedUnits()
        end,
        onOpenMaker = function()
            OpenCharacterMaker()
        end,
    })
end

--- 射线投射到 Y=0 地面平面，返回世界坐标
---@param screenX number 屏幕像素 X
---@param screenY number 屏幕像素 Y
---@return Vector3|nil 交点世界坐标，nil 表示射线不与地面相交
local function ScreenToGround(screenX, screenY)
    local sw = graphics:GetWidth()
    local sh = graphics:GetHeight()
    local nx = screenX / sw
    local ny = screenY / sh

    local ray = camera_:GetScreenRay(nx, ny)
    -- 与 Y=0 平面求交: origin.y + t * direction.y = 0
    if math.abs(ray.direction.y) < 0.0001 then return nil end
    local t = -ray.origin.y / ray.direction.y
    if t < 0 then return nil end

    local hitPos = ray.origin + ray.direction * t
    return hitPos
end

--- 检查位置是否在竞技场内
---@param pos Vector3
---@return boolean
local function IsInsideArena(pos)
    local halfW = Config.ArenaWidth / 2
    local halfD = Config.ArenaDepth / 2
    return math.abs(pos.x) <= halfW and math.abs(pos.z) <= halfD
end

--- 获取位置对应的队伍半场
---@param pos Vector3
---@return string "red" | "blue"
local function GetTeamForPosition(pos)
    -- 红队在左侧 (x < 0)，蓝队在右侧 (x > 0)
    return pos.x < 0 and "red" or "blue"
end

--- 查找离目标位置最近的已部署角色（在删除阈值内）
---@param pos Vector3
---@return number|nil 索引
local function FindNearestDeployed(pos)
    local minDist = DEPLOY_REMOVE_DIST
    local minIdx = nil
    for i, unit in ipairs(deployedUnits_) do
        local dx = unit.worldX - pos.x
        local dz = unit.worldZ - pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < minDist then
            minDist = dist
            minIdx = i
        end
    end
    return minIdx
end

--- 处理部署阶段的点击（放置或删除角色）
---@param screenX number
---@param screenY number
local function HandleDeployClick(screenX, screenY)
    if gameState_ ~= "deployment" then return end
    if not DeploymentEditor.IsOpen() then return end

    local groundPos = ScreenToGround(screenX, screenY)
    if not groundPos then return end
    if not IsInsideArena(groundPos) then
        DeploymentEditor.SetHint("点击竞技场内部放置角色")
        return
    end

    local selected = DeploymentEditor.GetSelectedCard()

    -- 如果没有选中卡且点击附近有角色 → 删除
    if not selected then
        local nearIdx = FindNearestDeployed(groundPos)
        if nearIdx then
            local unit = deployedUnits_[nearIdx]
            -- 从渲染和逻辑中移除
            CharRender.RemoveOne(unit.char)
            for i, c in ipairs(characters_) do
                if c == unit.char then
                    table.remove(characters_, i)
                    break
                end
            end
            table.remove(deployedUnits_, nearIdx)
            UpdateDeployCounts()
            DeploymentEditor.SetHint("已移除角色（选择卡牌可放置新角色）")
            print("[Deploy] Removed unit at " .. string.format("%.1f, %.1f", unit.worldX, unit.worldZ))
        else
            DeploymentEditor.SetHint("选择角色卡，然后点击场地放置")
        end
        return
    end

    -- 检查点击位置是否在所选队伍的半场
    local posTeam = GetTeamForPosition(groundPos)
    if posTeam ~= selected.team then
        DeploymentEditor.SetHint(selected.team == "red" and "红方请放在左半场" or "蓝方请放在右半场")
        return
    end

    -- 放置角色
    local char = CharLogic.Create(selected.moduleId, selected.team, Vector3(groundPos.x, 0, groundPos.z))
    table.insert(characters_, char)
    CharRender.AddOne(char)

    table.insert(deployedUnits_, {
        moduleId = selected.moduleId,
        team = selected.team,
        worldX = groundPos.x,
        worldZ = groundPos.z,
        char = char,
    })

    UpdateDeployCounts()
    DeploymentEditor.SetHint("已放置 - 继续点击场地或选择其他角色")
    print(string.format("[Deploy] Placed %s(%s) at %.1f, %.1f", selected.moduleId, selected.team, groundPos.x, groundPos.z))
end

--- 更新部署计数
function UpdateDeployCounts()
    local redCount = 0
    local blueCount = 0
    for _, unit in ipairs(deployedUnits_) do
        if unit.team == "red" then redCount = redCount + 1
        else blueCount = blueCount + 1 end
    end
    DeploymentEditor.UpdateCounts(redCount, blueCount)
end

--- 清空所有已部署角色
function ClearDeployedUnits()
    for _, unit in ipairs(deployedUnits_) do
        CharRender.RemoveOne(unit.char)
    end
    characters_ = {}
    deployedUnits_ = {}
    UpdateDeployCounts()
    DeploymentEditor.SetHint("已清空，重新选择角色放置")
    print("[Deploy] Cleared all units")
end

-- ============================================================================
-- 角色制作器
-- ============================================================================

--- 打开角色制作器（从部署界面切换过去）
function OpenCharacterMaker()
    -- 关闭部署 UI
    DeploymentEditor.Close()

    -- 打开制作器
    CharacterMaker.Open({
        onClose = function()
            -- 返回部署阶段（重新打开部署 UI，角色卡列表会刷新）
            EnterDeployment()
        end,
        onTestBattle = function(moduleId)
            -- 从制作器发起的测试战斗：放置两个该角色对打
            TestBattleFromMaker(moduleId)
        end,
    })
end

--- 从制作器发起的快速测试战斗
---@param moduleId string
function TestBattleFromMaker(moduleId)
    -- 清除旧数据
    CharRender.Clear(characters_)
    ProjectileRender.Clear()
    AI.Clear()
    characters_ = {}
    deployedUnits_ = {}

    -- 放置两个角色对打（红方左侧，蓝方右侧）
    local redChar = CharLogic.Create(moduleId, "red", Vector3(-3, 0, 0))
    local blueChar = CharLogic.Create(moduleId, "blue", Vector3(3, 0, 0))
    table.insert(characters_, redChar)
    table.insert(characters_, blueChar)

    gameState_ = "playing"

    -- 记录双方初始总HP
    redInitialHP_ = redChar.hp or 0
    blueInitialHP_ = blueChar.hp or 0

    -- CreateBattleHUD 内部会调用 CharRender.CreateSpines 重建 Spine 层
    GameUI.CreateBattleHUD(characters_, function()
        -- 战斗结束后回到部署
        ResetGame()
    end)
    GameUI.ResetStatus()
    print("[Main] Test battle from Maker: " .. moduleId)
end

--- 从部署数据启动战斗
function StartBattleFromDeployment()
    if #deployedUnits_ == 0 then
        DeploymentEditor.SetHint("请至少放置一个角色！")
        return
    end

    -- 关闭部署 UI
    DeploymentEditor.Close()
    gameState_ = "playing"

    -- 记录双方初始总HP
    redInitialHP_ = 0
    blueInitialHP_ = 0
    for _, char in ipairs(characters_) do
        if char.team == "red" then
            redInitialHP_ = redInitialHP_ + (char.hp or 0)
        else
            blueInitialHP_ = blueInitialHP_ + (char.hp or 0)
        end
    end

    -- 重建完整 HUD（CharRender 已有角色 spine，需要重新包装到游戏 HUD）
    GameUI.CreateBattleHUD(characters_, ResetGame)
    GameUI.ResetStatus()
    print("[Main] Battle started! " .. #deployedUnits_ .. " units deployed")
end

-- ============================================================================
-- 游戏逻辑（战斗阶段）
-- ============================================================================

function UpdateGameLogic(dt)
    if gameState_ == "deployment" then
        -- 部署阶段：角色可见但静止（仅更新渲染位置，不更新 AI）
        if #characters_ > 0 then
            CharRender.Update(characters_, camera_, dt)
        end
        return
    end

    if gameState_ ~= "playing" then return end

    local redAlive = 0
    local blueAlive = 0
    local redTotalHP = 0
    local blueTotalHP = 0

    -- 逻辑层更新：AI决策 + 战斗状态
    for _, char in ipairs(characters_) do
        AI.Update(char, characters_, dt)
        Battle.UpdateState(char, dt)

        if char.state ~= "dead" and char.state ~= "dying" then
            if char.team == "red" then
                redAlive = redAlive + 1
                redTotalHP = redTotalHP + (char.hp or 0)
            else
                blueAlive = blueAlive + 1
                blueTotalHP = blueTotalHP + (char.hp or 0)
            end
        end
    end

    -- 碰撞分离：防止角色重叠（简单圆形排斥，使用各自的 collisionRadius）
    for i = 1, #characters_ do
        local a = characters_[i]
        if a.state ~= "dead" and a.state ~= "dying" then
            local radiusA = a.collisionRadius or CHAR_COLLISION_RADIUS_DEFAULT
            for j = i + 1, #characters_ do
                local b = characters_[j]
                if b.state ~= "dead" and b.state ~= "dying" then
                    local radiusB = b.collisionRadius or CHAR_COLLISION_RADIUS_DEFAULT
                    local minDist = radiusA + radiusB
                    local dx = b.worldPos.x - a.worldPos.x
                    local dz = b.worldPos.z - a.worldPos.z
                    local dist = math.sqrt(dx * dx + dz * dz)
                    if dist < minDist and dist > 0.001 then
                        -- 计算分离量（各推一半）
                        local overlap = (minDist - dist) * 0.5
                        local invDist = 1.0 / dist
                        local nx = dx * invDist
                        local nz = dz * invDist
                        a.worldPos = Vector3(
                            a.worldPos.x - nx * overlap,
                            a.worldPos.y,
                            a.worldPos.z - nz * overlap
                        )
                        b.worldPos = Vector3(
                            b.worldPos.x + nx * overlap,
                            b.worldPos.y,
                            b.worldPos.z + nz * overlap
                        )
                    end
                end
            end
        end
    end

    -- 投射物：收集新发射的 + 更新飞行中的
    ProjectileRender.Collect(characters_)
    ProjectileRender.Update(camera_, dt)

    -- 表现层更新：Spine 位置/缩放/排序/动画/翻转
    CharRender.Update(characters_, camera_, dt)

    -- HUD 更新
    GameUI.UpdateCounts(redAlive, blueAlive)
    -- 传入HP系数（当前HP/初始HP）
    local redRatio = redInitialHP_ > 0 and (redTotalHP / redInitialHP_) or 0
    local blueRatio = blueInitialHP_ > 0 and (blueTotalHP / blueInitialHP_) or 0
    GameUI.UpdateHPRatio(redRatio, blueRatio)

    -- 胜负判定
    if redAlive == 0 then
        gameState_ = "blueWin"
        GameUI.ShowResult("BLUE TEAM WINS!")
        print("Blue team wins!")
    elseif blueAlive == 0 then
        gameState_ = "redWin"
        GameUI.ShowResult("RED TEAM WINS!")
        print("Red team wins!")
    end
end

--- 重置游戏 → 回到部署阶段
function ResetGame()
    EnterDeployment()
    print("=== Back to Deployment Phase ===")
end

-- ============================================================================
-- 事件
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    UpdateGameLogic(dt)
end

---@param eventType string
---@param eventData table
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    HandleDeployClick(x, y)
end

---@param eventType string
---@param eventData table
function HandleTouchBegin(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    HandleDeployClick(x, y)
end
