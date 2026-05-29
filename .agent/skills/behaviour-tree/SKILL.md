---
name: behaviour-tree
description: |
  纯 Lua 行为树 AI 库，支持 Sequence、Priority、Decorator、running 状态，适用于 NPC/Boss/宠物 AI。
  Use when users need to (1) NPC AI 行为逻辑（巡逻/追击/攻击）, (2) Boss 战多阶段 AI,
  (3) 宠物/同伴跟随与自主行为, (4) 塔防敌人决策树, (5) 行为树/决策树/AI 状态管理,
  (6) behaviour tree / behavior tree / BT AI, (7) 用户提到行为树或 NPC 智能行为。
---
# BehaviourTree.lua — AI Behavior Trees

Pure-Lua behavior tree library for game AI. Supports tasks, sequences, priority selectors, random selectors, decorators, and the `running` state for multi-frame actions.

**Source**: [tanema/behaviourtree.lua](https://github.com/tanema/behaviourtree.lua) (141 stars, MIT)

## Source Files

```
src/lib/
├── init.lua                    # Entry point (require this)
├── behaviour_tree.lua          # BehaviourTree class (root)
├── middleclass.lua             # OOP library (dependency)
├── registry.lua                # Named node registry
└── node_types/
    ├── node.lua                # Base Node (Task/leaf)
    ├── branch_node.lua         # Base for composite nodes
    ├── sequence.lua            # Sequence (AND)
    ├── priority.lua            # Priority/Selector (OR)
    ├── active_priority.lua     # ActivePriority (re-evaluates)
    ├── random.lua              # Random selector
    ├── decorator.lua           # Base decorator
    ├── invert_decorator.lua    # Inverts success/fail
    ├── always_fail_decorator.lua
    └── always_succeed_decorator.lua
```

## When to Use

- NPC AI (patrol → chase → attack patterns)
- Enemy wave behaviors
- Boss fight state logic
- Companion/pet AI
- Any entity needing reactive, hierarchical decision-making

## Setup

Copy `src/lib/` directory into the user's `scripts/` as `scripts/behaviourtree/`:

```lua
-- In game code:
local BT = require("behaviourtree")
```

## Core Concepts

### Node Results

Every node must call exactly ONE of these:

| Method | Meaning |
|--------|---------|
| `task:success()` | Task completed successfully |
| `task:fail()` | Task failed |
| `task:running()` | Task still in progress (will resume next `tree:run()`) |

### Node Types

| Type | Behavior |
|------|----------|
| **Task** | Leaf node — does actual work |
| **Sequence** | Runs children left-to-right; fails on first failure (AND logic) |
| **Priority** | Runs children left-to-right; succeeds on first success (OR logic / Selector) |
| **ActivePriority** | Like Priority but re-evaluates from start when a child returns `running` |
| **Random** | Picks one random child to run |
| **Decorator** | Wraps a single node, modifies its result |

## API Reference

### `BT:new(config) → BehaviourTree`

Create a new behavior tree.

```lua
local tree = BT:new({
    tree = rootNode,    -- Root node (Task, Sequence, Priority, etc.)
    object = entity,    -- (optional) Object passed to all node methods
})
```

### `tree:run([object])`

Execute one tick of the behavior tree. Call this once per frame (or per AI update).

- If a node previously returned `running`, execution resumes from that node.
- Optional `object` parameter overrides the tree's stored object.

### `tree:setObject(object)`

Set/change the object (blackboard/entity) passed to all nodes.

### `BT.Task:new(config) → Task`

Create a leaf node.

```lua
local task = BT.Task:new({
    start = function(task, obj) end,   -- (optional) Called before run (not on resume)
    finish = function(task, obj) end,  -- (optional) Called after success/fail (not after running)
    run = function(task, obj)          -- (required) Main logic
        -- Must call one of:
        task:success()
        task:fail()
        task:running()
    end,
})
```

**Alternative style** (method override):
```lua
local task = BT.Task:new()
function task:run(obj)
    self:success()
end
```

### `BT.Sequence:new({ nodes = {...} }) → Sequence`

AND-logic composite. Runs children sequentially; stops on first `fail()`.

```lua
local seq = BT.Sequence:new({
    nodes = { taskA, taskB, taskC }
    -- Runs A, then B, then C. If any fails, sequence fails.
    -- If all succeed, sequence succeeds.
})
```

### `BT.Priority:new({ nodes = {...} }) → Priority`

OR-logic composite (also called Selector). Runs children sequentially; stops on first `success()`.

```lua
local sel = BT.Priority:new({
    nodes = { taskA, taskB, taskC }
    -- Tries A first. If A fails, tries B. If B fails, tries C.
    -- If any succeeds, selector succeeds. If all fail, selector fails.
})
```

### `BT.ActivePriority:new({ nodes = {...} }) → ActivePriority`

Like Priority, but when a child returns `running`, it re-evaluates from the first child on next tick. If a higher-priority child now succeeds, the previously-running lower child is interrupted (`finish` called).

**Use for**: behaviors that should be preempted by higher-priority conditions (e.g., "flee" should interrupt "patrol" when enemy appears).

### `BT.Random:new({ nodes = {...} }) → Random`

Randomly picks one child to execute. If it returns `running`, the same child continues on next tick.

### `BT.InvertDecorator:new({ node = childNode }) → Decorator`

Flips success ↔ fail.

### `BT.AlwaysSucceedDecorator:new({ node = childNode }) → Decorator`

Always returns success regardless of child result.

### `BT.AlwaysFailDecorator:new({ node = childNode }) → Decorator`

Always returns fail regardless of child result.

### `BT.register(name, node)` / Named Nodes

Register a node by name for reuse:

```lua
BT.register('patrol', patrolTask)

-- Reference by string in trees:
local tree = BT:new({
    tree = BT.Sequence:new({ nodes = { 'patrol', 'attack' } })
})
```

Or auto-register by giving a node a `name` field:

```lua
BT.Task:new({ name = 'patrol', run = function(task, obj) ... end })
```

## UrhoX Integration Patterns

### Pattern 1: Basic NPC AI (Patrol + Chase + Attack)

```lua
local BT = require("behaviourtree")

-- Task: Check if player is in range
local checkPlayerNear = BT.Task:new({
    run = function(task, npc)
        local playerPos = playerNode.position
        local dist = (playerPos - npc.node.position):Length()
        if dist < npc.detectRange then
            npc.targetPos = playerPos
            task:success()
        else
            task:fail()
        end
    end
})

-- Task: Check if player is in attack range
local checkAttackRange = BT.Task:new({
    run = function(task, npc)
        local dist = (playerNode.position - npc.node.position):Length()
        if dist < npc.attackRange then
            task:success()
        else
            task:fail()
        end
    end
})

-- Task: Move toward target (multi-frame)
local moveToTarget = BT.Task:new({
    run = function(task, npc)
        local dir = (npc.targetPos - npc.node.position):Normalized()
        npc.node.position = npc.node.position + dir * npc.speed * timeStep
        local dist = (npc.targetPos - npc.node.position):Length()
        if dist < 0.5 then
            task:success()
        else
            task:running()  -- continue next frame
        end
    end
})

-- Task: Attack
local attackPlayer = BT.Task:new({
    start = function(task, npc)
        npc.attackTimer = 0
    end,
    run = function(task, npc)
        npc.attackTimer = npc.attackTimer + timeStep
        if npc.attackTimer >= npc.attackCooldown then
            -- Deal damage
            task:success()
        else
            task:running()
        end
    end
})

-- Task: Patrol to random point
local patrol = BT.Task:new({
    start = function(task, npc)
        npc.targetPos = Vector3(
            npc.homePos.x + math.random(-5, 5),
            npc.homePos.y,
            npc.homePos.z + math.random(-5, 5)
        )
    end,
    run = function(task, npc)
        local dir = (npc.targetPos - npc.node.position):Normalized()
        npc.node.position = npc.node.position + dir * npc.speed * 0.5 * timeStep
        local dist = (npc.targetPos - npc.node.position):Length()
        if dist < 0.5 then
            task:success()
        else
            task:running()
        end
    end
})

-- Build the tree
local npcAI = BT:new({
    tree = BT.Priority:new({
        nodes = {
            -- Priority 1: Attack if in range
            BT.Sequence:new({
                nodes = { checkPlayerNear, checkAttackRange, attackPlayer }
            }),
            -- Priority 2: Chase if detected
            BT.Sequence:new({
                nodes = { checkPlayerNear, moveToTarget }
            }),
            -- Priority 3: Patrol (fallback)
            patrol,
        }
    })
})

-- In HandleUpdate:
function HandleUpdate(eventType, eventData)
    timeStep = eventData["TimeStep"]:GetFloat()
    npcAI:setObject(npcData)
    npcAI:run()
end
```

### Pattern 2: Tower Defense Enemy Wave AI

```lua
local BT = require("behaviourtree")

local function createEnemyAI(enemy)
    -- Check if reached current waypoint
    local atWaypoint = BT.Task:new({
        run = function(task, e)
            local dist = (e.waypoints[e.waypointIdx] - e.node.position):Length()
            if dist < 0.3 then
                task:success()
            else
                task:fail()
            end
        end
    })

    -- Advance waypoint index
    local nextWaypoint = BT.Task:new({
        run = function(task, e)
            e.waypointIdx = e.waypointIdx + 1
            if e.waypointIdx > #e.waypoints then
                -- Reached end — damage base
                e.reachedEnd = true
                task:fail()  -- stop tree
            else
                task:success()
            end
        end
    })

    -- Move toward current waypoint
    local moveToWaypoint = BT.Task:new({
        run = function(task, e)
            local target = e.waypoints[e.waypointIdx]
            local dir = (target - e.node.position):Normalized()
            e.node.position = e.node.position + dir * e.speed * timeStep
            task:running()  -- always running (checked by atWaypoint)
        end
    })

    return BT:new({
        object = enemy,
        tree = BT.Priority:new({
            nodes = {
                -- If at waypoint, advance to next
                BT.Sequence:new({ nodes = { atWaypoint, nextWaypoint } }),
                -- Otherwise keep moving
                moveToWaypoint,
            }
        })
    })
end
```

### Pattern 3: Boss Fight Phases

```lua
local BT = require("behaviourtree")

local function createBossAI(boss)
    -- Condition: health check
    local isPhase2 = BT.Task:new({
        run = function(task, b)
            if b.hp < b.maxHp * 0.5 then task:success()
            else task:fail() end
        end
    })

    local isPhase3 = BT.Task:new({
        run = function(task, b)
            if b.hp < b.maxHp * 0.2 then task:success()
            else task:fail() end
        end
    })

    -- Phase 1: Simple melee
    local meleeAttack = BT.Task:new({
        start = function(task, b) b.animTimer = 0 end,
        run = function(task, b)
            b.animTimer = b.animTimer + timeStep
            if b.animTimer > 1.0 then
                -- damage player
                task:success()
            else
                task:running()
            end
        end
    })

    -- Phase 2: Ranged + summon minions
    local summonMinions = BT.Task:new({
        run = function(task, b)
            if b.summonCooldown <= 0 then
                spawnMinions(b.node.position, 3)
                b.summonCooldown = 10.0
                task:success()
            else
                b.summonCooldown = b.summonCooldown - timeStep
                task:fail()
            end
        end
    })

    -- Phase 3: Enrage
    local enrage = BT.Task:new({
        start = function(task, b) b.speed = b.speed * 2 end,
        run = function(task, b)
            meleeAttack:run(b)  -- faster attacks
        end
    })

    return BT:new({
        object = boss,
        tree = BT.ActivePriority:new({
            nodes = {
                -- Highest priority: Phase 3 (enrage)
                BT.Sequence:new({ nodes = { isPhase3, enrage } }),
                -- Phase 2: summon + melee
                BT.Sequence:new({ nodes = {
                    isPhase2,
                    BT.Priority:new({ nodes = { summonMinions, meleeAttack } })
                }}),
                -- Phase 1: just melee
                meleeAttack,
            }
        })
    })
end
```

### Pattern 4: Companion/Pet AI

```lua
local BT = require("behaviourtree")

local function createPetAI(pet)
    local followDistance = 3.0
    local interactDistance = 1.5

    -- Is owner too far?
    local ownerFar = BT.Task:new({
        run = function(task, p)
            local dist = (p.ownerNode.position - p.node.position):Length()
            if dist > followDistance then task:success()
            else task:fail() end
        end
    })

    -- Follow owner
    local followOwner = BT.Task:new({
        run = function(task, p)
            local dir = (p.ownerNode.position - p.node.position):Normalized()
            p.node.position = p.node.position + dir * p.speed * timeStep
            local dist = (p.ownerNode.position - p.node.position):Length()
            if dist <= followDistance then
                task:success()
            else
                task:running()
            end
        end
    })

    -- Is there a collectible nearby?
    local findCollectible = BT.Task:new({
        run = function(task, p)
            -- Search scene for nearest collectible
            for _, item in ipairs(collectibles) do
                local dist = (item.position - p.node.position):Length()
                if dist < 5.0 then
                    p.targetItem = item
                    task:success()
                    return
                end
            end
            task:fail()
        end
    })

    -- Fetch collectible
    local fetchItem = BT.Task:new({
        run = function(task, p)
            if not p.targetItem then task:fail() return end
            local dir = (p.targetItem.position - p.node.position):Normalized()
            p.node.position = p.node.position + dir * p.speed * 1.5 * timeStep
            local dist = (p.targetItem.position - p.node.position):Length()
            if dist < 0.3 then
                pickUpItem(p.targetItem)
                p.targetItem = nil
                task:success()
            else
                task:running()
            end
        end
    })

    -- Idle animation
    local idle = BT.Task:new({
        run = function(task, p)
            -- Play idle anim, always succeeds
            task:success()
        end
    })

    return BT:new({
        object = pet,
        tree = BT.ActivePriority:new({
            nodes = {
                -- Top priority: follow if too far
                BT.Sequence:new({ nodes = { ownerFar, followOwner } }),
                -- Second: fetch nearby items
                BT.Sequence:new({ nodes = { findCollectible, fetchItem } }),
                -- Fallback: idle
                idle,
            }
        })
    })
end
```

## Key Design Patterns

### Blackboard Pattern

Pass shared state through the `object` parameter:

```lua
local blackboard = {
    node = npcNode,       -- scene node reference
    hp = 100,
    speed = 5.0,
    targetPos = nil,      -- set by detection tasks
    attackTimer = 0,      -- used by attack tasks
}

tree:setObject(blackboard)
tree:run()
```

### Condition + Action Pairs

Standard BT pattern: condition task → action task in a Sequence:

```lua
BT.Sequence:new({
    nodes = {
        conditionTask,  -- checks state, calls success/fail
        actionTask,     -- does work if condition passed
    }
})
```

### Running State for Multi-Frame Actions

Tasks that take multiple frames use `running()`:

```lua
local moveTask = BT.Task:new({
    run = function(task, obj)
        -- Move a bit each frame
        obj.node.position = obj.node.position + obj.velocity * timeStep
        if reachedTarget(obj) then
            task:success()   -- done\!
        else
            task:running()   -- continue next frame
        end
    end
})
```

**Important**: When a task calls `running()`, on the next `tree:run()`:
- Execution resumes from that exact task (parents are not re-evaluated)
- `start()` is NOT called again
- Use `ActivePriority` instead of `Priority` if you need re-evaluation

### Custom Decorators

Create project-specific decorators:

```lua
-- Cooldown decorator: only allows child to run every N seconds
local CooldownDecorator = BT.Decorator:new()
function CooldownDecorator:run(obj)
    if (os.clock() - (self.lastRun or 0)) >= self.cooldown then
        self.lastRun = os.clock()
        BT.Decorator.run(self, obj)  -- run child
    else
        self:fail()
    end
end

-- Usage:
local cooledAttack = CooldownDecorator:new({
    cooldown = 2.0,
    node = attackTask
})
```

## Performance Tips

1. **One tree per entity** — each NPC/enemy gets its own `BT:new()` instance.

2. **Don't tick every frame** — for large numbers of entities, stagger updates:
   ```lua
   -- Update subsets each frame
   local AI_TICK = 0.1  -- 10 Hz
   npc.aiTimer = (npc.aiTimer or 0) + dt
   if npc.aiTimer >= AI_TICK then
       npc.aiTimer = 0
       npc.tree:run()
   end
   ```

3. **Use `running` wisely** — avoid expensive checks in nodes that return `running` frequently.

4. **ActivePriority vs Priority** — `ActivePriority` re-checks higher nodes every tick (more reactive but more expensive). Use `Priority` for static decision points.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Task never calls success/fail/running | Every `run()` MUST call exactly one of the three |
| Tree doesn't reset after completion | It auto-resets; just call `tree:run()` again |
| Node unexpectedly re-runs from start | A `running` node resumes without `start()`; init state in `start()` |
| `ActivePriority` interrupts task mid-action | Use `finish()` to clean up interrupted tasks |
| Referencing node by string but not registered | Call `BT.register('name', node)` before building tree |
| Multiple trees sharing same task instance | Each tree should have its own task instances (or use named registry) |

## Node Type Selection Guide

```
Need to do A, then B, then C in order?
  → Sequence

Need to try A, if fails try B, if fails try C?
  → Priority

Need to pick one randomly?
  → Random

Need higher-priority check to interrupt current action?
  → ActivePriority

Need to flip/modify a child's result?
  → Decorator (Invert, AlwaysFail, AlwaysSucceed, or custom)
```
