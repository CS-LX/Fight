-- Original source from: https://gist.github.com/brookesi/6593166
-- Author: brookesi (Lua port), original JS by Ken Fyrstenberg Nilsen (c) 2013
-- License: MIT
--
-- This is the ORIGINAL code preserved for reference.
-- See spline-module.lua for the bug-fixed UrhoX-ready version.
--
-- Known issues in this version:
--   1. class() function has syntax error (extra `end`)
--   2. table.insert() arguments in wrong order (value, pos instead of pos, value)
--   3. _pts = ptsa is a reference not a clone, mutates the input array
--   4. Loop boundary calculations are off due to padding errors

function class()
  return setmetatable({}, {
    __call = function(self, ...)
      self:init(...)
      return self
    end
  })
end

Spline = class()

function Spline:init()
end

-- Cardinal spline interpolation
-- ptsa: flat array {x1,y1, x2,y2, ...} minimum 2 points
-- tension: 0-1, 0=no smoothing, 0.5=smooth(default), 1=very smooth
-- numOfSegments: curve resolution per segment (default 16)
function Spline:getCurvePoints(ptsa, tension, numOfSegments)
  tension = tension or 0.5
  numOfSegments = numOfSegments or 16
  local res = {}
  local pl = #ptsa
  local _pts = ptsa  -- BUG: not a clone

  -- BUG: table.insert args swapped
  table.insert(_pts, ptsa[2], 1)
  table.insert(_pts, ptsa[1], 1)
  table.insert(_pts, ptsa[pl - 1])
  table.insert(_pts, ptsa[pl])

  for i = 3, pl, 2 do
    local p0 = _pts[i]
    local p1 = _pts[i + 1]
    local p2 = _pts[i + 2]
    local p3 = _pts[i + 3]

    local t1x = (p2 - _pts[i - 2]) * tension
    local t2x = (_pts[i + 4] - p0) * tension
    local t1y = (p3 - _pts[i - 1]) * tension
    local t2y = (_pts[i + 5] - p1) * tension

    for t = 0, numOfSegments do
      local st = t / numOfSegments
      local pow2 = st * st
      local pow3 = pow2 * st
      local pow23 = pow2 * 3
      local pow32 = pow3 * 2

      local c1 = pow32 - pow23 + 1
      local c2 = pow23 - pow32
      local c3 = pow3 - 2 * pow2 + st
      local c4 = pow3 - pow2

      local x = c1 * p0 + c2 * p2 + c3 * t1x + c4 * t2x
      local y = c1 * p1 + c2 * p3 + c3 * t1y + c4 * t2y

      table.insert(res, x)
      table.insert(res, y)
    end
  end
  return res
end
