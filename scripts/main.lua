-- ============================================================================
-- 3D 竞技场对战游戏
-- 两派角色从竞技场两侧进入，互相击打
-- 45度俯视角 | 3D简化角色 | 简易AI
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 全局变量
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil

-- 游戏配置
local CONFIG = {
    Title = "3D Arena Battle",
    -- 竞技场
    ArenaWidth = 20,        -- 竞技场宽度(X)
    ArenaDepth = 14,        -- 竞技场深度(Z)
    -- 角色
    TeamSize = 5,           -- 每队人数
    CharSpeed = 2.5,        -- 角色移动速度 m/s
    AttackRange = 1.2,      -- 攻击范围 m
    AttackCooldown = 0.8,   -- 攻击冷却 s
    AttackDamage = 10,      -- 攻击伤害
    MaxHP = 100,            -- 最大血量
    -- 相机
    CameraHeight = 18,      -- 相机高度
    CameraDistance = 12,    -- 相机后退距离(Z方向)
    CameraFOV = 45,         -- 视野角度
}

-- 角色数据列表
---@type table[]
local characters_ = {}

-- 游戏状态
local gameState_ = "playing"  -- "playing" | "redWin" | "blueWin"

-- UI 引用
---@type Widget|nil
local statusLabel_ = nil
---@type Widget|nil
local redCountLabel_ = nil
---@type Widget|nil
local blueCountLabel_ = nil

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title

    InitUI()
    CreateScene()
    SetupCamera()
    CreateArena()
    SpawnTeams()
    CreateGameUI()
    SubscribeToEvents()

    print("=== 3D Arena Battle Started ===")
    print("Red Team vs Blue Team, " .. CONFIG.TeamSize .. " vs " .. CONFIG.TeamSize)
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 场景创建
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
    -- 45度俯视角：相机在上方后侧
    cameraNode_.position = Vector3(0, CONFIG.CameraHeight, -CONFIG.CameraDistance)
    -- 向下看45度
    cameraNode_.rotation = Quaternion(55, 0, 0)

    local camera = cameraNode_:CreateComponent("Camera")
    camera.nearClip = 0.5
    camera.farClip = 200.0
    camera.fov = CONFIG.CameraFOV

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true
end

-- ============================================================================
-- 竞技场创建
-- ============================================================================

function CreateArena()
    -- 地面平台
    local floorNode = scene_:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.25, 0)
    floorNode.scale = Vector3(CONFIG.ArenaWidth, 0.5, CONFIG.ArenaDepth)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local floorMat = Material:new()
    floorMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    floorMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.35, 0.3, 1.0)))
    floorMat:SetShaderParameter("Metallic", Variant(0.0))
    floorMat:SetShaderParameter("Roughness", Variant(0.85))
    floorModel:SetMaterial(floorMat)

    -- 边界墙壁（装饰）
    local wallHeight = 1.0
    local wallThickness = 0.3
    local wallColor = Color(0.5, 0.5, 0.55, 1.0)

    -- 前墙 (Z+)
    CreateWall(Vector3(0, wallHeight / 2, CONFIG.ArenaDepth / 2 + wallThickness / 2),
        Vector3(CONFIG.ArenaWidth + wallThickness * 2, wallHeight, wallThickness), wallColor)
    -- 后墙 (Z-)
    CreateWall(Vector3(0, wallHeight / 2, -CONFIG.ArenaDepth / 2 - wallThickness / 2),
        Vector3(CONFIG.ArenaWidth + wallThickness * 2, wallHeight, wallThickness), wallColor)
    -- 左墙 (X-)
    CreateWall(Vector3(-CONFIG.ArenaWidth / 2 - wallThickness / 2, wallHeight / 2, 0),
        Vector3(wallThickness, wallHeight, CONFIG.ArenaDepth), wallColor)
    -- 右墙 (X+)
    CreateWall(Vector3(CONFIG.ArenaWidth / 2 + wallThickness / 2, wallHeight / 2, 0),
        Vector3(wallThickness, wallHeight, CONFIG.ArenaDepth), wallColor)

    -- 装饰：中间标记线
    local lineNode = scene_:CreateChild("CenterLine")
    lineNode.position = Vector3(0, 0.01, 0)
    lineNode.scale = Vector3(0.1, 0.02, CONFIG.ArenaDepth - 1)
    local lineModel = lineNode:CreateComponent("StaticModel")
    lineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local lineMat = Material:new()
    lineMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    lineMat:SetShaderParameter("MatDiffColor", Variant(Color(0.9, 0.9, 0.9, 1.0)))
    lineMat:SetShaderParameter("Metallic", Variant(0.0))
    lineMat:SetShaderParameter("Roughness", Variant(0.5))
    lineModel:SetMaterial(lineMat)

    print("Arena created: " .. CONFIG.ArenaWidth .. "x" .. CONFIG.ArenaDepth .. " meters")
end

function CreateWall(position, scale, color)
    local wallNode = scene_:CreateChild("Wall")
    wallNode.position = position
    wallNode.scale = scale
    local model = wallNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(0.1))
    mat:SetShaderParameter("Roughness", Variant(0.7))
    model:SetMaterial(mat)
    model.castShadows = true
end

-- ============================================================================
-- 角色系统
-- ============================================================================

--- 创建一个简化3D角色（Box身体 + Sphere头部）
---@param team string "red" | "blue"
---@param spawnPos Vector3
---@return table 角色数据
function CreateCharacter(team, spawnPos)
    local charNode = scene_:CreateChild("Char_" .. team)
    charNode.position = spawnPos

    -- 身体颜色
    local bodyColor, headColor
    if team == "red" then
        bodyColor = Color(0.85, 0.2, 0.15, 1.0)
        headColor = Color(1.0, 0.6, 0.5, 1.0)
    else
        bodyColor = Color(0.15, 0.3, 0.85, 1.0)
        headColor = Color(0.5, 0.7, 1.0, 1.0)
    end

    -- 身体 (Box: 0.5 x 0.8 x 0.3)
    local bodyNode = charNode:CreateChild("Body")
    bodyNode.position = Vector3(0, 0.5, 0)
    bodyNode.scale = Vector3(0.5, 0.8, 0.3)
    local bodyModel = bodyNode:CreateComponent("StaticModel")
    bodyModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local bodyMat = Material:new()
    bodyMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    bodyMat:SetShaderParameter("MatDiffColor", Variant(bodyColor))
    bodyMat:SetShaderParameter("Metallic", Variant(0.0))
    bodyMat:SetShaderParameter("Roughness", Variant(0.6))
    bodyModel:SetMaterial(bodyMat)
    bodyModel.castShadows = true

    -- 头部 (Sphere: 0.35 x 0.35 x 0.35)
    local headNode = charNode:CreateChild("Head")
    headNode.position = Vector3(0, 1.1, 0)
    headNode.scale = Vector3(0.35, 0.35, 0.35)
    local headModel = headNode:CreateComponent("StaticModel")
    headModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    local headMat = Material:new()
    headMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    headMat:SetShaderParameter("MatDiffColor", Variant(headColor))
    headMat:SetShaderParameter("Metallic", Variant(0.0))
    headMat:SetShaderParameter("Roughness", Variant(0.4))
    headModel:SetMaterial(headMat)
    headModel.castShadows = true

    -- 武器标志（小方块在前方）
    local weaponNode = charNode:CreateChild("Weapon")
    weaponNode.position = Vector3(0.35, 0.5, 0.15)
    weaponNode.scale = Vector3(0.12, 0.12, 0.4)
    local weaponModel = weaponNode:CreateComponent("StaticModel")
    weaponModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local weaponMat = Material:new()
    weaponMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    weaponMat:SetShaderParameter("MatDiffColor", Variant(Color(0.6, 0.6, 0.6, 1.0)))
    weaponMat:SetShaderParameter("Metallic", Variant(0.9))
    weaponMat:SetShaderParameter("Roughness", Variant(0.2))
    weaponModel:SetMaterial(weaponMat)

    -- 角色数据
    local char = {
        node = charNode,
        team = team,
        hp = CONFIG.MaxHP,
        maxHP = CONFIG.MaxHP,
        speed = CONFIG.CharSpeed + math.random() * 0.5,  -- 稍有差异
        attackCooldown = 0,
        state = "moving",   -- "moving" | "attacking" | "dead"
        target = nil,       -- 目标角色引用
        animTimer = 0,      -- 动画计时器
    }

    return char
end

function SpawnTeams()
    local halfWidth = CONFIG.ArenaWidth / 2 - 2
    local spacing = (CONFIG.ArenaDepth - 4) / (CONFIG.TeamSize - 1)

    -- 红队从左侧进入
    for i = 1, CONFIG.TeamSize do
        local z = -CONFIG.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(-halfWidth, 0, z)
        local char = CreateCharacter("red", spawnPos)
        table.insert(characters_, char)
    end

    -- 蓝队从右侧进入
    for i = 1, CONFIG.TeamSize do
        local z = -CONFIG.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(halfWidth, 0, z)
        local char = CreateCharacter("blue", spawnPos)
    table.insert(characters_, char)
    end

    print("Spawned " .. CONFIG.TeamSize .. " red and " .. CONFIG.TeamSize .. " blue characters")
end

-- ============================================================================
-- AI 系统
-- ============================================================================

--- 寻找最近的敌人
---@param char table
---@return table|nil
function FindNearestEnemy(char)
    local nearestDist = math.huge
    local nearest = nil
    local myPos = char.node.position

    for _, other in ipairs(characters_) do
        if other.team ~= char.team and other.state ~= "dead" then
            local dist = (other.node.position - myPos):Length()
            if dist < nearestDist then
                nearestDist = dist
                nearest = other
            end
        end
    end

    return nearest
end

--- 更新角色AI
---@param char table
---@param dt number
function UpdateCharacterAI(char, dt)
    if char.state == "dead" then return end

    -- 更新攻击冷却
    char.attackCooldown = math.max(0, char.attackCooldown - dt)

    -- 寻找目标
    local target = FindNearestEnemy(char)
    if target == nil then return end
    char.target = target

    local myPos = char.node.position
    local targetPos = target.node.position
    local diff = targetPos - myPos
    local dist = diff:Length()

    if dist <= CONFIG.AttackRange then
        -- 在攻击范围内 → 攻击
        char.state = "attacking"
        if char.attackCooldown <= 0 then
            PerformAttack(char, target)
            char.attackCooldown = CONFIG.AttackCooldown
        end
    else
        -- 向目标移动
        char.state = "moving"
        local dir = diff:Normalized()
        local moveVec = dir * char.speed * dt
        char.node.position = myPos + moveVec

        -- 面向目标（绕Y轴旋转）
        local angle = math.atan(dir.x, dir.z)
        char.node.rotation = Quaternion(math.deg(angle), Vector3.UP)
    end
end

--- 执行攻击
---@param attacker table
---@param target table
function PerformAttack(attacker, target)
    target.hp = target.hp - CONFIG.AttackDamage

    -- 攻击动画：身体前倾
    attacker.animTimer = 0.3

    if target.hp <= 0 then
        target.hp = 0
        target.state = "dead"
        -- 死亡效果：倒下
        local targetNode = target.node
        targetNode:SetEnabled(false)
    end
end

--- 更新角色动画
---@param char table
---@param dt number
function UpdateCharacterAnimation(char, dt)
    if char.state == "dead" then return end

    char.animTimer = math.max(0, char.animTimer - dt)

    local bodyNode = char.node:GetChild("Body")
    local weaponNode = char.node:GetChild("Weapon")

    if char.animTimer > 0 then
        -- 攻击动画：武器挥动
        local t = char.animTimer / 0.3
        weaponNode.rotation = Quaternion(-60 * t, Vector3.RIGHT)
    else
        -- 待机/走路轻微摆动
        if char.state == "moving" then
            local bobAmount = math.sin(time.elapsedTime * 8 + char.speed * 100) * 0.05
            bodyNode.position = Vector3(0, 0.5 + bobAmount, 0)
        else
            bodyNode.position = Vector3(0, 0.5, 0)
            weaponNode.rotation = Quaternion(0, 0, 0)
        end
    end
end

-- ============================================================================
-- 游戏逻辑
-- ============================================================================

function UpdateGameLogic(dt)
    if gameState_ ~= "playing" then return end

    local redAlive = 0
    local blueAlive = 0

    for _, char in ipairs(characters_) do
        UpdateCharacterAI(char, dt)
        UpdateCharacterAnimation(char, dt)

        if char.state ~= "dead" then
            if char.team == "red" then
                redAlive = redAlive + 1
            else
                blueAlive = blueAlive + 1
            end
        end
    end

    -- 更新UI计数
    if redCountLabel_ then
        redCountLabel_:SetText("Red: " .. redAlive)
    end
    if blueCountLabel_ then
        blueCountLabel_:SetText("Blue: " .. blueAlive)
    end

    -- 胜负判定
    if redAlive == 0 then
        gameState_ = "blueWin"
        if statusLabel_ then
            statusLabel_:SetText("BLUE TEAM WINS!")
        end
        print("Blue team wins!")
    elseif blueAlive == 0 then
        gameState_ = "redWin"
        if statusLabel_ then
            statusLabel_:SetText("RED TEAM WINS!")
        end
        print("Red team wins!")
    end
end

--- 重置游戏
function ResetGame()
    -- 清除旧角色
    for _, char in ipairs(characters_) do
        if char.node ~= nil then
            char.node:Remove()
        end
    end
    characters_ = {}

    -- 重新生成
    SpawnTeams()
    gameState_ = "playing"
    if statusLabel_ then
        statusLabel_:SetText("FIGHT!")
    end
    print("=== Game Reset ===")
end

-- ============================================================================
-- UI
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function CreateGameUI()
    -- 红队计数
    redCountLabel_ = UI.Label {
        text = "Red: " .. CONFIG.TeamSize,
        fontSize = 18,
        fontColor = { 255, 80, 80, 255 },
        position = "absolute",
        top = 12,
        left = 16,
    }

    -- 蓝队计数
    blueCountLabel_ = UI.Label {
        text = "Blue: " .. CONFIG.TeamSize,
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
            ResetGame()
        end,
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            redCountLabel_,
            blueCountLabel_,
            statusLabel_,
            resetBtn,
        }
    }

    UI.SetRoot(root)
end

-- ============================================================================
-- 事件
-- ============================================================================

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    UpdateGameLogic(dt)
end
