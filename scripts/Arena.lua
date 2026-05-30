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

    -- ===================== 3D 竞技场模型 =====================
    -- 模型原始尺寸: 0.869 x 0.5 x 0.869 (近正方形)
    -- 分轴缩放适配竞技场: X=20m, Z=14m
    local modelSizeX = 0.869
    local modelSizeY = 0.5
    local modelSizeZ = 0.869
    local scaleX = (W + 4) / modelSizeX    -- 覆盖略大于场地的区域
    local scaleZ = (D + 4) / modelSizeZ
    local scaleY = 12.0                     -- 适中高度（模型0.5m * 12 = 6m高）

    local arenaNode = scene:CreateChild("ArenaModel")
    arenaNode.scale = Vector3(scaleX, scaleY, scaleZ)
    -- 模型底部在 Y=-0.25（本地坐标），对齐地面
    arenaNode.position = Vector3(0, 0.25 * scaleY, 0)

    local arenaModel = arenaNode:CreateComponent("StaticModel")
    arenaModel:SetModel(cache:GetResource("Model", "Meshes/arena_stadium.mdl"))
    arenaModel:SetMaterial(cache:GetResource("Material", "Materials/arena_stadium_00_tripo_material_742b7daf-ec0a-4827-9030-d8fd15b7a763.xml"))
    arenaModel.castShadows = true

    -- ===================== 地面（角色行走平面）=====================
    local floorNode = scene:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.15, 0)
    floorNode.scale = Vector3(W, 0.3, D)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    floorModel:SetMaterial(MakeMat(Color(0.2, 0.2, 0.22, 1.0), 0.05, 0.9))

    -- 中线标记
    local lineNode = scene:CreateChild("CenterLine")
    lineNode.position = Vector3(0, 0.02, 0)
    lineNode.scale = Vector3(0.08, 0.01, D - 1)
    local lineModel = lineNode:CreateComponent("StaticModel")
    lineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    lineModel:SetMaterial(MakeMat(Color(0.9, 0.85, 0.3, 1.0), 0.0, 0.5))

    -- RED 侧标记线
    local redLine = scene:CreateChild("RedLine")
    redLine.position = Vector3(-W / 4, 0.02, 0)
    redLine.scale = Vector3(0.05, 0.01, D - 2)
    local redLineModel = redLine:CreateComponent("StaticModel")
    redLineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    redLineModel:SetMaterial(MakeMat(Color(0.8, 0.2, 0.2, 1.0), 0.0, 0.6))

    -- BLUE 侧标记线
    local blueLine = scene:CreateChild("BlueLine")
    blueLine.position = Vector3(W / 4, 0.02, 0)
    blueLine.scale = Vector3(0.05, 0.01, D - 2)
    local blueLineModel = blueLine:CreateComponent("StaticModel")
    blueLineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    blueLineModel:SetMaterial(MakeMat(Color(0.2, 0.4, 0.9, 1.0), 0.0, 0.6))

    -- ===================== 隐形碰撞墙（防止角色逃出）=====================
    local collWallH = 3.0
    CreateInvisibleWall(scene, Vector3(0, collWallH / 2, D / 2 + 0.2),
        Vector3(W + 1, collWallH, 0.3))
    CreateInvisibleWall(scene, Vector3(0, collWallH / 2, -D / 2 - 0.2),
        Vector3(W + 1, collWallH, 0.3))
    CreateInvisibleWall(scene, Vector3(-W / 2 - 0.2, collWallH / 2, 0),
        Vector3(0.3, collWallH, D + 1))
    CreateInvisibleWall(scene, Vector3(W / 2 + 0.2, collWallH / 2, 0),
        Vector3(0.3, collWallH, D + 1))

    print("[Arena] Stadium 3D model loaded: " .. W .. "x" .. D .. "m")
end

return M
