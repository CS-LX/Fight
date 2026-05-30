-- ============================================================================
-- Arena.lua - 竞技场构建（程序化卡兹米尔兹风格）
-- ============================================================================

local Config = require("Config")

local M = {}

--- 创建 PBR 材质
local function MakeMat(color, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.8))
    return mat
end

--- 创建一根金属桁架柱
local function CreateTruss(scene, pos, height)
    local node = scene:CreateChild("Truss")
    node.position = pos
    node.scale = Vector3(0.15, height, 0.15)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(MakeMat(Color(0.35, 0.35, 0.4, 1.0), 0.8, 0.35))
    model.castShadows = true
end

--- 创建看台阶梯
local function CreateBleacher(scene, pos, width, depth, rows)
    local parent = scene:CreateChild("Bleacher")
    parent.position = pos
    local stepH = 0.4
    local stepD = depth / rows
    for i = 1, rows do
        local step = parent:CreateChild("Step")
        step.position = Vector3(0, (i - 0.5) * stepH, -(i - 1) * stepD)
        step.scale = Vector3(width, stepH, stepD * 0.9)
        local model = step:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(MakeMat(Color(0.28, 0.28, 0.32, 1.0), 0.1, 0.75))
        model.castShadows = true
    end
end

--- 创建隐形碰撞墙
local function CreateInvisibleWall(scene, position, scale)
    local wallNode = scene:CreateChild("InvisibleWall")
    wallNode.position = position
    wallNode.scale = scale
    local model = wallNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0, 0, 0, 0)))
    model:SetMaterial(mat)
    model.castShadows = false
end

--- 创建完整竞技场
---@param scene Scene
function M.Create(scene)
    local W = Config.ArenaWidth   -- 20m
    local D = Config.ArenaDepth   -- 14m

    -- ===================== 地面（竞技场地板）=====================
    local floorNode = scene:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.15, 0)
    floorNode.scale = Vector3(W + 4, 0.3, D + 4)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    floorModel:SetMaterial(MakeMat(Color(0.22, 0.22, 0.25, 1.0), 0.05, 0.85))

    -- 竞技台面（略高于地面的比赛区域）
    local stageNode = scene:CreateChild("Stage")
    stageNode.position = Vector3(0, 0.02, 0)
    stageNode.scale = Vector3(W, 0.04, D)
    local stageModel = stageNode:CreateComponent("StaticModel")
    stageModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    stageModel:SetMaterial(MakeMat(Color(0.18, 0.2, 0.22, 1.0), 0.0, 0.9))

    -- 中线标记
    local lineNode = scene:CreateChild("CenterLine")
    lineNode.position = Vector3(0, 0.05, 0)
    lineNode.scale = Vector3(0.08, 0.01, D - 1)
    local lineModel = lineNode:CreateComponent("StaticModel")
    lineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    lineModel:SetMaterial(MakeMat(Color(0.9, 0.85, 0.3, 1.0), 0.0, 0.5))

    -- RED 侧标记线
    local redLine = scene:CreateChild("RedLine")
    redLine.position = Vector3(-W / 4, 0.05, 0)
    redLine.scale = Vector3(0.05, 0.01, D - 2)
    local redLineModel = redLine:CreateComponent("StaticModel")
    redLineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    redLineModel:SetMaterial(MakeMat(Color(0.8, 0.2, 0.2, 1.0), 0.0, 0.6))

    -- BLUE 侧标记线
    local blueLine = scene:CreateChild("BlueLine")
    blueLine.position = Vector3(W / 4, 0.05, 0)
    blueLine.scale = Vector3(0.05, 0.01, D - 2)
    local blueLineModel = blueLine:CreateComponent("StaticModel")
    blueLineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    blueLineModel:SetMaterial(MakeMat(Color(0.2, 0.4, 0.9, 1.0), 0.0, 0.6))

    -- ===================== 围栏/护墙 =====================
    local wallH = 1.2
    local wallT = 0.2
    local wallMat = MakeMat(Color(0.4, 0.4, 0.45, 1.0), 0.6, 0.4)

    -- 四面矮墙
    local walls = {
        { Vector3(0, wallH / 2, D / 2 + wallT / 2), Vector3(W + wallT * 2, wallH, wallT) },
        { Vector3(0, wallH / 2, -D / 2 - wallT / 2), Vector3(W + wallT * 2, wallH, wallT) },
        { Vector3(-W / 2 - wallT / 2, wallH / 2, 0), Vector3(wallT, wallH, D) },
        { Vector3(W / 2 + wallT / 2, wallH / 2, 0), Vector3(wallT, wallH, D) },
    }
    for _, w in ipairs(walls) do
        local wn = scene:CreateChild("Wall")
        wn.position = w[1]
        wn.scale = w[2]
        local wm = wn:CreateComponent("StaticModel")
        wm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        wm:SetMaterial(wallMat)
        wm.castShadows = true
    end

    -- ===================== 看台（前后两侧）=====================
    CreateBleacher(scene, Vector3(0, 0, D / 2 + 1.5), W - 2, 3.0, 4)
    CreateBleacher(scene, Vector3(0, 0, -D / 2 - 1.5), W - 2, -3.0, 4)

    -- ===================== 桁架柱（四角 + 中间）=====================
    local trussH = 6.0
    local trussPositions = {
        Vector3(-W / 2 - 0.5, trussH / 2, D / 2 + 0.5),
        Vector3(W / 2 + 0.5, trussH / 2, D / 2 + 0.5),
        Vector3(-W / 2 - 0.5, trussH / 2, -D / 2 - 0.5),
        Vector3(W / 2 + 0.5, trussH / 2, -D / 2 - 0.5),
        Vector3(0, trussH / 2, D / 2 + 0.5),
        Vector3(0, trussH / 2, -D / 2 - 0.5),
    }
    for _, p in ipairs(trussPositions) do
        CreateTruss(scene, p, trussH)
    end

    -- 顶部横梁（连接桁架）
    local beamMat = MakeMat(Color(0.3, 0.3, 0.35, 1.0), 0.7, 0.4)
    local beams = {
        { Vector3(0, trussH + 0.1, D / 2 + 0.5), Vector3(W + 1.5, 0.12, 0.12) },
        { Vector3(0, trussH + 0.1, -D / 2 - 0.5), Vector3(W + 1.5, 0.12, 0.12) },
        { Vector3(-W / 2 - 0.5, trussH + 0.1, 0), Vector3(0.12, 0.12, D + 1.5) },
        { Vector3(W / 2 + 0.5, trussH + 0.1, 0), Vector3(0.12, 0.12, D + 1.5) },
    }
    for _, b in ipairs(beams) do
        local bn = scene:CreateChild("Beam")
        bn.position = b[1]
        bn.scale = b[2]
        local bm = bn:CreateComponent("StaticModel")
        bm:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        bm:SetMaterial(beamMat)
        bm.castShadows = true
    end

    -- ===================== 隐形碰撞墙（防止角色逃出）=====================
    local collWallH = 3.0
    CreateInvisibleWall(scene, Vector3(0, collWallH / 2, D / 2 + wallT),
        Vector3(W + 1, collWallH, 0.3))
    CreateInvisibleWall(scene, Vector3(0, collWallH / 2, -D / 2 - wallT),
        Vector3(W + 1, collWallH, 0.3))
    CreateInvisibleWall(scene, Vector3(-W / 2 - wallT, collWallH / 2, 0),
        Vector3(0.3, collWallH, D + 1))
    CreateInvisibleWall(scene, Vector3(W / 2 + wallT, collWallH / 2, 0),
        Vector3(0.3, collWallH, D + 1))

    print("[Arena] Kazimierz-style arena created: " .. W .. "x" .. D .. "m")
end

return M
