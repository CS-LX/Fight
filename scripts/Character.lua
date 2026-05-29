-- ============================================================================
-- Character.lua - 角色创建与生成
-- ============================================================================

local Config = require("Config")

local M = {}

--- 创建一个简化3D角色（Box身体 + Sphere头部 + 武器）
---@param scene Scene
---@param team string "red" | "blue"
---@param spawnPos Vector3
---@return table 角色数据
function M.Create(scene, team, spawnPos)
    local charNode = scene:CreateChild("Char_" .. team)
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
        hp = Config.MaxHP,
        maxHP = Config.MaxHP,
        speed = Config.CharSpeed + math.random() * 0.5,
        attackCooldown = 0,
        state = "moving",   -- "moving" | "attacking" | "dying" | "dead"
        target = nil,
        animTimer = 0,
        deathTimer = 0,     -- 死亡动画计时器
    }

    return char
end

--- 生成两队角色
---@param scene Scene
---@return table[] 角色数据列表
function M.SpawnTeams(scene)
    local characters = {}
    local halfWidth = Config.ArenaWidth / 2 - 2
    local spacing = (Config.ArenaDepth - 4) / (Config.TeamSize - 1)

    -- 红队从左侧进入
    for i = 1, Config.TeamSize do
        local z = -Config.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(-halfWidth, 0, z)
        local char = M.Create(scene, "red", spawnPos)
        table.insert(characters, char)
    end

    -- 蓝队从右侧进入
    for i = 1, Config.TeamSize do
        local z = -Config.ArenaDepth / 2 + 2 + (i - 1) * spacing
        local spawnPos = Vector3(halfWidth, 0, z)
        local char = M.Create(scene, "blue", spawnPos)
        table.insert(characters, char)
    end

    print("Spawned " .. Config.TeamSize .. " red and " .. Config.TeamSize .. " blue characters")
    return characters
end

return M
