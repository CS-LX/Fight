-- ============================================================================
-- main.lua - 3D 竞技场对战游戏（入口）
-- Spine 2D 角色 + 3D 竞技场 | 45度俯视角
-- ============================================================================
-- 架构：逻辑层（logic/）驱动数据 → 表现层（render/）驱动视觉

local Config = require("Config")
local Arena = require("Arena")
local CharLogic = require("logic.CharLogic")
local Battle = require("logic.Battle")
local AI = require("logic.AI")
local CharRender = require("render.CharRender")
local GameUI = require("GameUI")

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

--- 游戏状态 "playing" | "redWin" | "blueWin"
local gameState_ = "playing"

--- 当前使用的角色定义ID
local CHAR_DEF_ID = "wisdel"

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = Config.Title

    GameUI.Init()
    CreateScene()
    SetupCamera()
    Arena.Create(scene_)
    characters_ = CharLogic.SpawnTeams(CHAR_DEF_ID)
    GameUI.CreateHUD(characters_, ResetGame)
    SubscribeToEvent("Update", "HandleUpdate")

    print("=== 3D Arena Battle Started (Modular) ===")
    print("Red Team vs Blue Team, " .. Config.TeamSize .. " vs " .. Config.TeamSize)
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
-- 游戏逻辑
-- ============================================================================

function UpdateGameLogic(dt)
    if gameState_ ~= "playing" then return end

    local redAlive = 0
    local blueAlive = 0

    -- 逻辑层更新：AI决策 + 战斗状态
    for _, char in ipairs(characters_) do
        AI.Update(char, characters_, dt)
        Battle.UpdateState(char, dt)

        if char.state ~= "dead" and char.state ~= "dying" then
            if char.team == "red" then
                redAlive = redAlive + 1
            else
                blueAlive = blueAlive + 1
            end
        end
    end

    -- 表现层更新：Spine 位置/缩放/排序/动画/翻转
    CharRender.Update(characters_, camera_)

    -- HUD 更新
    GameUI.UpdateCounts(redAlive, blueAlive)

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

--- 重置游戏
function ResetGame()
    -- 清除旧渲染数据
    CharRender.Clear(characters_)
    characters_ = {}

    -- 重新生成逻辑数据
    characters_ = CharLogic.SpawnTeams(CHAR_DEF_ID)
    gameState_ = "playing"

    -- 重建 UI（含新 Spine 层）
    GameUI.CreateHUD(characters_, ResetGame)
    GameUI.ResetStatus()
    print("=== Game Reset ===")
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
