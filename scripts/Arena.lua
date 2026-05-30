-- ============================================================================
-- Arena.lua - 竞技场构建（3D 模型 + 隐形碰撞墙）
-- ============================================================================

local Config = require("Config")

local M = {}

--- 创建隐形碰撞墙（不可见，仅限制角色移动范围）
---@param scene Scene
---@param position Vector3
---@param scale Vector3
local function CreateInvisibleWall(scene, position, scale)
    local wallNode = scene:CreateChild("InvisibleWall")
    wallNode.position = position
    wallNode.scale = scale
    local model = wallNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    -- 完全透明的材质
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0, 0, 0, 0)))
    model:SetMaterial(mat)
    model.castShadows = false
end

--- 创建完整竞技场
---@param scene Scene
function M.Create(scene)
    -- ===================== 3D 竞技场模型 =====================
    local arenaNode = scene:CreateChild("ArenaModel")
    -- 模型原始尺寸: 0.518 x 1.8 x 0.828 米
    -- 需要缩放到竞技场尺寸: 20m(X) x 14m(Z)
    -- 使用统一缩放让 X 匹配竞技场宽度
    local modelSizeX = 0.518
    local modelSizeZ = 0.828
    local scaleX = Config.ArenaWidth / modelSizeX   -- ~38.6
    local scaleZ = Config.ArenaDepth / modelSizeZ   -- ~16.9
    -- 取较小的缩放值保持整体比例美观，或者分轴缩放让模型完全覆盖场地
    local scaleY = (scaleX + scaleZ) / 2            -- Y方向取平均让高度适中
    arenaNode.scale = Vector3(scaleX, scaleY, scaleZ)
    -- 模型 BoundingBox 中心在 (0, 0, 0)，底部在 Y=-0.9*scale
    -- 将竞技场底部对齐地面 Y=0
    arenaNode.position = Vector3(0, 0.9 * scaleY, 0)

    local arenaModel = arenaNode:CreateComponent("StaticModel")
    arenaModel:SetModel(cache:GetResource("Model", "Meshes/arena.mdl"))
    arenaModel:SetMaterial(cache:GetResource("Material", "Materials/arena_00_tripo_material_0750c575-10d0-4b6a-8d66-adba216b66c1.xml"))
    arenaModel.castShadows = true

    -- ===================== 地面（角色行走平面）=====================
    local floorNode = scene:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.25, 0)
    floorNode.scale = Vector3(Config.ArenaWidth, 0.5, Config.ArenaDepth)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local floorMat = Material:new()
    floorMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    floorMat:SetShaderParameter("MatDiffColor", Variant(Color(0.25, 0.28, 0.25, 1.0)))
    floorMat:SetShaderParameter("Metallic", Variant(0.0))
    floorMat:SetShaderParameter("Roughness", Variant(0.9))
    floorModel:SetMaterial(floorMat)

    -- ===================== 隐形边界墙 =====================
    local wallHeight = 3.0
    local wallThickness = 0.3

    -- 前墙 (Z+)
    CreateInvisibleWall(scene, Vector3(0, wallHeight / 2, Config.ArenaDepth / 2 + wallThickness / 2),
        Vector3(Config.ArenaWidth + wallThickness * 2, wallHeight, wallThickness))
    -- 后墙 (Z-)
    CreateInvisibleWall(scene, Vector3(0, wallHeight / 2, -Config.ArenaDepth / 2 - wallThickness / 2),
        Vector3(Config.ArenaWidth + wallThickness * 2, wallHeight, wallThickness))
    -- 左墙 (X-)
    CreateInvisibleWall(scene, Vector3(-Config.ArenaWidth / 2 - wallThickness / 2, wallHeight / 2, 0),
        Vector3(wallThickness, wallHeight, Config.ArenaDepth))
    -- 右墙 (X+)
    CreateInvisibleWall(scene, Vector3(Config.ArenaWidth / 2 + wallThickness / 2, wallHeight / 2, 0),
        Vector3(wallThickness, wallHeight, Config.ArenaDepth))

    print("[Arena] 3D arena model loaded, scale=" .. string.format("%.1f, %.1f, %.1f", scaleX, scaleY, scaleZ))
end

return M
