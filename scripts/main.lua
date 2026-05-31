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
local Workshop = require("ui.Workshop")
local Lobby = require("ui.Lobby")
local Economy = require("economy.Economy")
local AIDeployer = require("logic.AIDeployer")
local Ranked = require("economy.Ranked")
local CloudScore = require("economy.CloudScore")
local SponsorPool = require("economy.SponsorPool")
local AIProfile = require("logic.AIProfile")
local Anim = require("ui.UIAnimations")
local UI = require("urhox-libs/UI")
-- LLM 网络模块（当前仅预留，需 persistent_world 服务端支持）
-- local LLMClient = require("network.Client")

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

--- 游戏状态 "lobby" | "deployment" | "playing" | "redWin" | "blueWin" | "spectating"
local gameState_ = "lobby"

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

--- 赞助观战中的状态
---@type {betAmount: number, betTeam: string}|nil
local spectateState_ = nil

--- 是否排位对战模式
local isRankedBattle_ = false

--- 上次战斗的部署费用（结算时显示）
local lastDeployCost_ = 0

--- 沙盒测试模式（不触发经济结算）
local sandboxMode_ = false

--- 当前对战 AI Profile（头像+昵称）
---@type {name: string, avatar: string, tier: string, tierName: string}|nil
local currentAIProfile_ = nil

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = Config.Title

    -- 初始化角色注册表（加载预设 + 恢复持久化角色）
    CharRegistry.Init()

    -- 初始化经济系统
    Economy.Init()
    SponsorPool.Init()
    Ranked.Init()

    GameUI.Init()
    CreateScene()
    SetupCamera()
    Arena.Create(scene_)

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")

    -- 循环背景音乐
    local bgm = cache:GetResource("Sound", "audio/Carefree.ogg")
    if not bgm then
        bgm = cache:GetResource("Sound", "audio/Carefree.mp3")
    end
    if bgm then
        bgm.looped = true
        local bgmNode = scene_:CreateChild("BGM")
        local bgmSource = bgmNode:CreateComponent("SoundSource")
        bgmSource:SetSoundType("Music")
        bgmSource.gain = 0.35
        bgmSource:Play(bgm)
    end

    -- 异步获取 TapTap 昵称（用于玩家 Profile 显示）
    AIProfile.FetchPlayerNickname()

    -- 首次进入时显示 Splash（2秒后淡出进入大厅）
    ShowSplash()

    print("=== TABS Arena - Splash ===")
end

function Stop()
    GameUI.Shutdown()
end

-- ============================================================================
-- Splash 启动画面（每次session首次进入时显示一次）
-- ============================================================================

local splashShown_ = false

function ShowSplash()
    if splashShown_ then
        EnterLobby()
        return
    end
    splashShown_ = true
    gameState_ = "splash"

    local splashPanel = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 255 },
        justifyContent = "center",
        alignItems = "center",
        transition = "opacity 0.6s easeOut",
        opacity = 1.0,
        children = {
            UI.Panel {
                width = 360,
                height = 200,
                backgroundImage = "image/Gemini_Generated_Image_6mnnav6mnnav6mnn.png",
                backgroundFit = "contain",
            },
        },
    }
    UI.SetRoot(splashPanel)

    -- 2秒后开始淡出
    splashTimer_ = 2.0
    splashFading_ = false
    splashPanel_ = splashPanel
end

function UpdateSplash(dt)
    if gameState_ ~= "splash" then return end
    splashTimer_ = splashTimer_ - dt
    if splashTimer_ <= 0 and not splashFading_ then
        splashFading_ = true
        splashPanel_:SetStyle({ opacity = 0 })
        -- 淡出动画 0.6s 后进入大厅
        splashFadeTimer_ = 0.6
    end
    if splashFading_ then
        splashFadeTimer_ = splashFadeTimer_ - dt
        if splashFadeTimer_ <= 0 then
            gameState_ = "lobby"
            UI.SetRoot(nil)
            EnterLobby()
        end
    end
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
-- 大厅阶段
-- ============================================================================

--- 进入大厅（游戏主入口）
function EnterLobby()
    -- 清除旧战斗数据
    CharRender.Clear(characters_)
    ProjectileRender.Clear()
    AI.Clear()
    characters_ = {}
    deployedUnits_ = {}

    gameState_ = "lobby"

    isRankedBattle_ = false

    Lobby.Open({
        onBattle = function()
            EnterDeployment(false)
        end,
        onRanked = function()
            EnterDeployment(true)
        end,
        onSpectate = function()
            EnterSpectateSetup()
        end,
        onMaker = function()
            OpenCharacterMakerFromLobby()
        end,
        onSandbox = function()
            EnterSandboxDeployment()
        end,
    })


end

-- ============================================================================
-- 沙盒模式部署
-- ============================================================================

--- 进入沙盒部署（双方可放置，无费用，无经济结算）
function EnterSandboxDeployment()
    -- 清除旧战斗数据
    CharRender.Clear(characters_)
    ProjectileRender.Clear()
    AI.Clear()
    characters_ = {}
    deployedUnits_ = {}

    isRankedBattle_ = false
    sandboxMode_ = true
    lastDeployCost_ = 0
    gameState_ = "deployment"

    -- 创建空 Spine 容器
    local spineLayer = CharRender.CreateEmptyContainer()

    -- 沙盒模式无 AI Profile
    currentAIProfile_ = { name = "沙盒", avatar = "", tier = "sandbox", tierName = "沙盒" }

    -- 打开部署 UI（pvp 模式，双方都可手动放置）
    DeploymentEditor.Open({
        spineLayer = spineLayer,
        mode = "pvp",
        onStartBattle = function()
            StartBattleFromDeployment()
        end,
        onClear = function()
            ClearDeployedUnits()
        end,
        onOpenMaker = function()
            OpenCharacterMaker()
        end,
        onBack = function()
            DeploymentEditor.Close()
            sandboxMode_ = false
            EnterLobby()
        end,
    })

    print("[Main] Sandbox deployment entered (free placement, both sides)")
end

-- ============================================================================
-- 部署阶段
-- ============================================================================

--- 进入部署阶段
---@param ranked boolean 是否排位模式
function EnterDeployment(ranked)
    -- 清除旧战斗数据
    CharRender.Clear(characters_)
    ProjectileRender.Clear()
    AI.Clear()
    characters_ = {}
    deployedUnits_ = {}

    isRankedBattle_ = ranked or false
    gameState_ = "deployment"

    -- 创建空 Spine 容器（角色将逐步添加）
    local spineLayer = CharRender.CreateEmptyContainer()

    -- PvAI 模式：部署 AI 蓝方角色（本地阵型 AI）
    -- AI teamSize 基于玩家经济水平：玩家金币能买多少单位，AI 就匹配 70~90%
    local aiConfig
    if ranked then
        aiConfig = Ranked.GetAIConfig()
    else
        local playerGold = Economy.GetBalance()
        local costPerUnit = Economy.Config.DEPLOY_COST_PER_UNIT
        local playerMaxUnits = math.floor(playerGold / costPerUnit)
        -- AI 部署数 = 玩家最大部署数的 70%~90%，至少3个，最多8个
        local aiSize = math.max(3, math.min(8, math.floor(playerMaxUnits * (0.7 + math.random() * 0.2))))
        aiConfig = { teamSize = aiSize, statMultiplier = 1.0 }
    end
    local aiChars, aiTotalPV = AIDeployer.DeployPvAI(aiConfig.teamSize, nil, aiConfig.statMultiplier)
    for _, char in ipairs(aiChars) do
        table.insert(characters_, char)
    end
    -- 渲染 AI 角色
    for _, char in ipairs(characters_) do
        CharRender.AddOne(char)
    end

    -- 根据 AI 子力生成对应 Profile
    currentAIProfile_ = AIProfile.GenerateProfile(aiTotalPV or 200)
    print(string.format("[Deploy] AI blue pre-deployed %d units (PV=%.0f, tier=%s, name=%s)",
        aiConfig.teamSize, aiTotalPV or 0, currentAIProfile_.tier, currentAIProfile_.name))

    -- 打开部署 UI（spineLayer 作为底层传入）
    DeploymentEditor.Open({
        spineLayer = spineLayer,
        mode = "pvai",
        onStartBattle = function()
            StartBattleFromDeployment()
        end,
        onClear = function()
            ClearDeployedUnits()
        end,
        onOpenMaker = function()
            OpenCharacterMaker()
        end,
        onBack = function()
            DeploymentEditor.Close()
            EnterLobby()
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
    local posTeam = GetTeamForPosition(groundPos)

    -- pvai 模式下，限制只能放在红方半场（沙盒模式无此限制）
    if not sandboxMode_ and posTeam ~= "red" then
        DeploymentEditor.SetHint("蓝方由 AI 控制，请在左半场放置你的角色")
        return
    end

    -- 如果没有选中卡且点击附近有角色 → 删除
    if not selected then
        local nearIdx = FindNearestDeployed(groundPos)
        if nearIdx then
            local unit = deployedUnits_[nearIdx]
            -- 非沙盒模式退还部署费用
            if not sandboxMode_ then
                local refund = unit.cost or Economy.CalcActualDeployCost(1, isRankedBattle_)
                Economy.Earn(refund, "撤回角色:" .. (unit.moduleId or "?"))
                DeploymentEditor.SetHint("已移除 (+" .. refund .. "G 退还)")
                print("[Deploy] Removed unit at " .. string.format("%.1f, %.1f, refund %dG", unit.worldX, unit.worldZ, refund))
            else
                DeploymentEditor.SetHint("已移除")
                print("[Deploy] Sandbox removed unit at " .. string.format("%.1f, %.1f", unit.worldX, unit.worldZ))
            end
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
            DeploymentEditor.RefreshGold()
        else
            DeploymentEditor.SetHint(sandboxMode_ and "选择角色卡，点击场地放置" or "选择角色卡，然后点击左半场放置")
        end
        return
    end

    -- 非沙盒模式：选中的卡强制为红方，位置必须匹配队伍半场
    if not sandboxMode_ then
        if posTeam ~= selected.team then
            DeploymentEditor.SetHint("红方请放在左半场")
            return
        end
    else
        -- 沙盒模式：位置必须匹配选中卡的队伍半场
        if posTeam ~= selected.team then
            local hint = selected.team == "red" and "红方角色请放在左半场" or "蓝方角色请放在右半场"
            DeploymentEditor.SetHint(hint)
            return
        end
    end

    -- 沙盒模式免费，普通模式需检查并扣费
    local unitCost = 0
    if not sandboxMode_ then
        unitCost = Economy.CalcActualDeployCost(1, isRankedBattle_)
        if not Economy.CanAfford(unitCost) then
            DeploymentEditor.SetHint("金币不足! 需要 " .. unitCost .. "G (拥有 " .. Economy.GetBalance() .. "G)")
            return
        end
        Economy.Spend(unitCost, "部署角色:" .. selected.moduleId)
        DeploymentEditor.PlayGoldSpendAnim(unitCost)
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
        cost = unitCost,
    })

    UpdateDeployCounts()
    if sandboxMode_ then
        DeploymentEditor.SetHint("已放置 [免费] 继续点击放置")
    else
        DeploymentEditor.SetHint("已放置 (-" .. unitCost .. "G) 继续点击或选择其他角色")
    end
    print(string.format("[Deploy] Placed %s(%s) at %.1f, %.1f, cost %dG", selected.moduleId, selected.team, groundPos.x, groundPos.z, unitCost))
end

--- 更新部署计数（红方从 deployedUnits_ 统计，蓝方从 characters_ 统计）
function UpdateDeployCounts()
    local redCount = 0
    local blueCount = 0
    for _, unit in ipairs(deployedUnits_) do
        if unit.team == "red" then redCount = redCount + 1 end
    end
    for _, char in ipairs(characters_) do
        if char.team == "blue" then blueCount = blueCount + 1 end
    end
    DeploymentEditor.UpdateCounts(redCount, blueCount)
end

--- 清空玩家部署的角色（保留 AI 蓝方预部署角色）
function ClearDeployedUnits()
    -- 计算总退款
    local totalRefund = 0
    -- 移除玩家手动放置的角色
    for _, unit in ipairs(deployedUnits_) do
        totalRefund = totalRefund + (unit.cost or 0)
        CharRender.RemoveOne(unit.char)
        for i, c in ipairs(characters_) do
            if c == unit.char then
                table.remove(characters_, i)
                break
            end
        end
    end
    -- 退还全部费用（沙盒模式不涉及经济）
    if not sandboxMode_ and totalRefund > 0 then
        Economy.Earn(totalRefund, "清空部署退款")
    end
    deployedUnits_ = {}
    UpdateDeployCounts()
    DeploymentEditor.RefreshGold()
    if sandboxMode_ then
        DeploymentEditor.SetHint("已清空（沙盒模式）")
    else
        DeploymentEditor.SetHint("已清空 (+" .. totalRefund .. "G 退还)")
    end
    print(string.format("[Deploy] Cleared player units, refund %dG (sandbox=%s)", totalRefund, tostring(sandboxMode_)))
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
            EnterDeployment(false)
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
    -- 开启沙盒模式（不触发经济结算）
    sandboxMode_ = true
    lastDeployCost_ = 0

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
    print("[Main] Sandbox test battle: " .. moduleId)
end

--- 从部署数据启动战斗
function StartBattleFromDeployment()
    if #deployedUnits_ == 0 then
        DeploymentEditor.SetHint("请至少放置一个角色！")
        return
    end

    -- 费用已在放置时逐个扣除，这里只汇总用于结算显示
    local totalSpent = 0
    for _, unit in ipairs(deployedUnits_) do
        totalSpent = totalSpent + (unit.cost or 0)
    end
    lastDeployCost_ = totalSpent

    -- AI 蓝方角色已在 EnterDeployment 阶段预部署（characters_ 中已有）
    -- 这里不再重复部署

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

    -- 赞助池：开启新一场 + AI 观众投注
    SponsorPool.BeginMatch()
    local redStr, blueStr = 0, 0
    for _, char in ipairs(characters_) do
        if char.team == "red" then
            redStr = redStr + (char.hp or 0)
        else
            blueStr = blueStr + (char.hp or 0)
        end
    end
    SponsorPool.SimulateAIBets(redStr, blueStr)

    -- 重建完整 HUD（CharRender 已有角色 spine，需要重新包装到游戏 HUD）
    local playerProfile = AIProfile.GetPlayerProfile()
    GameUI.CreateBattleHUD(characters_, function()
        SettleBattleResult()
    end, {
        redProfile = playerProfile,
        blueProfile = currentAIProfile_,
    })
    GameUI.ResetStatus()
    print("[Main] Battle started! " .. #deployedUnits_ .. " units deployed" ..
        (isRankedBattle_ and " [RANKED]" or ""))
end

-- ============================================================================
-- 游戏逻辑（战斗阶段）
-- ============================================================================

function UpdateGameLogic(dt)
    if gameState_ == "deployment" or gameState_ == "spectating" then
        -- 部署/观战准备阶段：角色可见但静止（仅更新渲染位置，不更新 AI）
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

-- ============================================================================
-- 战斗结算（普通 + 排位统一入口）
-- ============================================================================

--- 战斗结束后统一结算
function SettleBattleResult()
    -- 观战模式走独立结算
    if spectateState_ then
        SettleSpectateResult()
        return
    end

    -- 沙盒测试模式：只显示结果，不触发经济
    if sandboxMode_ then
        sandboxMode_ = false
        local winTeam = gameState_ == "redWin" and "red" or "blue"
        local title = "沙盒测试 - " .. (winTeam == "red" and "红方胜" or "蓝方胜")
        local items = {
            { label = "模式", amount = 0, unit = "沙盒" },
            { label = "提示", amount = 0, unit = "无经济影响" },
        }
        GameUI.ShowSettlement(title, true, items, function()
            EnterLobby()
        end)
        return
    end

    -- 判断胜负（当前规则：玩家部署了哪方？默认 red 为玩家方）
    local playerTeam = "red"
    for _, u in ipairs(deployedUnits_) do
        if u.team == "blue" then playerTeam = "blue"; break end
    end
    -- 如果两边都有，以红方为玩家方
    local playerHasRed = false
    for _, u in ipairs(deployedUnits_) do
        if u.team == "red" then playerHasRed = true; break end
    end
    if playerHasRed then playerTeam = "red" end

    local winTeam = gameState_ == "redWin" and "red" or "blue"
    local playerWon = (winTeam == playerTeam)

    -- 计算敌方数量
    local enemyCount = 0
    for _, char in ipairs(characters_) do
        if char.team ~= playerTeam then
            enemyCount = enemyCount + 1
        end
    end

    -- 赞助池结算：选手从池中获得分成
    local poolResult = SponsorPool.SettleMatch(winTeam)
    local fighterBonus = playerWon and poolResult.winnerShare or poolResult.loserShare

    -- 收集结算明细
    local items = {}
    table.insert(items, { label = "部署费用", amount = -lastDeployCost_ })

    if isRankedBattle_ then
        -- 排位结算：积分 + 奖励倍数 + 赞助池分成
        local scoreChange = Ranked.RecordMatch(playerWon)
        -- 胜利时同步到云端排行榜
        if playerWon then
            CloudScore.RecordWin()
        end
        local reward = Ranked.CalcReward(playerWon, enemyCount)
        local totalReward = reward + fighterBonus
        if totalReward > 0 then
            local label = playerWon
                and ("排位胜利(" .. winTeam .. ") +" .. scoreChange .. "pt")
                or ("排位失败安慰")
            Economy.Earn(totalReward, label)
        end
        table.insert(items, { label = "战斗奖励", amount = reward })
        if fighterBonus > 0 then
            table.insert(items, { label = "赞助池分成", amount = fighterBonus })
        end
        table.insert(items, { label = "段位积分", amount = scoreChange, unit = "pt" })
        print(string.format("[Ranked] Result: %s, score %+d → %d (%s), reward %dG + pool %dG",
            playerWon and "WIN" or "LOSE", scoreChange, Ranked.GetScore(),
            Ranked.GetTierName(), reward, fighterBonus))
    else
        -- 普通AI对战结算 + 赞助池分成
        local reward = Economy.CalcBattleReward(playerWon, enemyCount)
        local totalReward = reward + fighterBonus
        if totalReward > 0 then
            Economy.Earn(totalReward, "对战" .. (playerWon and "胜利" or "失败") .. "(" .. winTeam .. ")")
        end
        table.insert(items, { label = "战斗奖励", amount = reward })
        if fighterBonus > 0 then
            table.insert(items, { label = "赞助池分成", amount = fighterBonus })
        end
    end

    -- 连胜创造晶奖励 (Phase 3)
    local crystalEarned = Economy.ProcessBattleWinStreak(playerWon)
    if crystalEarned > 0 then
        table.insert(items, { label = "创造晶", amount = crystalEarned, unit = "◆" })
    end

    -- 显示结算面板（用户点击后回大厅）
    local title = playerWon and "VICTORY!" or "DEFEAT"
    GameUI.ShowSettlement(title, playerWon, items, function()
        EnterLobby()
    end)
end

--- 重置游戏 → 回到大厅
function ResetGame()
    EnterLobby()
    print("=== Back to Lobby ===")
end

-- ============================================================================
-- 赞助观战模式
-- ============================================================================

--- 进入赞助观战设置（选择押注）
function EnterSpectateSetup()
    gameState_ = "spectating"
    spectateState_ = { betAmount = 0, betTeam = "red" }

    -- 智能生成均衡的两支AI队伍（阵型 + 实力均衡）
    CharRender.Clear(characters_)
    ProjectileRender.Clear()
    AI.Clear()
    characters_ = {}

    -- 使用智能部署系统生成均衡双方（LLM 模式下同样先用本地 AI 生成，后续可扩展）
    local redChars, blueChars = AIDeployer.DeploySpectateBalanced()
    local redCount = #redChars
    local blueCount = #blueChars

    for _, char in ipairs(redChars) do
        table.insert(characters_, char)
    end
    for _, char in ipairs(blueChars) do
        table.insert(characters_, char)
    end

    -- 记录初始HP
    redInitialHP_ = 0
    blueInitialHP_ = 0
    for _, char in ipairs(characters_) do
        if char.team == "red" then
            redInitialHP_ = redInitialHP_ + (char.hp or 0)
        else
            blueInitialHP_ = blueInitialHP_ + (char.hp or 0)
        end
    end

    -- 创建 Spine 容器并渲染 AI 双方角色（让玩家在投注时能看到阵容）
    local spineLayer = CharRender.CreateEmptyContainer()
    for _, char in ipairs(characters_) do
        CharRender.AddOne(char)
    end

    -- 显示赞助观战 UI（押注选择 + 战斗HUD）
    local SpectateUI = require("ui.SpectateUI")
    SpectateUI.Open({
        spineLayer = spineLayer,
        redCount = redCount,
        blueCount = blueCount,
        characters = characters_,
        onConfirmBet = function(betAmount, betTeam)
            spectateState_.betAmount = betAmount
            spectateState_.betTeam = betTeam
            -- 扣除押注金
            if betAmount > 0 then
                Economy.Spend(betAmount, "赞助押注(" .. betTeam .. ")")
            end
            -- 启动战斗
            StartSpectatedBattle()
        end,
        onSkipBet = function()
            -- 不押注，直接观战
            spectateState_.betAmount = 0
            spectateState_.betTeam = ""
            StartSpectatedBattle()
        end,
        onCancel = function()
            EnterLobby()
        end,
    })

    print("[Main] Spectate setup: " .. redCount .. " vs " .. blueCount)
end

--- 启动观战战斗
function StartSpectatedBattle()
    gameState_ = "playing"

    -- 赞助池：开启新一场，加入玩家押注 + AI 观众投注
    SponsorPool.BeginMatch()
    if spectateState_ and spectateState_.betAmount > 0 then
        SponsorPool.AddBet(spectateState_.betAmount, spectateState_.betTeam, "player")
    end
    local redStr, blueStr = 0, 0
    for _, char in ipairs(characters_) do
        if char.team == "red" then
            redStr = redStr + (char.hp or 0)
        else
            blueStr = blueStr + (char.hp or 0)
        end
    end
    SponsorPool.SimulateAIBets(redStr, blueStr)

    GameUI.CreateBattleHUD(characters_, function()
        -- 战斗结束时结算
        SettleSpectateResult()
    end)
    GameUI.ResetStatus()
    print("[Main] Spectated battle started!")
end

--- 观战结算（通过赞助池分配奖金）
function SettleSpectateResult()
    local winTeam = gameState_ == "redWin" and "red" or "blue"
    local betAmount = spectateState_ and spectateState_.betAmount or 0
    local betTeam = spectateState_ and spectateState_.betTeam or ""

    -- 赞助池结算
    local poolResult = SponsorPool.SettleMatch(winTeam)

    local guessCorrect = (betAmount > 0) and (betTeam == winTeam)

    -- 收集结算明细
    local items = {}
    local playerWon = false

    if guessCorrect and poolResult.winBets > 0 then
        -- 玩家押对：按投注比例获得赞助商分成（返还本金 + 利润）
        playerWon = true
        local playerShare = math.floor(poolResult.sponsorPayout * betAmount / poolResult.winBets)
        local totalReturn = betAmount + playerShare
        Economy.Earn(totalReturn, "赞助观战-猜对(" .. winTeam .. "胜)")
        table.insert(items, { label = "押注(" .. betTeam .. "方)", amount = -betAmount })
        table.insert(items, { label = "返还本金", amount = betAmount })
        table.insert(items, { label = "赞助池分红", amount = playerShare })
        print(string.format("[Spectate] Won! bet=%d, share=%d/%d of sponsor %dG, return=%dG",
            betAmount, betAmount, poolResult.winBets, poolResult.sponsorPayout, totalReturn))
    elseif betAmount > 0 and not guessCorrect then
        -- 玩家押错：本金已扣除（lost），仅给参与奖
        Economy.Earn(Economy.Config.SPECTATE_BASE_REWARD, "观战参与奖")
        table.insert(items, { label = "押注(" .. betTeam .. "方)", amount = -betAmount })
        table.insert(items, { label = "参与奖", amount = Economy.Config.SPECTATE_BASE_REWARD })
        print(string.format("[Spectate] Lost bet=%d on %s, winner=%s", betAmount, betTeam, winTeam))
    else
        -- 未押注：仅参与奖
        Economy.Earn(Economy.Config.SPECTATE_BASE_REWARD, "观战参与奖")
        table.insert(items, { label = "观战参与奖", amount = Economy.Config.SPECTATE_BASE_REWARD })
        print("[Spectate] No bet, base reward only")
    end

    -- 显示结算面板
    local title = playerWon and "SPONSOR WIN!" or (betAmount > 0 and "SPONSOR LOST" or "SPECTATED")
    GameUI.ShowSettlement(title, playerWon, items, function()
        EnterLobby()
    end)
end

-- ============================================================================
-- 角色工坊（从大厅入口）
-- ============================================================================

--- 从大厅打开角色制作器
function OpenCharacterMakerFromLobby()
    Workshop.Open({
        onBack = function()
            EnterLobby()
        end,
        onCreate = function()
            -- 创建新角色：进入编辑器（新建模式）
            OpenCharacterMakerNew()
        end,
        onEdit = function(charId)
            -- 编辑已有角色：进入编辑器（编辑模式）
            OpenCharacterMakerEdit(charId)
        end,
    })
end

--- 从工坊进入编辑器（新建模式）
function OpenCharacterMakerNew()
    CharacterMaker.Open({
        mode = "create",
        onClose = function()
            -- 返回工坊
            OpenCharacterMakerFromLobby()
        end,
        onTestBattle = function(moduleId)
            TestBattleFromMaker(moduleId)
        end,
    })
end

--- 从工坊进入编辑器（编辑已有角色）
---@param charId string
function OpenCharacterMakerEdit(charId)
    CharacterMaker.Open({
        mode = "edit",
        editId = charId,
        onClose = function()
            -- 返回工坊
            OpenCharacterMakerFromLobby()
        end,
        onTestBattle = function(moduleId)
            TestBattleFromMaker(moduleId)
        end,
    })
end

-- ============================================================================
-- 事件
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    UpdateSplash(dt)
    Anim.Update(dt)
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
