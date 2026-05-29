-- ============================================================================
-- main.lua - 3D 竞技场对战游戏（入口）
-- Spine 2D 角色 + 3D 竞技场 | 45度俯视角
-- ============================================================================

local Config = require("Config")
local Arena = require("Arena")
local Character = require("Character")
local Battle = require("Battle")
local AI = require("AI")
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

--- 角色数据列表
---@type table[]
local characters_ = {}

--- 游戏状态 "playing" | "redWin" | "blueWin"
local gameState_ = "playing"

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = Config.Title

    GameUI.Init()
    CreateScene()
    SetupCamera()
    Arena.Create(scene_)
    characters_ = Character.SpawnTeams()
    GameUI.CreateHUD(characters_, ResetGame)
    SubscribeToEvent("Update", "HandleUpdate")

    print("=== 3D Arena Battle Started (Spine) ===")
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

    for _, char in ipairs(characters_) do
        AI.Update(char, characters_, dt)
        Battle.UpdateAnimation(char, dt)

        if char.state ~= "dead" and char.state ~= "dying" then
            if char.team == "red" then
                redAlive = redAlive + 1
            else
                blueAlive = blueAlive + 1
            end
        end
    end

    -- 更新 Spine 角色屏幕位置
    GameUI.UpdateSpinePositions(characters_, camera_)

    -- 更新UI计数
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
    -- 清除旧 Spine 控件
    GameUI.ClearSpines(characters_)
    characters_ = {}

    -- 重新生成
    characters_ = Character.SpawnTeams()
    gameState_ = "playing"

    -- 重建 UI
    GameUI.RebuildHUD(characters_, ResetGame)
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
