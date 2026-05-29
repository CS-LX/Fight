---
name: lua-noise
description: |
  纯 Lua 噪声生成库（Simplex 2D、Perlin 3D、FBM），零依赖，适用于程序化内容生成。
  Use when users need to (1) 程序化地形/地图生成, (2) Perlin/Simplex 噪声,
  (3) 随机但连续的数值（云朵、山脉、洞穴）, (4) 程序化纹理/贴图生成,
  (5) 相机抖动/屏幕震动效果, (6) procedural generation / noise,
  (7) 用户提到噪声、perlin、simplex 或程序化生成。
---
# Lua Noise — Procedural Noise Generation

Pure-Lua noise library for procedural content generation. Zero dependencies, Lua 5.4 compatible.

## Source Files

| File | Description |
|------|-------------|
| `src/noise.lua` | **All-in-one module** — Simplex 2D + Perlin 3D + FBM |
| `LICENSE` | MIT (dual: Ashima Arts/Mikael Lind + Leonard Somero) |

## When to Use

- Terrain heightmap generation (2D noise → height)
- Procedural textures (wood grain, marble, clouds)
- Animated effects (fire, smoke, water ripples)
- Object placement with natural distribution
- Camera shake / screen shake
- NPC wander behavior (smooth random movement)

## Setup

Copy `src/noise.lua` into the user's `scripts/` directory:

```lua
-- scripts/noise.lua (copy from skill)
-- Then in game code:
local Noise = require("noise")
```

## API Reference

### `Noise.simplex2d(x, y) → number`

2D Simplex noise based on Ashima Arts' webgl-noise.

| Parameter | Type | Description |
|-----------|------|-------------|
| x | number | X coordinate |
| y | number | Y coordinate |
| **returns** | number | **Range: [-1, 1]** |

**Properties:**
- Gradient noise (smooth, no grid artifacts)
- Computationally cheaper than classic Perlin
- Isotropic (no directional bias)
- Deterministic (same input → same output)
- Period: 289 (repeats after 289 units in any axis)

### `Noise.perlin3d(x, y, z) → number`

Classic 3D Perlin noise using Ken Perlin's improved algorithm.

| Parameter | Type | Description |
|-----------|------|-------------|
| x | number | X coordinate |
| y | number | Y coordinate |
| z | number | Z coordinate |
| **returns** | number | **Range: [0, 1]** |

**Properties:**
- Uses Ken Perlin's original permutation table (deterministic)
- 5th-degree fade curve (no second-derivative discontinuities)
- Period: 256 (repeats after 256 units in any axis)

> ⚠️ **Range difference**: `simplex2d` returns [-1,1], `perlin3d` returns [0,1].
> Normalize if mixing: `(simplex2d(x,y) + 1) / 2` to get [0,1].

### `Noise.fbm2d(x, y, [octaves, lacunarity, gain]) → number`

Fractal Brownian Motion using simplex2d as base.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| x | number | — | X coordinate |
| y | number | — | Y coordinate |
| octaves | number | 4 | Number of noise layers |
| lacunarity | number | 2.0 | Frequency multiplier per octave |
| gain | number | 0.5 | Amplitude multiplier per octave |
| **returns** | number | — | **Range: approximately [-1, 1]** |

### `Noise.fbm3d(x, y, z, [octaves, lacunarity, gain]) → number`

Fractal Brownian Motion using perlin3d as base.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| x | number | — | X coordinate |
| y | number | — | Y coordinate |
| z | number | — | Z coordinate |
| octaves | number | 4 | Number of noise layers |
| lacunarity | number | 2.0 | Frequency multiplier per octave |
| gain | number | 0.5 | Amplitude multiplier per octave |
| **returns** | number | — | **Range: approximately [0, 1]** |

## Parameter Tuning Guide

### Frequency (Scale)

The input coordinates control effective frequency:

```lua
-- Low frequency = large smooth features (continents)
local h = Noise.simplex2d(x * 0.01, y * 0.01)

-- High frequency = small noisy details (gravel)
local h = Noise.simplex2d(x * 0.5, y * 0.5)
```

### FBM Octaves

| Octaves | Effect | Performance |
|---------|--------|-------------|
| 1 | Smooth blobs | Fastest |
| 2-3 | Soft terrain, clouds | Good |
| 4-6 | Detailed terrain | Moderate |
| 8+ | Extreme detail | Expensive |

### Lacunarity & Gain

| lacunarity | gain | Result |
|-----------|------|--------|
| 2.0 | 0.5 | **Standard** — natural-looking terrain |
| 2.0 | 0.7 | Rougher — rocky surfaces |
| 2.0 | 0.3 | Smoother — rolling hills |
| 3.0 | 0.5 | Sharper frequency jumps |

## UrhoX Integration Patterns

### Pattern 1: Terrain Heightmap (Tile-based 2D game)

```lua
local Noise = require("noise")

local MAP_W, MAP_H = 64, 64
local SCALE = 0.08  -- controls terrain "zoom"

local function generateHeightmap(seed)
    local map = {}
    for y = 1, MAP_H do
        map[y] = {}
        for x = 1, MAP_W do
            -- Use seed as offset for different worlds
            local nx = (x + seed * 1000) * SCALE
            local ny = (y + seed * 1000) * SCALE
            -- FBM for multi-scale detail
            local h = Noise.fbm2d(nx, ny, 5, 2.0, 0.5)
            -- Normalize from [-1,1] to [0,1]
            map[y][x] = (h + 1) / 2
        end
    end
    return map
end

-- Terrain type thresholds
local function getTileType(height)
    if height < 0.3 then return "water"
    elseif height < 0.4 then return "sand"
    elseif height < 0.7 then return "grass"
    elseif height < 0.85 then return "rock"
    else return "snow"
    end
end
```

### Pattern 2: 3D Terrain Mesh (UrhoX 3D scene)

```lua
local Noise = require("noise")

local function createTerrainNode(scene, width, depth, scale, heightScale)
    scale = scale or 0.05
    heightScale = heightScale or 10.0

    local terrainNode = scene:CreateChild("Terrain")
    local geom = terrainNode:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    for z = 0, depth - 1 do
        for x = 0, width - 1 do
            -- Sample height at 4 corners of each quad
            local h00 = Noise.fbm2d(x * scale, z * scale, 5) * heightScale
            local h10 = Noise.fbm2d((x+1) * scale, z * scale, 5) * heightScale
            local h01 = Noise.fbm2d(x * scale, (z+1) * scale, 5) * heightScale
            local h11 = Noise.fbm2d((x+1) * scale, (z+1) * scale, 5) * heightScale

            -- Triangle 1
            geom:DefineVertex(Vector3(x, h00, z))
            geom:DefineNormal(Vector3(0, 1, 0))
            geom:DefineTexCoord(Vector2(x/width, z/depth))

            geom:DefineVertex(Vector3(x+1, h10, z))
            geom:DefineNormal(Vector3(0, 1, 0))
            geom:DefineTexCoord(Vector2((x+1)/width, z/depth))

            geom:DefineVertex(Vector3(x, h01, z+1))
            geom:DefineNormal(Vector3(0, 1, 0))
            geom:DefineTexCoord(Vector2(x/width, (z+1)/depth))

            -- Triangle 2
            geom:DefineVertex(Vector3(x+1, h10, z))
            geom:DefineNormal(Vector3(0, 1, 0))
            geom:DefineTexCoord(Vector2((x+1)/width, z/depth))

            geom:DefineVertex(Vector3(x+1, h11, z+1))
            geom:DefineNormal(Vector3(0, 1, 0))
            geom:DefineTexCoord(Vector2((x+1)/width, (z+1)/depth))

            geom:DefineVertex(Vector3(x, h01, z+1))
            geom:DefineNormal(Vector3(0, 1, 0))
            geom:DefineTexCoord(Vector2(x/width, (z+1)/depth))
        end
    end

    geom:Commit()
    -- Apply material...
    return terrainNode
end
```

### Pattern 3: Animated Cloud / Fog (NanoVG 2D)

```lua
local Noise = require("noise")
local time = 0

function HandleNanoVGRender(eventType, eventData)
    nvgBeginFrame(vg, W, H, 1.0)
    time = time + 0.01

    -- Use 3D perlin with Z=time for smooth animation
    for y = 0, H - 1, 8 do
        for x = 0, W - 1, 8 do
            local nx = x * 0.005
            local ny = y * 0.005
            local val = Noise.perlin3d(nx, ny, time)  -- [0,1]
            local alpha = val * 0.6
            nvgBeginPath(vg)
            nvgRect(vg, x, y, 8, 8)
            nvgFillColor(vg, nvgRGBAf(1, 1, 1, alpha))
            nvgFill(vg)
        end
    end

    nvgEndFrame(vg)
end
```

### Pattern 4: Procedural Object Placement

```lua
local Noise = require("noise")

--- Place trees/rocks with natural-looking distribution
local function placeObjects(scene, areaSize, density, seed)
    local placed = {}
    local spacing = 1.0 / density

    for z = 0, areaSize, spacing do
        for x = 0, areaSize, spacing do
            -- Use noise to determine if object should be placed here
            local n = Noise.simplex2d(
                (x + seed) * 0.1,
                (z + seed) * 0.1
            )
            -- Threshold controls sparseness
            if n > 0.2 then
                -- Jitter position using noise for organic look
                local jx = Noise.simplex2d(x * 0.5 + 100, z * 0.5) * spacing * 0.3
                local jz = Noise.simplex2d(x * 0.5, z * 0.5 + 100) * spacing * 0.3

                local px = x + jx
                local pz = z + jz
                -- Get terrain height at this position
                local py = Noise.fbm2d(px * 0.05, pz * 0.05, 4) * 10

                local node = scene:CreateChild("Tree")
                node.position = Vector3(px, py, pz)
                -- Vary scale with noise
                local s = 0.8 + Noise.simplex2d(x * 0.3 + 200, z * 0.3) * 0.4
                node.scale = Vector3(s, s, s)
                table.insert(placed, node)
            end
        end
    end
    return placed
end
```

### Pattern 5: Camera Shake

```lua
local Noise = require("noise")

local shakeIntensity = 0
local shakeTime = 0

--- Trigger camera shake
function TriggerShake(intensity, duration)
    shakeIntensity = intensity
    -- duration handled by decay
end

--- Call in HandleUpdate
function UpdateCameraShake(dt, cameraNode, basePosition)
    if shakeIntensity < 0.001 then
        cameraNode.position = basePosition
        return
    end

    shakeTime = shakeTime + dt * 20  -- speed of shake

    -- Use noise for smooth organic shake (not random jitter)
    local offsetX = Noise.simplex2d(shakeTime, 0) * shakeIntensity
    local offsetY = Noise.simplex2d(0, shakeTime) * shakeIntensity

    cameraNode.position = basePosition + Vector3(offsetX, offsetY, 0)

    -- Decay
    shakeIntensity = shakeIntensity * (1 - dt * 5)
end
```

### Pattern 6: Domain Warping (Advanced)

```lua
local Noise = require("noise")

--- Domain warping creates organic, flowing shapes
--- by feeding noise into itself.
local function warpedNoise(x, y, warpStrength)
    warpStrength = warpStrength or 4.0

    -- First pass: compute warp offset
    local qx = Noise.fbm2d(x, y, 4)
    local qy = Noise.fbm2d(x + 5.2, y + 1.3, 4)

    -- Second pass: sample at warped position
    return Noise.fbm2d(
        x + qx * warpStrength,
        y + qy * warpStrength,
        4
    )
end

-- Usage: creates swirling, marble-like patterns
local val = warpedNoise(x * 0.02, y * 0.02, 4.0)
```

## Performance Tips

1. **Cache noise values** — noise is deterministic, don't recompute same coords:
   ```lua
   -- Pre-compute heightmap once, not every frame
   local heightCache = {}
   ```

2. **Reduce octaves for real-time** — 2-3 octaves for per-frame animation, 6+ only for one-time generation.

3. **Scale coordinates wisely** — very small scale (0.001) means adjacent samples are nearly identical; very large scale (10.0) means chaotic noise.

4. **Use perlin3d(x, y, time) for animation** — smoother than incrementing 2D noise seed.

5. **Chunk-based generation** — for large worlds, generate per-chunk and cache:
   ```lua
   local chunks = {}
   local function getChunkNoise(cx, cy)
       local key = cx .. "," .. cy
       if not chunks[key] then
           chunks[key] = generateChunk(cx, cy)
       end
       return chunks[key]
   end
   ```

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Noise looks like static/random | Scale down coordinates: `x * 0.01` instead of `x` |
| Terrain is too smooth | Increase octaves or gain |
| Visible grid patterns | Use simplex2d (no grid bias) or add slight rotation to perlin coords |
| Same world every time | Offset coords by seed: `Noise.simplex2d(x + seed*1000, y)` |
| Animation stutters | Use `perlin3d(x, y, time)` not `simplex2d(x + time, y)` |
| Range mismatch | simplex2d is [-1,1], perlin3d is [0,1] — normalize when mixing |

## Algorithm Comparison

| Feature | simplex2d | perlin3d |
|---------|-----------|----------|
| Dimensions | 2D | 3D |
| Output range | [-1, 1] | [0, 1] |
| Algorithm | Simplex (Gustavson) | Classic Perlin (improved) |
| Grid artifacts | None | Minimal (5th-degree fade) |
| Speed (relative) | Faster | Slightly slower (3D) |
| Best for | Heightmaps, 2D textures | Volumetric, animated noise |
