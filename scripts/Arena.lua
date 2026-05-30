-- ============================================================================
-- Arena.lua - 卡兹米尔兹竞技场（程序化几何体拼接）
-- 参考：明日方舟 Kazimierz Major 竞技场风格
-- 设计适配俯视相机（高度18m，俯角55°，FOV 45°）
-- 结构：地面 + 边框台阶看台 + 角柱 + 地面标记线 + 隐形墙
-- ============================================================================

local Config = require("Config")

local M = {}

-- ============================================================================
-- 材质工具
-- ============================================================================

local function MakeMat(color, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.8))
    return mat
end

local function MakeAlphaMat(color)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    return mat
end

-- ============================================================================
-- 基础构件
-- ============================================================================

local function CreateBox(parent, name, pos, scale, mat, castShadows)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = scale
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    model:SetMaterial(mat)
    model.castShadows = (castShadows ~= false)
    return node
end

-- ============================================================================
-- 预定义材质（避免重复创建）
-- ============================================================================

local mats = {}

local function InitMaterials()
    mats.floor      = MakeMat(Color(0.35, 0.35, 0.38, 1.0), 0.05, 0.85)     -- 深灰地面
    mats.floorTile  = MakeMat(Color(0.42, 0.42, 0.44, 1.0), 0.05, 0.80)     -- 浅灰色格子
    mats.border     = MakeMat(Color(0.28, 0.27, 0.30, 1.0), 0.1, 0.75)      -- 边框深灰
    mats.stand1     = MakeMat(Color(0.30, 0.30, 0.33, 1.0), 0.1, 0.8)       -- 看台层1
    mats.stand2     = MakeMat(Color(0.25, 0.25, 0.28, 1.0), 0.1, 0.8)       -- 看台层2
    mats.orange     = MakeMat(Color(0.9, 0.5, 0.1, 1.0), 0.3, 0.5)          -- 橙色装饰
    mats.yellow     = MakeMat(Color(0.85, 0.75, 0.15, 1.0), 0.2, 0.5)       -- 黄色标记
    mats.blue       = MakeMat(Color(0.15, 0.3, 0.6, 1.0), 0.1, 0.7)         -- 蓝色座椅
    mats.darkSteel  = MakeMat(Color(0.20, 0.20, 0.22, 1.0), 0.85, 0.3)      -- 深色钢材
    mats.pillar     = MakeMat(Color(0.45, 0.40, 0.35, 1.0), 0.7, 0.4)       -- 柱子
    mats.banner     = MakeMat(Color(0.12, 0.12, 0.15, 1.0), 0.1, 0.7)       -- 横幅底
    mats.bannerText = MakeMat(Color(0.9, 0.8, 0.2, 1.0), 0.0, 0.5)          -- 横幅文字
    mats.line       = MakeMat(Color(0.9, 0.55, 0.15, 1.0), 0.0, 0.5)        -- 地面橙线
    mats.invisible  = MakeAlphaMat(Color(0, 0, 0, 0))
end

-- ============================================================================
-- 竞技场部件（适配俯视角）
-- ============================================================================

--- 主地面
local function CreateFloor(parent, W, D)
    -- 主战斗区地面
    CreateBox(parent, "Floor", Vector3(0, -0.1, 0), Vector3(W, 0.2, D), mats.floor)

    -- 棋盘格效果（用稍亮的方块点缀）
    local tileSize = 2.0
    for ix = 0, math.floor(W / tileSize) - 1 do
        for iz = 0, math.floor(D / tileSize) - 1 do
            if (ix + iz) % 2 == 0 then
                local x = -W/2 + tileSize/2 + ix * tileSize
                local z = -D/2 + tileSize/2 + iz * tileSize
                CreateBox(parent, "Tile_" .. ix .. "_" .. iz,
                    Vector3(x, 0.01, z), Vector3(tileSize - 0.1, 0.02, tileSize - 0.1),
                    mats.floorTile, false)
            end
        end
    end
end

--- 边框 + 台阶式看台（紧贴地面边缘，从俯视可见）
local function CreateBorderAndStands(parent, W, D)
    local borderH = 0.5    -- 边框高度
    local borderW = 0.6    -- 边框厚度

    -- 四面围挡边框
    CreateBox(parent, "BorderL", Vector3(-W/2 - borderW/2, borderH/2, 0), Vector3(borderW, borderH, D + borderW*2), mats.border)
    CreateBox(parent, "BorderR", Vector3(W/2 + borderW/2, borderH/2, 0), Vector3(borderW, borderH, D + borderW*2), mats.border)
    CreateBox(parent, "BorderF", Vector3(0, borderH/2, -D/2 - borderW/2), Vector3(W, borderH, borderW), mats.border)
    CreateBox(parent, "BorderB", Vector3(0, borderH/2, D/2 + borderW/2), Vector3(W, borderH, borderW), mats.border)

    -- 左右阶梯式看台（3级台阶，从低到高向外延伸）
    local steps = 3
    local stepDepth = 1.2   -- 每级台阶深度（X方向）
    local stepH = 0.6       -- 每级台阶高度

    for side = -1, 1, 2 do
        local sideParent = parent:CreateChild(side < 0 and "StandL" or "StandR")
        for i = 1, steps do
            local x = side * (W/2 + borderW + (i - 0.5) * stepDepth)
            local y = i * stepH / 2
            local h = i * stepH
            local mat = (i % 2 == 1) and mats.stand1 or mats.stand2
            CreateBox(sideParent, "Step" .. i,
                Vector3(x, y, 0), Vector3(stepDepth, h, D - 1), mat)

            -- 每级台阶上的蓝色座椅条
            if i <= 2 then
                CreateBox(sideParent, "Seat" .. i,
                    Vector3(x, h + 0.1, 0), Vector3(stepDepth - 0.3, 0.2, D - 2), mats.blue)
            end
        end
    end

    -- 前后也做 2 级矮看台
    for side = -1, 1, 2 do
        local zDir = side
        local fbParent = parent:CreateChild(zDir < 0 and "StandFront" or "StandBack")
        for i = 1, 2 do
            local z = zDir * (D/2 + borderW + (i - 0.5) * stepDepth)
            local y = i * stepH / 2
            local h = i * stepH
            local mat = (i % 2 == 1) and mats.stand1 or mats.stand2
            CreateBox(fbParent, "Step" .. i,
                Vector3(0, y, z), Vector3(W - 2, h, stepDepth), mat)
        end
    end
end

--- 四角柱子（工业风金属柱 + 橙色顶部）
local function CreateCornerPillars(parent, W, D)
    local pillarH = 3.5
    local pillarSize = 0.5
    local offset = 1.0  -- 紧贴看台外缘

    local corners = {
        Vector3(-W/2 - offset, 0, -D/2 - offset),
        Vector3(W/2 + offset, 0, -D/2 - offset),
        Vector3(-W/2 - offset, 0, D/2 + offset),
        Vector3(W/2 + offset, 0, D/2 + offset),
    }

    for i, pos in ipairs(corners) do
        -- 柱体
        CreateBox(parent, "Pillar" .. i,
            Vector3(pos.x, pillarH/2, pos.z),
            Vector3(pillarSize, pillarH, pillarSize), mats.pillar)
        -- 橙色顶帽
        CreateBox(parent, "PillarCap" .. i,
            Vector3(pos.x, pillarH + 0.15, pos.z),
            Vector3(pillarSize + 0.2, 0.3, pillarSize + 0.2), mats.orange)
    end

    -- 柱间横梁（左右两侧顶部连线）
    local beamY = pillarH - 0.3
    CreateBox(parent, "BeamL", Vector3(-W/2 - offset, beamY, 0), Vector3(0.2, 0.2, D + offset*2), mats.darkSteel)
    CreateBox(parent, "BeamR", Vector3(W/2 + offset, beamY, 0), Vector3(0.2, 0.2, D + offset*2), mats.darkSteel)
    CreateBox(parent, "BeamF", Vector3(0, beamY, -D/2 - offset), Vector3(W + offset*2, 0.2, 0.2), mats.darkSteel)
    CreateBox(parent, "BeamB", Vector3(0, beamY, D/2 + offset), Vector3(W + offset*2, 0.2, 0.2), mats.darkSteel)
end

--- 地面标记线
local function CreateMarkings(parent, W, D)
    -- 中线
    CreateBox(parent, "CenterLine", Vector3(0, 0.02, 0), Vector3(0.08, 0.02, D - 1), mats.line)

    -- 中心圆模拟（小正方形排列）
    local radius = 2.5
    local segments = 16
    for i = 1, segments do
        local angle = (i / segments) * math.pi * 2
        local x = math.cos(angle) * radius
        local z = math.sin(angle) * radius
        CreateBox(parent, "Circle" .. i,
            Vector3(x, 0.02, z), Vector3(0.3, 0.02, 0.08), mats.line, false)
    end

    -- 两侧区域分界线
    CreateBox(parent, "ZoneLineL", Vector3(-W/4, 0.02, 0), Vector3(0.06, 0.02, D - 2), mats.yellow, false)
    CreateBox(parent, "ZoneLineR", Vector3(W/4, 0.02, 0), Vector3(0.06, 0.02, D - 2), mats.yellow, false)

    -- 边缘标线
    CreateBox(parent, "EdgeLineF", Vector3(0, 0.02, -D/2 + 0.3), Vector3(W - 0.5, 0.02, 0.06), mats.orange, false)
    CreateBox(parent, "EdgeLineB", Vector3(0, 0.02, D/2 - 0.3), Vector3(W - 0.5, 0.02, 0.06), mats.orange, false)
end

--- 看台装饰（横幅、灯光柱等较小元素）
local function CreateDecorations(parent, W, D)
    -- 前后看台上方的小横幅
    local bannerY = 1.8
    CreateBox(parent, "BannerF", Vector3(0, bannerY, -D/2 - 2.0), Vector3(6, 0.6, 0.1), mats.banner)
    CreateBox(parent, "BannerTxtF", Vector3(0, bannerY, -D/2 - 2.06), Vector3(4.5, 0.3, 0.04), mats.bannerText)
    CreateBox(parent, "BannerB", Vector3(0, bannerY, D/2 + 2.0), Vector3(6, 0.6, 0.1), mats.banner)
    CreateBox(parent, "BannerTxtB", Vector3(0, bannerY, D/2 + 2.06), Vector3(4.5, 0.3, 0.04), mats.bannerText)

    -- 左右看台中间位置的橙色装饰条
    local decorY = 1.2
    CreateBox(parent, "DecoL", Vector3(-W/2 - 2.5, decorY, 0), Vector3(0.15, 0.15, D - 4), mats.orange, false)
    CreateBox(parent, "DecoR", Vector3(W/2 + 2.5, decorY, 0), Vector3(0.15, 0.15, D - 4), mats.orange, false)
end

--- 隐形碰撞墙
local function CreateCollisionWalls(parent, W, D)
    local wallH = 4.0
    CreateBox(parent, "WallF", Vector3(0, wallH/2, -D/2 - 0.1), Vector3(W, wallH, 0.2), mats.invisible, false)
    CreateBox(parent, "WallB", Vector3(0, wallH/2, D/2 + 0.1), Vector3(W, wallH, 0.2), mats.invisible, false)
    CreateBox(parent, "WallL", Vector3(-W/2 - 0.1, wallH/2, 0), Vector3(0.2, wallH, D), mats.invisible, false)
    CreateBox(parent, "WallR", Vector3(W/2 + 0.1, wallH/2, 0), Vector3(0.2, wallH, D), mats.invisible, false)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function M.Create(scene)
    local W = Config.ArenaWidth   -- 20m
    local D = Config.ArenaDepth   -- 14m

    InitMaterials()

    local arenaRoot = scene:CreateChild("Arena")

    CreateFloor(arenaRoot, W, D)
    CreateBorderAndStands(arenaRoot, W, D)
    CreateCornerPillars(arenaRoot, W, D)
    CreateMarkings(arenaRoot, W, D)
    CreateDecorations(arenaRoot, W, D)
    CreateCollisionWalls(arenaRoot, W, D)

    print("[Arena] Kazimierz arena built: " .. W .. "x" .. D .. "m (procedural, top-view optimized)")
end

return M
