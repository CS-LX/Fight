-- ============================================================================
-- logic/AIDeployer.lua - 智能AI部署系统
-- ============================================================================
-- 职责：为AI方生成合理的角色选择和阵型部署
-- 特性：
--   1. 阵型模板（前排坦克 + 后排输出）
--   2. 角色强度评估（power score）
--   3. 观战模式双方均衡匹配
--   4. 可选的阵容多样性约束
-- ============================================================================

local CharRegistry = require("characters.CharRegistry")
local CharLogic = require("logic.CharLogic")
local Config = require("Config")

local M = {}

-- ============================================================================
-- 角色强度评估
-- ============================================================================

--- 计算角色的综合 power score（用于均衡匹配）
---@param mod table CharModule
---@return number powerScore
function M.CalcPowerScore(mod)
    local cfg = mod.config
    local hp     = cfg.baseHP or Config.MaxHP
    local atk    = cfg.attackDamage or Config.AttackDamage
    local spd    = cfg.baseSpeed or Config.CharSpeed
    local range  = cfg.attackRange or Config.AttackRange
    local cd     = cfg.attackCooldown or Config.AttackCooldown

    -- DPS = atk / cd
    local dps = atk / math.max(cd, 0.1)
    -- 有效血量 = hp * (1 + speed/5)  速度越快越难被集火
    local ehp = hp * (1 + spd / 5.0)
    -- 范围加成
    local rangeFactor = 1.0 + (range - 1.2) * 0.3

    return ehp * 0.4 + dps * 30 * rangeFactor * 0.6
end

--- 获取角色的战术角色分类
---@param mod table CharModule
---@return string role "tank"|"melee"|"ranged"
function M.ClassifyRole(mod)
    local cfg = mod.config
    local hp    = cfg.baseHP or Config.MaxHP
    local range = cfg.attackRange or Config.AttackRange

    if range >= 2.0 then
        return "ranged"
    elseif hp >= 150 then
        return "tank"
    else
        return "melee"
    end
end

-- ============================================================================
-- 阵型模板
-- ============================================================================

--- 生成阵型位置（基于角色角色分类）
--- team: "red"(-X半场) / "blue"(+X半场)
--- roles: { {char=..., role="tank"/"melee"/"ranged"}, ... }
---@param team string
---@param roles table[]
---@return Vector3[] positions 对应每个角色的部署位置
function M.FormationPositions(team, roles)
    local halfW = Config.ArenaWidth * 0.5 - 2   -- 8m
    local halfD = Config.ArenaDepth * 0.5 - 1   -- 6m

    -- 按角色分类分组
    local tanks = {}
    local melees = {}
    local rangeds = {}
    for i, r in ipairs(roles) do
        if r.role == "tank" then
            table.insert(tanks, i)
        elseif r.role == "ranged" then
            table.insert(rangeds, i)
        else
            table.insert(melees, i)
        end
    end

    -- 定义前/中/后排 X 位置（距离中线的距离）
    local frontX  = 2.0   -- 前排：靠近中线
    local midX    = 4.5   -- 中排
    local backX   = 7.0   -- 后排：靠近己方边线

    local positions = {}
    for i = 1, #roles do positions[i] = nil end

    -- 分配位置辅助函数
    local function assignRow(indices, rowX, zSpread)
        local count = #indices
        if count == 0 then return end
        for j, idx in ipairs(indices) do
            -- Z 方向均匀分布（带少许随机偏移）
            local zBase
            if count == 1 then
                zBase = 0
            else
                zBase = ((j - 1) / (count - 1) - 0.5) * 2 * zSpread
            end
            local zJitter = (math.random() - 0.5) * 1.0
            local xJitter = (math.random() - 0.5) * 0.8

            local x = rowX + xJitter
            local z = zBase + zJitter

            -- 限制在半场内
            x = math.max(1.0, math.min(halfW, x))
            z = math.max(-halfD, math.min(halfD, z))

            -- 红方在 -X 半场
            if team == "red" then
                x = -x
            end

            positions[idx] = Vector3(x, 0, z)
        end
    end

    -- 坦克 → 前排，近战 → 中排，远程 → 后排
    assignRow(tanks, frontX, halfD * 0.6)
    assignRow(melees, midX, halfD * 0.7)
    assignRow(rangeds, backX, halfD * 0.5)

    -- 确保所有位置都被分配（fallback）
    for i = 1, #roles do
        if not positions[i] then
            local x = midX + (math.random() - 0.5) * 2
            local z = (math.random() - 0.5) * halfD * 1.2
            x = math.max(1.0, math.min(halfW, x))
            z = math.max(-halfD, math.min(halfD, z))
            if team == "red" then x = -x end
            positions[i] = Vector3(x, 0, z)
        end
    end

    return positions
end

-- ============================================================================
-- 智能选角
-- ============================================================================

--- 从可用角色池中选择 N 个角色（带多样性）
---@param count number 需要选择的角色数
---@param budget number|nil 可选总power预算（用于均衡）
---@return string[] moduleIds 选中的角色模块ID列表
---@return number totalPower 总战力
function M.SelectCharacters(count, budget)
    local allIds = CharRegistry.GetAllIds()
    if #allIds == 0 then allIds = { "doro" } end

    -- 计算每个角色的 power
    local pool = {}
    for _, id in ipairs(allIds) do
        local mod = CharRegistry.Get(id)
        if mod then
            local power = M.CalcPowerScore(mod)
            local role = M.ClassifyRole(mod)
            table.insert(pool, { id = id, power = power, role = role })
        end
    end

    -- 如果池太小，允许重复
    if #pool == 0 then
        local result = {}
        for i = 1, count do result[i] = "doro" end
        return result, count * 50
    end

    -- 按 power 排序，用于预算控制
    table.sort(pool, function(a, b) return a.power > b.power end)

    local selected = {}
    local totalPower = 0
    local usedCount = {}  -- 限制同一角色重复次数

    -- 策略：尝试保证至少1个坦克、至少1个远程（如果有的话）
    local hasTank = false
    local hasRanged = false

    for i = 1, count do
        local best = nil
        local bestScore = -1

        for _, entry in ipairs(pool) do
            -- 限制同一角色最多出现2次
            local used = usedCount[entry.id] or 0
            if used >= 2 then goto continue end

            local score = 0

            -- 基础分：加入随机性避免每次一样
            score = score + math.random() * 20

            -- 角色多样性加分
            if not hasTank and entry.role == "tank" then
                score = score + 30
            end
            if not hasRanged and entry.role == "ranged" then
                score = score + 25
            end

            -- 预算控制：如果有预算限制，偏向让总power接近目标
            if budget and budget > 0 then
                local remaining = budget - totalPower
                local avgRemaining = remaining / (count - i + 1)
                -- 越接近平均值越好
                local deviation = math.abs(entry.power - avgRemaining)
                score = score - deviation * 0.1
            end

            if score > bestScore then
                bestScore = score
                best = entry
            end
            ::continue::
        end

        if best then
            table.insert(selected, best.id)
            totalPower = totalPower + best.power
            usedCount[best.id] = (usedCount[best.id] or 0) + 1
            if best.role == "tank" then hasTank = true end
            if best.role == "ranged" then hasRanged = true end
        else
            -- fallback
            local fallback = pool[math.random(1, #pool)]
            table.insert(selected, fallback.id)
            totalPower = totalPower + fallback.power
        end
    end

    return selected, totalPower
end

-- ============================================================================
-- 完整部署（选角 + 阵型）
-- ============================================================================

--- 为一个队伍生成智能部署方案
---@param team string "red"|"blue"
---@param teamSize number 队伍人数
---@param budget number|nil power预算（均衡用）
---@param statMultiplier number|nil 属性放大倍率（排位难度用）
---@return table[] characters 部署的角色列表（已创建 CharLogic 实例）
---@return number totalPower 该队总战力
function M.DeployTeam(team, teamSize, budget, statMultiplier)
    statMultiplier = statMultiplier or 1.0

    -- 1. 智能选角
    local moduleIds, totalPower = M.SelectCharacters(teamSize, budget)

    -- 2. 确定每个角色的战术分类
    local roles = {}
    for i, id in ipairs(moduleIds) do
        local mod = CharRegistry.Get(id)
        local role = mod and M.ClassifyRole(mod) or "melee"
        table.insert(roles, { id = id, role = role })
    end

    -- 3. 生成阵型位置
    local positions = M.FormationPositions(team, roles)

    -- 4. 创建角色实例
    local chars = {}
    for i, id in ipairs(moduleIds) do
        local char = CharLogic.Create(id, team, positions[i])
        -- 排位难度缩放
        if statMultiplier ~= 1.0 then
            char.hp = math.floor(char.hp * statMultiplier)
            char.maxHP = char.hp
            char.attackDamage = math.floor(char.attackDamage * statMultiplier)
        end
        table.insert(chars, char)
    end

    return chars, totalPower
end

--- 为观战模式生成均衡的双方队伍
---@return table[] redChars, table[] blueChars, number redPower, number bluePower
function M.DeploySpectateBalanced()
    -- 双方人数相同（3~5）以确保公平
    local teamSize = math.random(3, 5)

    -- 第一队自由选角
    local redChars, redPower = M.DeployTeam("red", teamSize, nil, 1.0)

    -- 第二队以第一队的 power 为预算目标（±15%浮动）
    local targetPower = redPower * (0.85 + math.random() * 0.30)
    local blueChars, bluePower = M.DeployTeam("blue", teamSize, targetPower, 1.0)

    print(string.format("[AIDeployer] Spectate balanced: red=%d(%.0f) vs blue=%d(%.0f), ratio=%.2f",
        #redChars, redPower, #blueChars, bluePower,
        bluePower / math.max(redPower, 1)))

    return redChars, blueChars, redPower, bluePower
end

-- ============================================================================
-- LLM 集成辅助方法
-- ============================================================================

--- 构建发给 LLM 的游戏状态数据
---@param team string "blue"（AI方）
---@param maxUnits number 最大部署数
---@param gold number 可用金币
---@return table gameState 用于 LLM Client 的 prompt 数据
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
---@param plan table[] LLM返回的 [{id, x, z}, ...]
---@param team string "blue"
---@param statMultiplier number|nil 属性缩放
---@return table[] characters
function M.ApplyLLMPlan(plan, team, statMultiplier)
    statMultiplier = statMultiplier or 1.0
    local halfW = Config.ArenaWidth * 0.5 - 1
    local halfD = Config.ArenaDepth * 0.5 - 1
    local chars = {}

    for _, entry in ipairs(plan) do
        local id = entry.id
        -- 验证角色ID是否存在
        local mod = CharRegistry.Get(id)
        if not mod then
            -- 尝试模糊匹配（LLM可能返回部分名称）
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
            -- 限制坐标到合法范围
            local x = tonumber(entry.x) or (math.random() * 7 + 1)
            local z = tonumber(entry.z) or ((math.random() - 0.5) * 10)
            x = math.max(1.0, math.min(halfW, x))
            z = math.max(-halfD, math.min(halfD, z))

            -- 蓝方在 +X 半场
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

    -- 如果 LLM 返回为空，fallback 至少放1个角色
    if #chars == 0 then
        print("[AIDeployer] LLM plan empty, fallback to random")
        return M.DeployTeam(team, 3, nil, statMultiplier)
    end

    return chars
end

return M
