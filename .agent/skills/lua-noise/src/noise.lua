--[[
    Lua Noise Library
    Unified module providing Simplex 2D, Perlin 3D, and FBM utilities.

    Sources:
    - Simplex 2D: elemel/lua-webgl-noise (MIT) - Ashima Arts webgl-noise port
    - Perlin 3D: verysoftwares/Lua-Perlin-noise (MIT) - Classic Perlin implementation
    - FBM: Extended from elemel/lua-webgl-noise (MIT)

    Usage:
        local Noise = require("noise")
        local val = Noise.simplex2d(x, y)       -- range [-1, 1]
        local val = Noise.perlin3d(x, y, z)     -- range [0, 1]
        local val = Noise.fbm2d(x, y)           -- range ~[-1, 1]
        local val = Noise.fbm3d(x, y, z)        -- range ~[0, 1]
]]

------------------------------------------------------------
-- Simplex 2D Noise (from elemel/lua-webgl-noise)
------------------------------------------------------------

local function fract(x)
    local _, f = math.modf(x)
    return f
end

local function permute(x)
    return (((x * 34) + 1) * x) % 289
end

--- 2D Simplex noise.
--- @param vx number
--- @param vy number
--- @return number value in range [-1, 1]
local function simplex2d(vx, vy)
    local Cx = 0.211324865405187
    local Cy = 0.366025403784439
    local Cz = -0.577350269189626
    local Cw = 0.024390243902439

    local ix = math.floor(vx + vx * Cy + vy * Cy)
    local iy = math.floor(vy + vx * Cy + vy * Cy)

    local x0x = vx - ix + ix * Cx + iy * Cx
    local x0y = vy - iy + ix * Cx + iy * Cx

    local i1x = (x0x > x0y) and 1 or 0
    local i1y = (x0x > x0y) and 0 or 1
    local x12x = x0x + Cx - i1x
    local x12y = x0y + Cx - i1y
    local x12z = x0x + Cz
    local x12w = x0y + Cz

    ix = ix % 289
    iy = iy % 289
    local px = permute(permute(iy) + ix)
    local py = permute(permute(iy + i1y) + ix + i1x)
    local pz = permute(permute(iy + 1) + ix + 1)

    local mx = math.max(0.5 - x0x * x0x - x0y * x0y, 0) ^ 4
    local my = math.max(0.5 - x12x * x12x - x12y * x12y, 0) ^ 4
    local mz = math.max(0.5 - x12z * x12z - x12w * x12w, 0) ^ 4

    local xx = 2 * fract(px * Cw) - 1
    local xy = 2 * fract(py * Cw) - 1
    local xz = 2 * fract(pz * Cw) - 1
    local hx = math.abs(xx) - 0.5
    local hy = math.abs(xy) - 0.5
    local hz = math.abs(xz) - 0.5
    local oxx = math.floor(xx + 0.5)
    local oxy = math.floor(xy + 0.5)
    local oxz = math.floor(xz + 0.5)
    local a0x = xx - oxx
    local a0y = xy - oxy
    local a0z = xz - oxz

    mx = mx * (1.79284291400159 - 0.85373472095314 * (a0x * a0x + hx * hx))
    my = my * (1.79284291400159 - 0.85373472095314 * (a0y * a0y + hy * hy))
    mz = mz * (1.79284291400159 - 0.85373472095314 * (a0z * a0z + hz * hz))

    local gx = a0x * x0x + hx * x0y
    local gy = a0y * x12x + hy * x12y
    local gz = a0z * x12z + hz * x12w
    return 130 * (mx * gx + my * gy + mz * gz)
end

------------------------------------------------------------
-- Classic 3D Perlin Noise (from verysoftwares/Lua-Perlin-noise)
------------------------------------------------------------

local floor = math.floor

local function fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(a, b, x)
    return a + x * (b - a)
end

local function grad(hash, x, y, z)
    local h = hash % 16
    if h == 0  then return  x + y end
    if h == 1  then return -x + y end
    if h == 2  then return  x - y end
    if h == 3  then return -x - y end
    if h == 4  then return  x + z end
    if h == 5  then return -x + z end
    if h == 6  then return  x - z end
    if h == 7  then return -x - z end
    if h == 8  then return  y + z end
    if h == 9  then return -y + z end
    if h == 10 then return  y - z end
    if h == 11 then return -y - z end
    if h == 12 then return  y + x end
    if h == 13 then return -y + z end
    if h == 14 then return  y - x end
    if h == 15 then return -y - z end
    return 0
end

local permutation = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,
    142,8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,
    203,117,35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,
    74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,
    220,105,92,41,55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,
    132,187,208,89,18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,
    186,3,64,52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,
    59,227,47,16,58,17,182,189,28,42,223,183,170,213,119,248,152,2,44,154,163,
    70,221,153,101,155,167,43,172,9,129,22,39,253,19,98,108,110,79,113,224,232,
    178,185,112,104,218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,
    241,81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,157,184,84,204,
    176,115,121,50,45,127,4,150,254,138,236,205,93,222,114,67,29,24,72,243,141,
    128,195,78,66,215,61,156,180
}

local p = {}
for i = 0, 511 do
    p[i] = permutation[i % 256 + 1]
end

--- 3D Classic Perlin noise.
--- @param x number
--- @param y number
--- @param z number
--- @return number value in range [0, 1]
local function perlin3d(x, y, z)
    local xi = floor(x) % 256
    local yi = floor(y) % 256
    local zi = floor(z) % 256
    local xf = x - floor(x)
    local yf = y - floor(y)
    local zf = z - floor(z)
    local u = fade(xf)
    local v = fade(yf)
    local w = fade(zf)

    local aaa = p[p[p[xi] + yi] + zi]
    local aba = p[p[p[xi] + yi + 1] + zi]
    local aab = p[p[p[xi] + yi] + zi + 1]
    local abb = p[p[p[xi] + yi + 1] + zi + 1]
    local baa = p[p[p[xi + 1] + yi] + zi]
    local bba = p[p[p[xi + 1] + yi + 1] + zi]
    local bab = p[p[p[xi + 1] + yi] + zi + 1]
    local bbb = p[p[p[xi + 1] + yi + 1] + zi + 1]

    local x1 = lerp(grad(aaa, xf, yf, zf), grad(baa, xf - 1, yf, zf), u)
    local x2 = lerp(grad(aba, xf, yf - 1, zf), grad(bba, xf - 1, yf - 1, zf), u)
    local y1 = lerp(x1, x2, v)

    x1 = lerp(grad(aab, xf, yf, zf - 1), grad(bab, xf - 1, yf, zf - 1), u)
    x2 = lerp(grad(abb, xf, yf - 1, zf - 1), grad(bbb, xf - 1, yf - 1, zf - 1), u)
    local y2 = lerp(x1, x2, v)

    return (lerp(y1, y2, w) + 1) / 2
end

------------------------------------------------------------
-- FBM (Fractal Brownian Motion)
------------------------------------------------------------

--- Compute 2D FBM using simplex2d.
--- @param x number
--- @param y number
--- @param octaves? number   (default 4)
--- @param lacunarity? number (default 2.0)
--- @param gain? number       (default 0.5)
--- @return number  range approximately [-1, 1]
local function fbm2d(x, y, octaves, lacunarity, gain)
    octaves = octaves or 4
    lacunarity = lacunarity or 2.0
    gain = gain or 0.5

    local total = 0
    local amplitude = 1.0
    local totalAmplitude = 0
    local frequency = 1.0

    for _ = 1, octaves do
        total = total + amplitude * simplex2d(x * frequency, y * frequency)
        totalAmplitude = totalAmplitude + amplitude
        frequency = frequency * lacunarity
        amplitude = amplitude * gain
    end

    return total / totalAmplitude
end

--- Compute 3D FBM using perlin3d.
--- @param x number
--- @param y number
--- @param z number
--- @param octaves? number   (default 4)
--- @param lacunarity? number (default 2.0)
--- @param gain? number       (default 0.5)
--- @return number  range approximately [0, 1]
local function fbm3d(x, y, z, octaves, lacunarity, gain)
    octaves = octaves or 4
    lacunarity = lacunarity or 2.0
    gain = gain or 0.5

    local total = 0
    local amplitude = 1.0
    local totalAmplitude = 0
    local frequency = 1.0

    for _ = 1, octaves do
        total = total + amplitude * perlin3d(x * frequency, y * frequency, z * frequency)
        totalAmplitude = totalAmplitude + amplitude
        frequency = frequency * lacunarity
        amplitude = amplitude * gain
    end

    return total / totalAmplitude
end

------------------------------------------------------------
-- Module export
------------------------------------------------------------

return {
    -- Core noise functions
    simplex2d = simplex2d,  -- (x, y) -> [-1, 1]
    perlin3d  = perlin3d,   -- (x, y, z) -> [0, 1]

    -- FBM (fractal) convenience
    fbm2d = fbm2d,          -- (x, y, [octaves, lacunarity, gain]) -> ~[-1, 1]
    fbm3d = fbm3d,          -- (x, y, z, [octaves, lacunarity, gain]) -> ~[0, 1]
}
