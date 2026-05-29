-- ============================================================================
-- Arena.lua - 竞技场构建
-- ============================================================================

local Config = require("Config")

local M = {}

--- 创建一面墙
---@param scene Scene
---@param position Vector3
---@param scale Vector3
---@param color Color
local function CreateWall(scene, position, scale, color)
    local wallNode = scene:CreateChild("Wall")
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

--- 创建完整竞技场
---@param scene Scene
function M.Create(scene)
    -- 地面平台
    local floorNode = scene:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.25, 0)
    floorNode.scale = Vector3(Config.ArenaWidth, 0.5, Config.ArenaDepth)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local floorMat = Material:new()
    floorMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    floorMat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.35, 0.3, 1.0)))
    floorMat:SetShaderParameter("Metallic", Variant(0.0))
    floorMat:SetShaderParameter("Roughness", Variant(0.85))
    floorModel:SetMaterial(floorMat)

    -- 边界墙壁
    local wallHeight = 1.0
    local wallThickness = 0.3
    local wallColor = Color(0.5, 0.5, 0.55, 1.0)

    -- 前墙 (Z+)
    CreateWall(scene, Vector3(0, wallHeight / 2, Config.ArenaDepth / 2 + wallThickness / 2),
        Vector3(Config.ArenaWidth + wallThickness * 2, wallHeight, wallThickness), wallColor)
    -- 后墙 (Z-)
    CreateWall(scene, Vector3(0, wallHeight / 2, -Config.ArenaDepth / 2 - wallThickness / 2),
        Vector3(Config.ArenaWidth + wallThickness * 2, wallHeight, wallThickness), wallColor)
    -- 左墙 (X-)
    CreateWall(scene, Vector3(-Config.ArenaWidth / 2 - wallThickness / 2, wallHeight / 2, 0),
        Vector3(wallThickness, wallHeight, Config.ArenaDepth), wallColor)
    -- 右墙 (X+)
    CreateWall(scene, Vector3(Config.ArenaWidth / 2 + wallThickness / 2, wallHeight / 2, 0),
        Vector3(wallThickness, wallHeight, Config.ArenaDepth), wallColor)

    -- 装饰：中间标记线
    local lineNode = scene:CreateChild("CenterLine")
    lineNode.position = Vector3(0, 0.01, 0)
    lineNode.scale = Vector3(0.1, 0.02, Config.ArenaDepth - 1)
    local lineModel = lineNode:CreateComponent("StaticModel")
    lineModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local lineMat = Material:new()
    lineMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    lineMat:SetShaderParameter("MatDiffColor", Variant(Color(0.9, 0.9, 0.9, 1.0)))
    lineMat:SetShaderParameter("Metallic", Variant(0.0))
    lineMat:SetShaderParameter("Roughness", Variant(0.5))
    lineModel:SetMaterial(lineMat)

    print("Arena created: " .. Config.ArenaWidth .. "x" .. Config.ArenaDepth .. " meters")
end

return M
