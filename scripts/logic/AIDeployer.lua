-- ============================================================================
-- logic/AIDeployer.lua - 智能AI部署系统 v2
-- ============================================================================
-- 职责：为AI方生成合理的角色选择和阵型部署
-- 特性：
--   1. 10+ 种阵型模板（前排推进、环形包围、对角线、散射等）
--   2. 角色强度评估（power score）
--   3. "子力"(piece value) 隐形平衡系统
--   4. 观战模式：1~20人多样化 + 子力均衡
--   5. 可选的阵容多样性约束
-- ============================================================================

local CharRegistry = require("characters.CharRegistry")
local CharLogic = require("logic.CharLogic")
local Config = require("Config")

local M = {}

-- ============================================================================
-- 子力系统（隐形，不对玩家公开）
-- ============================================================================
-- "子力" = 角色综合战力评估值，类似国际象棋子力
-- 用于在双方人数不对等时保证总体实力均衡

--- 计算单个角色的子力值
---@param mod table CharModule
---@return number pieceValue 子力值（越高越强）
function M.CalcPieceValue(mod)
    local cfg = mod.config
    local hp     = cfg.baseHP or Config.MaxHP
    local atk    = cfg.attackDamage or Config.AttackDamage
    local spd    = cfg.baseSpeed or Config.CharSpeed
    local range  = cfg.attackRange or Config.AttackRange
    local cd     = cfg.attackCooldown or Config.AttackCooldown

    -- DPS 有效输出
    local dps = atk / math.max(cd, 0.1)
    -- 有效生存力 = HP × 速度修正
    local survivability = hp * (1.0 + spd * 0.12)
    -- 射程优势（远程角色能在安全距离输出）
    local rangeFactor = 1.0 + math.max(0, range - 1.2) * 0.25

    -- 子力 = 综合评估
    local value = survivability * 0.35 + dps * 25 * rangeFactor * 0.65

    return value
end

--- 计算角色的综合 power score（兼容旧接口）
---@param mod table CharModule
---@return number powerScore
function M.CalcPowerScore(mod)
    return M.CalcPieceValue(mod)
end

--- 获取角色的战术角色分类
---@param mod table CharModule
---@return string role "tank"|"melee"|"ranged"|"assassin"
function M.ClassifyRole(mod)
    local cfg = mod.config
    local hp    = cfg.baseHP or Config.MaxHP
    local range = cfg.attackRange or Config.AttackRange
    local spd   = cfg.baseSpeed or Config.CharSpeed

    if range >= 2.0 then
        return "ranged"
    elseif hp >= 150 then
        return "tank"
    elseif spd >= 3.5 then
        return "assassin"
    else
        return "melee"
    end
end

-- ============================================================================
-- 阵型模板库（10+ 种）
-- ============================================================================
-- 每个阵型返回归一化坐标 (nx, nz)，范围 [0,1]
-- nx: 0=己方后方，1=前线方向
-- nz: 0=中央，-1/+1=两翼

---@alias FormationFunc fun(index: number, total: number): number, number

--- 阵型模板集合
local Formations = {}

--- 1. 经典三排（坦克前/近战中/远程后）
Formations.classic = {
    name = "经典三排",
    suitable = { "tank", "melee", "ranged" },
    generate = function(index, total, role)
        local row, col
        if role == "tank" then
            row = 0.9  -- 最前
        elseif role == "ranged" then
            row = 0.2  -- 最后
        else
            row = 0.55 -- 中间
        end
        -- Z 方向用 index 扩散
        local spread = math.min(0.8, 0.3 + total * 0.04)
        col = (index / (total + 1) - 0.5) * 2 * spread
        return row, col
    end,
}

--- 2. 冲锋箭头（V字前锋）
Formations.arrow = {
    name = "箭头突击",
    generate = function(index, total, _role)
        -- 领头在最前方中央，后续向两翼对称展开
        local t = (index - 1) / math.max(total - 1, 1)
        local row = 1.0 - t * 0.7  -- 越后越靠后
        local side = ((index % 2 == 0) and 1 or -1)
        local col = t * 0.6 * side
        return row, col
    end,
}

--- 3. 横排一字（拉满宽度，同时压上）
Formations.line = {
    name = "一字横排",
    generate = function(index, total, _role)
        local row = 0.7 + (math.random() - 0.5) * 0.1
        local col = (index / (total + 1) - 0.5) * 2 * 0.85
        return row, col
    end,
}

--- 4. 环形/半圆包围
Formations.arc = {
    name = "弧形包围",
    generate = function(index, total, _role)
        local angle = math.pi * 0.2 + (index - 1) / math.max(total - 1, 1) * math.pi * 0.6
        local radius = 0.5 + (math.random() - 0.5) * 0.1
        local row = 0.5 + math.cos(angle) * radius
        local col = math.sin(angle) * 0.7
        return row, col
    end,
}

--- 5. 对角斜线
Formations.diagonal = {
    name = "对角线",
    generate = function(index, total, _role)
        local t = (index - 1) / math.max(total - 1, 1)
        local row = 0.3 + t * 0.6
        local col = -0.6 + t * 1.2
        return row, col
    end,
}

--- 6. 双翼钳形（中间空，两翼重兵）
Formations.pincer = {
    name = "钳形夹击",
    generate = function(index, total, _role)
        local half = math.ceil(total / 2)
        local wing, wingIdx
        if index <= half then
            wing = -1
            wingIdx = index
        else
            wing = 1
            wingIdx = index - half
        end
        local wingTotal = (wing == -1) and half or (total - half)
        local t = (wingIdx - 1) / math.max(wingTotal - 1, 1)
        local row = 0.5 + t * 0.4
        local col = wing * (0.3 + t * 0.4)
        return row, col
    end,
}

--- 7. 集中一团（死球）
Formations.blob = {
    name = "集中抱团",
    generate = function(index, total, _role)
        local angle = (index - 1) / total * math.pi * 2 + math.random() * 0.3
        local radius = 0.15 + math.random() * 0.15
        local row = 0.6 + math.cos(angle) * radius
        local col = math.sin(angle) * radius
        return row, col
    end,
}

--- 8. 散射/游击（完全随机分散）
Formations.scatter = {
    name = "散射游击",
    generate = function(index, total, _role)
        local row = 0.2 + math.random() * 0.7
        local col = (math.random() - 0.5) * 1.6
        return row, col
    end,
}

--- 9. 前后双排
Formations.twoRow = {
    name = "前后双排",
    generate = function(index, total, role)
        local isFront = (role == "tank") or (role == "melee" and index <= math.ceil(total / 2))
        local row = isFront and 0.8 or 0.3
        local rowMembers = isFront and math.ceil(total / 2) or math.floor(total / 2)
        local localIdx = isFront and (math.min(index, rowMembers)) or (index - math.ceil(total / 2))
        localIdx = math.max(1, localIdx)
        local col = (localIdx / (rowMembers + 1) - 0.5) * 2 * 0.7
        return row, col
    end,
}

--- 10. 龟阵（远程中心，近战环绕保护）
Formations.turtle = {
    name = "龟甲护卫",
    generate = function(index, total, role)
        if role == "ranged" then
            -- 远程在中心偏后
            local row = 0.35 + (math.random() - 0.5) * 0.1
            local col = (math.random() - 0.5) * 0.3
            return row, col
        else
            -- 近战/坦克环绕前方
            local angle = (index - 1) / math.max(total - 1, 1) * math.pi
            local row = 0.6 + math.cos(angle) * 0.3
            local col = math.sin(angle) * 0.5
            return row, col
        end
    end,
}

--- 11. 雁形（菱形展开）
Formations.wedge = {
    name = "雁形阵",
    generate = function(index, total, _role)
        -- 中间靠前，两边靠后，类似 > 形
        local center = (total + 1) / 2
        local distFromCenter = math.abs(index - center) / center
        local row = 0.9 - distFromCenter * 0.5
        local col = ((index - center) / center) * 0.7
        return row, col
    end,
}

--- 12. 鱼鳞阵（交错排列）
Formations.staggered = {
    name = "鱼鳞阵",
    generate = function(index, total, _role)
        local cols = math.max(2, math.ceil(math.sqrt(total)))
        local r = math.floor((index - 1) / cols)
        local c = (index - 1) % cols
        local maxRows = math.ceil(total / cols)
        local row = 0.8 - r / math.max(maxRows - 1, 1) * 0.6
        local offset = (r % 2 == 1) and 0.5 / cols or 0
        local col = ((c + offset) / (cols - 0.5) - 0.5) * 1.4
        return row, col
    end,
}

--- 所有可用阵型列表
local ALL_FORMATIONS = {
    Formations.classic,
    Formations.arrow,
    Formations.line,
    Formations.arc,
    Formations.diagonal,
    Formations.pincer,
    Formations.blob,
    Formations.scatter,
    Formations.twoRow,
    Formations.turtle,
    Formations.wedge,
    Formations.staggered,
}

--- 随机选择一个阵型
---@return table formation
function M.RandomFormation()
    return ALL_FORMATIONS[math.random(1, #ALL_FORMATIONS)]
end

-- ============================================================================
-- 阵型位置生成（新版 - 支持多阵型）
-- ============================================================================

--- 基于阵型模板生成实际世界坐标
---@param team string "red"|"blue"
---@param roles table[] { {id, role}, ... }
---@param formation table|nil 指定阵型（nil=随机）
---@return Vector3[] positions
function M.FormationPositions(team, roles, formation)
    formation = formation or M.RandomFormation()

    local halfW = Config.ArenaWidth * 0.5 - 1.5  -- X方向半场可用范围
    local halfD = Config.ArenaDepth * 0.5 - 1.0  -- Z方向半场可用范围
    local total = #roles

    local positions = {}

    for i, r in ipairs(roles) do
        -- 获取归一化坐标
        local nx, nz = formation.generate(i, total, r.role)

        -- 转为世界坐标
        -- nx [0,1] → X [backline, frontline]
        -- 对于 red: frontline = 靠近 x=0 的中线, backline = -halfW
        -- 对于 blue: frontline = 靠近 x=0 的中线, backline = +halfW
        local x = 1.0 + nx * (halfW - 1.0)  -- 从 1m 到 halfW
        local z = nz * halfD

        -- 加入微量随机抖动
        x = x + (math.random() - 0.5) * 0.6
        z = z + (math.random() - 0.5) * 0.5

        -- 限制在合法范围
        x = math.max(1.0, math.min(halfW, x))
        z = math.max(-halfD, math.min(halfD, z))

        -- 红方在 -X 半场
        if team == "red" then
            x = -x
        end

        positions[i] = Vector3(x, 0, z)
    end

    return positions
end

-- ============================================================================
-- 智能选角
-- ============================================================================

--- 从可用角色池中选择 N 个角色
---@param count number 需要选择的角色数
---@param targetPieceValue number|nil 目标总子力（用于均衡）
---@return string[] moduleIds 选中的角色模块ID列表
---@return number totalPieceValue 总子力
function M.SelectCharacters(count, targetPieceValue)
    local allIds = CharRegistry.GetAllIds()
    if #allIds == 0 then allIds = { "doro" } end

    -- 计算每个角色的子力
    local pool = {}
    for _, id in ipairs(allIds) do
        local mod = CharRegistry.Get(id)
        if mod then
            local pv = M.CalcPieceValue(mod)
            local role = M.ClassifyRole(mod)
            table.insert(pool, { id = id, pieceValue = pv, role = role })
        end
    end

    if #pool == 0 then
        local result = {}
        for i = 1, count do result[i] = "doro" end
        return result, count * 50
    end

    -- 按子力排序
    table.sort(pool, function(a, b) return a.pieceValue > b.pieceValue end)

    -- 平均子力
    local avgPV = 0
    for _, e in ipairs(pool) do avgPV = avgPV + e.pieceValue end
    avgPV = avgPV / #pool

    local selected = {}
    local totalPV = 0
    local usedCount = {}

    -- 保证阵容结构
    local hasTank = false
    local hasRanged = false

    for i = 1, count do
        local best = nil
        local bestScore = -math.huge

        for _, entry in ipairs(pool) do
            local used = usedCount[entry.id] or 0
            -- 人数多时允许更多重复（最多3次）
            local maxRepeat = count <= 5 and 2 or 3
            if used >= maxRepeat then goto continue end

            local score = 0

            -- 随机基础分
            score = score + math.random() * 20

            -- 子力质量分
            local pvRatio = entry.pieceValue / math.max(avgPV, 1)
            score = score + math.min(pvRatio * 12, 25)

            -- 结构保证加分
            if not hasTank and entry.role == "tank" and count >= 3 then
                score = score + 30
            end
            if not hasRanged and entry.role == "ranged" and count >= 3 then
                score = score + 25
            end

            -- 多样性
            if used > 0 then
                score = score - used * 12
            end

            -- 子力预算控制
            if targetPieceValue and targetPieceValue > 0 then
                local remaining = targetPieceValue - totalPV
                local avgRemaining = remaining / math.max(count - i + 1, 1)
                local deviation = math.abs(entry.pieceValue - avgRemaining)
                score = score - deviation * 0.2
            end

            if score > bestScore then
                bestScore = score
                best = entry
            end
            ::continue::
        end

        if best then
            table.insert(selected, best.id)
            totalPV = totalPV + best.pieceValue
            usedCount[best.id] = (usedCount[best.id] or 0) + 1
            if best.role == "tank" then hasTank = true end
            if best.role == "ranged" then hasRanged = true end
        else
            local fallback = pool[math.random(1, math.max(1, math.ceil(#pool * 0.5)))]
            table.insert(selected, fallback.id)
            totalPV = totalPV + fallback.pieceValue
        end
    end

    return selected, totalPV
end

-- ============================================================================
-- 完整部署（选角 + 阵型）
-- ============================================================================

--- 为一个队伍生成智能部署方案
---@param team string "red"|"blue"
---@param teamSize number 队伍人数
---@param targetPieceValue number|nil 目标子力（均衡用）
---@param statMultiplier number|nil 属性放大倍率
---@param formation table|nil 指定阵型（nil=随机）
---@return table[] characters 部署的角色列表
---@return number totalPieceValue 该队总子力
function M.DeployTeam(team, teamSize, targetPieceValue, statMultiplier, formation)
    statMultiplier = statMultiplier or 1.0

    -- 1. 智能选角
    local moduleIds, totalPV = M.SelectCharacters(teamSize, targetPieceValue)

    -- 2. 确定每个角色的战术分类
    local roles = {}
    for i, id in ipairs(moduleIds) do
        local mod = CharRegistry.Get(id)
        local role = mod and M.ClassifyRole(mod) or "melee"
        table.insert(roles, { id = id, role = role })
    end

    -- 3. 生成阵型位置
    local positions = M.FormationPositions(team, roles, formation)

    -- 4. 创建角色实例
    local chars = {}
    for i, id in ipairs(moduleIds) do
        local char = CharLogic.Create(id, team, positions[i])
        -- 难度缩放
        if statMultiplier ~= 1.0 then
            char.hp = math.floor(char.hp * statMultiplier)
            char.maxHP = char.hp
            char.attackDamage = math.floor(char.attackDamage * statMultiplier)
        end
        table.insert(chars, char)
    end

    return chars, totalPV
end

-- ============================================================================
-- 子力均衡部署（核心新功能）
-- ============================================================================

--- 根据目标子力总量，选择合适的队伍大小和角色
--- 少量强力角色 vs 大量弱角色 可实现相同总子力
---@param team string
---@param targetTotalPV number 目标总子力
---@param preferSize number|nil 偏好人数（nil=自动计算）
---@param statMultiplier number|nil
---@return table[] characters, number actualPV
function M.DeployByPieceValue(team, targetTotalPV, preferSize, statMultiplier)
    statMultiplier = statMultiplier or 1.0

    -- 计算角色池平均子力
    local allIds = CharRegistry.GetAllIds()
    local avgPV = 0
    local count = 0
    for _, id in ipairs(allIds) do
        local mod = CharRegistry.Get(id)
        if mod then
            avgPV = avgPV + M.CalcPieceValue(mod)
            count = count + 1
        end
    end
    avgPV = count > 0 and (avgPV / count) or 50

    -- 根据目标子力计算合适人数（如没有偏好）
    local teamSize
    if preferSize then
        teamSize = preferSize
    else
        teamSize = math.max(1, math.min(20, math.floor(targetTotalPV / avgPV + 0.5)))
    end

    -- 部署（带子力预算）
    local formation = M.RandomFormation()
    local chars, actualPV = M.DeployTeam(team, teamSize, targetTotalPV, statMultiplier, formation)

    -- 如果实际子力偏差过大（>30%），用属性缩放修正
    local ratio = targetTotalPV / math.max(actualPV, 1)
    if math.abs(ratio - 1.0) > 0.3 then
        local correction = math.sqrt(ratio) -- 用平方根缓和修正
        for _, char in ipairs(chars) do
            char.hp = math.floor(char.hp * correction)
            char.maxHP = char.hp
            char.attackDamage = math.floor(char.attackDamage * correction)
        end
        actualPV = actualPV * correction
    end

    return chars, actualPV
end

-- ============================================================================
-- 观战模式（子力均衡 + 人数多样化 1~20）
-- ============================================================================

--- 为观战模式生成均衡的双方队伍
--- 人数范围 1~20，双方人数可不同，通过子力保证均衡
---@return table[] redChars, table[] blueChars, number redPV, number bluePV
function M.DeploySpectateBalanced()
    -- 随机决定"规模等级"，控制观赏性
    -- 小规模(1~4)=30%, 中规模(5~10)=40%, 大规模(11~20)=30%
    local roll = math.random()
    local baseSize
    if roll < 0.30 then
        baseSize = math.random(1, 4)
    elseif roll < 0.70 then
        baseSize = math.random(5, 10)
    else
        baseSize = math.random(11, 20)
    end

    -- 红方人数 = baseSize（或微调）
    local redSize = baseSize

    -- 蓝方人数：可以不同！用子力来平衡
    -- 50%概率相同人数，50%概率不同人数（差异 ±1~5）
    local blueSize
    if math.random() < 0.5 then
        blueSize = redSize
    else
        local diff = math.random(1, math.max(1, math.floor(redSize * 0.5)))
        blueSize = math.random() < 0.5 and (redSize + diff) or math.max(1, redSize - diff)
        blueSize = math.max(1, math.min(20, blueSize))
    end

    -- 双方各自随机阵型
    local redFormation = M.RandomFormation()
    local blueFormation = M.RandomFormation()

    -- 第一队部署（自由子力）
    local redChars, redPV = M.DeployTeam("red", redSize, nil, 1.0, redFormation)

    -- 第二队以第一队子力为目标（±10%浮动确保不完全镜像）
    local targetBluePV = redPV * (0.90 + math.random() * 0.20)
    local blueChars, bluePV = M.DeployByPieceValue("blue", targetBluePV, blueSize, 1.0)

    print(string.format(
        "[AIDeployer] Spectate: red=%d(%s, PV=%.0f) vs blue=%d(%s, PV=%.0f), balance=%.2f",
        #redChars, redFormation.name, redPV,
        #blueChars, blueFormation.name, bluePV,
        bluePV / math.max(redPV, 1)))

    return redChars, blueChars, redPV, bluePV
end

-- ============================================================================
-- 非观战模式（PvAI - 阵型多样化）
-- ============================================================================

--- 为PvAI对战生成AI方部署
--- 使用随机阵型，保持阵容多样性
---@param teamSize number
---@param playerPieceValue number|nil 玩家方总子力（用于均衡）
---@param statMultiplier number|nil
---@return table[] characters, number totalPV
function M.DeployPvAI(teamSize, playerPieceValue, statMultiplier)
    local formation = M.RandomFormation()
    local chars, totalPV = M.DeployTeam("blue", teamSize, playerPieceValue, statMultiplier, formation)

    print(string.format("[AIDeployer] PvAI: blue=%d (%s, PV=%.0f)",
        #chars, formation.name, totalPV))

    return chars, totalPV
end

-- ============================================================================
-- LLM 集成辅助方法
-- ============================================================================

--- 构建发给 LLM 的游戏状态数据
---@param team string "blue"（AI方）
---@param maxUnits number 最大部署数
---@param gold number 可用金币
---@return table gameState
function M.BuildLLMGameState(team, maxUnits, gold)
    local allIds = CharRegistry.GetAllIds()
    local availableChars = {}

    for _, id in ipairs(allIds) do
        local mod = CharRegistry.Get(id)
        if mod then
            local cfg = mod.config
            table.insert(availableChars, {
                id    = id,
                hp    = cfg.baseHP or Config.MaxHP,
                atk   = cfg.attackDamage or Config.AttackDamage,
                spd   = cfg.baseSpeed or Config.CharSpeed,
                range = cfg.attackRange or Config.AttackRange,
                cost  = 10,
                skill = cfg.skillDesc or "普通攻击",
            })
        end
    end

    return {
        team = team,
        gold = gold,
        costPerUnit = 10,
        minUnits = 2,
        maxUnits = maxUnits,
        availableChars = availableChars,
    }
end

--- 将 LLM 返回的部署方案转为角色实例
---@param plan table[] [{id, x, z}, ...]
---@param team string "blue"
---@param statMultiplier number|nil
---@return table[] characters
function M.ApplyLLMPlan(plan, team, statMultiplier)
    statMultiplier = statMultiplier or 1.0
    local halfW = Config.ArenaWidth * 0.5 - 1
    local halfD = Config.ArenaDepth * 0.5 - 1
    local chars = {}

    for _, entry in ipairs(plan) do
        local id = entry.id
        local mod = CharRegistry.Get(id)
        if not mod then
            local allIds = CharRegistry.GetAllIds()
            for _, candidate in ipairs(allIds) do
                if candidate:find(id, 1, true) or id:find(candidate, 1, true) then
                    id = candidate
                    mod = CharRegistry.Get(id)
                    break
                end
            end
        end

        if mod then
            local x = tonumber(entry.x) or (math.random() * 7 + 1)
            local z = tonumber(entry.z) or ((math.random() - 0.5) * 10)
            x = math.max(1.0, math.min(halfW, x))
            z = math.max(-halfD, math.min(halfD, z))

            if team == "red" then x = -x end

            local char = CharLogic.Create(id, team, Vector3(x, 0, z))
            if statMultiplier ~= 1.0 then
                char.hp = math.floor(char.hp * statMultiplier)
                char.maxHP = char.hp
                char.attackDamage = math.floor(char.attackDamage * statMultiplier)
            end
            table.insert(chars, char)
        else
            print("[AIDeployer] LLM referenced unknown char: " .. tostring(entry.id))
        end
    end

    if #chars == 0 then
        print("[AIDeployer] LLM plan empty, fallback to random")
        return M.DeployTeam(team, 3, nil, statMultiplier)
    end

    return chars
end

return M
