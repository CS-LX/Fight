-------------------------------------------------------------------
-- CardinalSpline.lua
-- Bug-fixed & optimized Cardinal Spline module for UrhoX Lua games.
-- Based on: https://gist.github.com/brookesi/6593166
-- Original algorithm by Ken Fyrstenberg Nilsen (c) 2013, MIT License.
--
-- Fixes applied:
--   - Properly clones input array (no mutation)
--   - Correct table.insert argument order
--   - Correct loop boundaries after padding
--   - Supports both 2D flat arrays and Vector2/Vector3 arrays
-------------------------------------------------------------------

local CardinalSpline = {}
CardinalSpline.__index = CardinalSpline

--- Create a new CardinalSpline instance.
---@param tension number? Curve tension 0-1 (default 0.5)
---@param segments number? Points per segment (default 16)
---@return table
function CardinalSpline.new(tension, segments)
    local self = setmetatable({}, CardinalSpline)
    self.tension = tension or 0.5
    self.segments = segments or 16
    return self
end

--- Generate smooth curve points from a flat array of 2D coordinates.
--- Input: {x1,y1, x2,y2, ..., xn,yn} (minimum 4 values = 2 points)
--- Output: {x1,y1, x2,y2, ...} smooth curve points
---@param points number[] Flat array of x,y pairs
---@param tension number? Override tension (0=linear, 0.5=smooth, 1=very smooth)
---@param numOfSegments number? Override segments per curve section
---@return number[] Flat array of interpolated x,y pairs
function CardinalSpline.getCurvePoints2D(points, tension, numOfSegments)
    tension = tension or 0.5
    numOfSegments = numOfSegments or 16

    local pl = #points
    if pl < 4 then
        -- Need at least 2 points (4 values)
        return {table.unpack(points)}
    end

    -- Clone and pad the array:
    -- Prepend first point, append last point (for tangent calculation)
    local pts = {}
    -- Pad start: duplicate first point
    pts[1] = points[1]
    pts[2] = points[2]
    -- Copy original points
    for i = 1, pl do
        pts[i + 2] = points[i]
    end
    -- Pad end: duplicate last point
    pts[pl + 3] = points[pl - 1]
    pts[pl + 4] = points[pl]

    local res = {}
    local resIdx = 0

    -- Iterate through each segment (pairs of points in padded array)
    for i = 3, pl + 2, 2 do
        local p0 = pts[i]
        local p1 = pts[i + 1]
        local p2 = pts[i + 2]
        local p3 = pts[i + 3]

        if not (p0 and p1 and p2 and p3) then break end

        -- Tangent vectors
        local t1x = (p2 - pts[i - 2]) * tension
        local t2x = (pts[i + 4] - p0) * tension
        local t1y = (p3 - pts[i - 1]) * tension
        local t2y = (pts[i + 5] - p1) * tension

        if not (t2x and t2y) then break end

        for t = 0, numOfSegments do
            local st = t / numOfSegments
            local st2 = st * st
            local st3 = st2 * st
            local st23 = st2 * 3
            local st32 = st3 * 2

            -- Hermite basis functions
            local c1 = st32 - st23 + 1
            local c2 = st23 - st32
            local c3 = st3 - 2 * st2 + st
            local c4 = st3 - st2

            resIdx = resIdx + 1
            res[resIdx] = c1 * p0 + c2 * p2 + c3 * t1x + c4 * t2x
            resIdx = resIdx + 1
            res[resIdx] = c1 * p1 + c2 * p3 + c3 * t1y + c4 * t2y
        end
    end

    return res
end

--- Generate smooth curve from an array of Vector3 points.
--- Interpolates x, y, z independently using cardinal spline.
---@param points table[] Array of Vector3 (or tables with x,y,z)
---@param tension number? Curve tension (default 0.5)
---@param numOfSegments number? Points per segment (default 16)
---@return table[] Array of Vector3 positions
function CardinalSpline.getCurvePoints3D(points, tension, numOfSegments)
    tension = tension or 0.5
    numOfSegments = numOfSegments or 16

    local n = #points
    if n < 2 then
        return {{x = points[1].x, y = points[1].y, z = points[1].z}}
    end

    -- Pad: duplicate first and last
    local pts = {}
    pts[1] = points[1]
    for i = 1, n do
        pts[i + 1] = points[i]
    end
    pts[n + 2] = points[n]

    local res = {}
    local resIdx = 0

    for i = 2, n + 1 do
        local p0 = pts[i - 1]
        local p1 = pts[i]
        local p2 = pts[i + 1]
        local p3 = pts[math.min(i + 2, n + 2)]

        -- Tangent vectors for each axis
        local t1x = (p2.x - p0.x) * tension
        local t1y = (p2.y - p0.y) * tension
        local t1z = (p2.z - p0.z) * tension
        local t2x = (p3.x - p1.x) * tension
        local t2y = (p3.y - p1.y) * tension
        local t2z = (p3.z - p1.z) * tension

        local segCount = numOfSegments
        -- Skip last point of segment except for final segment
        local endT = (i < n + 1) and (segCount - 1) or segCount

        for t = 0, endT do
            local st = t / segCount
            local st2 = st * st
            local st3 = st2 * st

            local c1 = 2*st3 - 3*st2 + 1
            local c2 = 3*st2 - 2*st3
            local c3 = st3 - 2*st2 + st
            local c4 = st3 - st2

            resIdx = resIdx + 1
            res[resIdx] = {
                x = c1 * p1.x + c2 * p2.x + c3 * t1x + c4 * t2x,
                y = c1 * p1.y + c2 * p2.y + c3 * t1y + c4 * t2y,
                z = c1 * p1.z + c2 * p2.z + c3 * t1z + c4 * t2z,
            }
        end
    end

    return res
end

--- Convenience: get a single interpolated point at parameter t (0-1) along the spline.
---@param points table[] Array of Vector3 control points
---@param t number Parameter 0-1 (0=start, 1=end)
---@param tension number? Curve tension (default 0.5)
---@return table Vector3 position at t
function CardinalSpline.getPointAt3D(points, t, tension)
    tension = tension or 0.5
    local n = #points
    if n < 2 then return points[1] end

    -- Map t to segment
    t = math.max(0, math.min(1, t))
    local segTotal = n - 1
    local scaledT = t * segTotal
    local seg = math.floor(scaledT)
    local localT = scaledT - seg

    -- Clamp segment index
    seg = math.min(seg, segTotal - 1)

    -- Get 4 control points (with padding)
    local p0 = points[math.max(1, seg)]
    local p1 = points[seg + 1]
    local p2 = points[math.min(seg + 2, n)]
    local p3 = points[math.min(seg + 3, n)]

    -- Tangents
    local t1x = (p2.x - p0.x) * tension
    local t1y = (p2.y - p0.y) * tension
    local t1z = (p2.z - p0.z) * tension
    local t2x = (p3.x - p1.x) * tension
    local t2y = (p3.y - p1.y) * tension
    local t2z = (p3.z - p1.z) * tension

    -- Hermite interpolation
    local st = localT
    local st2 = st * st
    local st3 = st2 * st
    local c1 = 2*st3 - 3*st2 + 1
    local c2 = 3*st2 - 2*st3
    local c3 = st3 - 2*st2 + st
    local c4 = st3 - st2

    return {
        x = c1 * p1.x + c2 * p2.x + c3 * t1x + c4 * t2x,
        y = c1 * p1.y + c2 * p2.y + c3 * t1y + c4 * t2y,
        z = c1 * p1.z + c2 * p2.z + c3 * t1z + c4 * t2z,
    }
end

return CardinalSpline
