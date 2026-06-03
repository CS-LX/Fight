-- ============================================================================
-- StormCircle.lua - 缩圈系统（矩形毒圈）
-- 30秒后从竞技场外围开始缩小，圈外角色受到持续伤害
-- 3D视觉：4面红色半透明墙壁 + 4块画框式毒雾地面（安全区镂空）
-- ============================================================================

local Config = require("Config")

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================

local STORM_DELAY       = 30      -- 战斗开始后多少秒触发缩圈
local SHRINK_DURATION   = 45      -- 从全场缩到最小用多少秒
local MIN_HALF_W        = 1.5     -- 最终安全区半宽（米）
local MIN_HALF_D        = 1.0     -- 最终安全区半深（米）
local DMG_PER_SEC       = 0.10    -- 圈外每秒伤害 = maxHP * 10%（约5秒半条命）
local WALL_HEIGHT       = 3.5     -- 圈墙视觉高度
local PULSE_SPEED       = 2.0     -- 圈墙呼吸脉动速度
local FLOOR_Y           = 0.03    -- 毒雾地面 Y 偏移（略高于地面）

-- ============================================================================
-- 状态
-- ============================================================================

---@type Node|nil
local stormRoot_ = nil
---@type Material|nil
local wallMat_ = nil
---@type Material|nil
local floorMat_ = nil

-- 4面墙节点
---@type Node[]
local wallNodes_ = {}
-- 4块毒雾地面节点（上/下/左/右画框条）
---@type Node[]
local floorNodes_ = {}

local active_ = false
local timer_ = 0
local shrinkTimer_ = 0
local dmgTick_ = 0

-- 当前安全区半尺寸
local safeHalfW_ = 0
local safeHalfD_ = 0
-- 初始（全场）半尺寸
local arenaHalfW_ = 0
local arenaHalfD_ = 0
-- 上次更新视觉时的值（避免每帧重复设置）
local lastSafeW_ = -1
local lastSafeD_ = -1

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 创建圈墙材质（半透明红色发光）
local function CreateWallMaterial()
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.9, 0.15, 0.1, 0.35)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.8, 0.1, 0.05, 1.0)))
    mat:SetShaderParameter("Roughness", Variant(1.0))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    return mat
end

--- 创建毒圈地面材质（半透明暗红雾）
local function CreateFloorMaterial()
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.6, 0.05, 0.05, 0.3)))
    mat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.4, 0.0, 0.0, 1.0)))
    mat:SetShaderParameter("Roughness", Variant(1.0))
    mat:SetShaderParameter("Metallic", Variant(0.0))
    return mat
end

--- 创建一个 Box 节点（用于墙面和地面条）
---@param parent Node
---@param name string
---@param mat Material
---@return Node
local function CreateBoxNode(parent, name, mat)
    local node = parent:CreateChild(name)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = false
    return node
end

--- 更新4面矩形墙的位置和大小
---@param hw number 安全区半宽
---@param hd number 安全区半深
local function UpdateWalls(hw, hd)
    local h = WALL_HEIGHT
    local thickness = 0.12
    -- 墙壁在安全区边缘，朝内面对玩家
    -- 左墙 (x = -hw)
    wallNodes_[1].position = Vector3(-hw, h / 2, 0)
    wallNodes_[1].scale = Vector3(thickness, h, hd * 2)
    -- 右墙 (x = +hw)
    wallNodes_[2].position = Vector3(hw, h / 2, 0)
    wallNodes_[2].scale = Vector3(thickness, h, hd * 2)
    -- 前墙 (z = +hd)
    wallNodes_[3].position = Vector3(0, h / 2, hd)
    wallNodes_[3].scale = Vector3(hw * 2, h, thickness)
    -- 后墙 (z = -hd)
    wallNodes_[4].position = Vector3(0, h / 2, -hd)
    wallNodes_[4].scale = Vector3(hw * 2, h, thickness)
end

--- 更新4条画框式毒雾地面（安全区镂空）
--- 布局：在安全区矩形和竞技场边缘之间填充4个长条
---@param hw number 安全区半宽
---@param hd number 安全区半深
local function UpdateFloorFrame(hw, hd)
    local aw = arenaHalfW_ + 1  -- 略超出竞技场边缘
    local ad = arenaHalfD_ + 1
    local thick = 0.05  -- 地面厚度

    -- 上条（z > hd 区域，宽度=全场，深度=ad-hd）
    local topDepth = ad - hd
    if topDepth > 0.01 then
        floorNodes_[1].position = Vector3(0, FLOOR_Y, hd + topDepth / 2)
        floorNodes_[1].scale = Vector3(aw * 2, thick, topDepth)
        floorNodes_[1].enabled = true
    else
        floorNodes_[1].enabled = false
    end

    -- 下条（z < -hd 区域）
    local botDepth = ad - hd
    if botDepth > 0.01 then
        floorNodes_[2].position = Vector3(0, FLOOR_Y, -hd - botDepth / 2)
        floorNodes_[2].scale = Vector3(aw * 2, thick, botDepth)
        floorNodes_[2].enabled = true
    else
        floorNodes_[2].enabled = false
    end

    -- 左条（x < -hw 区域，高度仅在 -hd ~ +hd 之间）
    local leftWidth = aw - hw
    if leftWidth > 0.01 then
        floorNodes_[3].position = Vector3(-hw - leftWidth / 2, FLOOR_Y, 0)
        floorNodes_[3].scale = Vector3(leftWidth, thick, hd * 2)
        floorNodes_[3].enabled = true
    else
        floorNodes_[3].enabled = false
    end

    -- 右条（x > +hw 区域）
    local rightWidth = aw - hw
    if rightWidth > 0.01 then
        floorNodes_[4].position = Vector3(hw + rightWidth / 2, FLOOR_Y, 0)
        floorNodes_[4].scale = Vector3(rightWidth, thick, hd * 2)
        floorNodes_[4].enabled = true
    else
        floorNodes_[4].enabled = false
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化缩圈系统（在场景创建后调用）
---@param scene Scene
function M.Init(scene)
    arenaHalfW_ = Config.ArenaWidth / 2    -- 10
    arenaHalfD_ = Config.ArenaDepth / 2    -- 7
    safeHalfW_ = arenaHalfW_
    safeHalfD_ = arenaHalfD_

    -- 创建根节点
    stormRoot_ = scene:CreateChild("StormCircle")
    stormRoot_.enabled = false  -- 初始隐藏

    -- 材质
    wallMat_ = CreateWallMaterial()
    floorMat_ = CreateFloorMaterial()

    -- 4面墙（初始 scale=0 确保不可见）
    wallNodes_ = {}
    for i = 1, 4 do
        wallNodes_[i] = CreateBoxNode(stormRoot_, "Wall" .. i, wallMat_)
        wallNodes_[i].scale = Vector3(0, 0, 0)
    end

    -- 4块毒雾地面（初始 scale=0 确保不可见）
    floorNodes_ = {}
    for i = 1, 4 do
        floorNodes_[i] = CreateBoxNode(stormRoot_, "Floor" .. i, floorMat_)
        floorNodes_[i].scale = Vector3(0, 0, 0)
    end

    active_ = false
    timer_ = 0
    shrinkTimer_ = 0
    dmgTick_ = 0
    lastSafeW_ = -1
    lastSafeD_ = -1

    print("[StormCircle] Initialized (rect mode). Delay=" .. STORM_DELAY .. "s, Duration=" .. SHRINK_DURATION .. "s")
end

--- 重置（新一局开始时调用）
function M.Reset()
    active_ = false
    timer_ = 0
    shrinkTimer_ = 0
    dmgTick_ = 0
    safeHalfW_ = arenaHalfW_
    safeHalfD_ = arenaHalfD_
    lastSafeW_ = -1
    lastSafeD_ = -1

    if stormRoot_ then
        stormRoot_.enabled = false
        -- 显式归零所有视觉节点，防止切换竞技场时残留
        for i = 1, 4 do
            if wallNodes_[i] then
                wallNodes_[i].scale = Vector3(0, 0, 0)
            end
            if floorNodes_[i] then
                floorNodes_[i].scale = Vector3(0, 0, 0)
            end
        end
    end
end

--- 每帧更新缩圈
---@param dt number
---@param characters table 角色列表
---@return boolean stormActive 缩圈是否激活中
function M.Update(dt, characters)
    if not stormRoot_ then return false end

    timer_ = timer_ + dt

    -- 还没到缩圈时间
    if timer_ < STORM_DELAY then
        return false
    end

    -- 激活缩圈
    if not active_ then
        active_ = true
        stormRoot_.enabled = true
        shrinkTimer_ = 0
        print("[StormCircle] ⚡ 毒圈开始缩小！圈外角色将持续受到伤害")
    end

    -- 计算当前安全区大小（easeInQuad：前期慢后期快）
    shrinkTimer_ = shrinkTimer_ + dt
    local progress = math.min(shrinkTimer_ / SHRINK_DURATION, 1.0)
    local easedProgress = progress * progress
    safeHalfW_ = arenaHalfW_ - (arenaHalfW_ - MIN_HALF_W) * easedProgress
    safeHalfD_ = arenaHalfD_ - (arenaHalfD_ - MIN_HALF_D) * easedProgress

    -- 更新3D视觉（仅在变化超过阈值时）
    if math.abs(safeHalfW_ - lastSafeW_) > 0.05 or math.abs(safeHalfD_ - lastSafeD_) > 0.05 then
        lastSafeW_ = safeHalfW_
        lastSafeD_ = safeHalfD_
        UpdateWalls(safeHalfW_, safeHalfD_)
        UpdateFloorFrame(safeHalfW_, safeHalfD_)
    end

    -- 圈墙呼吸脉动（透明度变化）
    local pulse = 0.25 + 0.15 * math.sin(timer_ * PULSE_SPEED)
    wallMat_:SetShaderParameter("MatDiffColor", Variant(Color(0.9, 0.15, 0.1, pulse)))

    -- 伤害逻辑：每秒对圈外角色造成伤害（矩形判定）
    dmgTick_ = dmgTick_ + dt
    if dmgTick_ >= 1.0 then
        dmgTick_ = dmgTick_ - 1.0
        for _, char in ipairs(characters) do
            if char.state ~= "dead" and char.state ~= "dying" then
                local cx = char.worldPos.x
                local cz = char.worldPos.z
                -- 矩形判定：超出安全区半宽或半深即为圈外
                if math.abs(cx) > safeHalfW_ or math.abs(cz) > safeHalfD_ then
                    local maxHP = char.maxHP or char.baseHP or 100
                    local dmg = math.ceil(maxHP * DMG_PER_SEC)
                    char.hp = char.hp - dmg
                    if char.hp <= 0 then
                        char.hp = 0
                        char.state = "dying"
                        char.deathTimer = 1.2
                        char.animState = "die"
                    end
                end
            end
        end
    end

    return true
end

--- 获取当前安全区信息
---@return number halfW, number halfD, boolean isActive
function M.GetSafeZone()
    return safeHalfW_, safeHalfD_, active_
end

--- 判断某位置是否在安全区内
---@param pos Vector3
---@return boolean
function M.IsInsideSafeZone(pos)
    if not active_ then return true end
    return math.abs(pos.x) <= safeHalfW_ and math.abs(pos.z) <= safeHalfD_
end

--- 销毁（场景切换时）
function M.Destroy()
    if stormRoot_ then
        stormRoot_:Remove()
        stormRoot_ = nil
    end
    wallNodes_ = {}
    floorNodes_ = {}
    wallMat_ = nil
    floorMat_ = nil
    active_ = false
end

return M
