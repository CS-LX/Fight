-- ============================================================================
-- Config.lua - 全局游戏配置
-- ============================================================================

local M = {}

M.Title = "3D Arena Battle"

-- 竞技场
M.ArenaWidth = 20        -- 竞技场宽度(X) 米
M.ArenaDepth = 14        -- 竞技场深度(Z) 米

-- 角色
M.TeamSize = 5           -- 每队人数
M.CharSpeed = 2.5        -- 角色移动速度 m/s
M.AttackRange = 1.2      -- 攻击范围 m
M.AttackCooldown = 0.8   -- 攻击冷却 s
M.AttackDamage = 10      -- 攻击伤害
M.MaxHP = 100            -- 最大血量

-- 相机
M.CameraHeight = 18      -- 相机高度
M.CameraDistance = 12    -- 相机后退距离(Z方向)
M.CameraFOV = 45         -- 视野角度

return M
