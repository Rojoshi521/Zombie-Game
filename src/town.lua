-- Procedural ruined town around the settlement, different every run.
-- Streets are two tiles wide on a fixed grid; the blocks between them are
-- filled with houses, shops, lots and a few landmarks, each turned to face
-- its nearest street. Wrecks litter the roads and packs of infected lurk.
local D = require("src.data")
local U = require("src.util")
local S = require("src.structures")

local Town = {}

-- streets start on these cells, both across and down the map
Town.STREETS = { 7, 19, 31, 44, 57, 69, 81 }

-- which way a building faces, by the side its street is on
local FACING = { south = "front", east = "left", north = "back", west = "right" }

function Town.rollLoot(kind)
  local out = {}
  for k, v in pairs(D.LOOT[kind] or {}) do
    local n
    if type(v) == "table" then n = love.math.random(v[1], v[2]) else n = love.math.random() < v and 1 or 0 end
    if n > 0 then out[k] = n end
  end
  return out
end

-- Where survivors stand to search a building: just outside its front door.
function Town.entrance(s)
  local f = s.facing
  if f == "front" then return s.cx, s.wy2 + 0.6 end
  if f == "left" then return s.wx2 + 0.6, s.cy end
  if f == "back" then return s.cx, s.wy1 - 0.6 end
  return s.wx1 - 0.6, s.cy
end

local function ranges(streets, size)
  local out, start = {}, 1
  for _, s in ipairs(streets) do
    if s - 1 >= start then out[#out + 1] = { start, s - 1 } end
    start = s + 2
  end
  if start <= size then out[#out + 1] = { start, size } end
  return out
end

-- base: { min, max } of the cells kept clear around the walls
function Town.generate(game, W, H, base)
  local map = game.map
  local function inClear(cx, cy)
    return cx >= base.min and cx <= base.max and cy >= base.min and cy <= base.max
  end

  local function inWalls(cx, cy)
    return cx >= base.fmin and cx <= base.fmax and cy >= base.fmin and cy <= base.fmax
  end

  -- Streets run everywhere outside the walls. 1 = runs across (along x),
  -- 2 = runs down (along y), 3 = crossing.
  local road = {}
  for _, s in ipairs(Town.STREETS) do
    for k = 1, math.max(W, H) do
      for d = 0, 1 do
        if k <= W and not inWalls(k, s + d) then
          local i = map:idx(k, s + d)
          road[i] = (road[i] or 0) + 1
        end
        if k <= H and not inWalls(s + d, k) then
          local i = map:idx(s + d, k)
          road[i] = (road[i] or 0) + 2
        end
      end
    end
  end
  game.townRoad = road

  local sites = {}
  local function place(entry, size, x, y, view)
    local sp = S.townSprite(entry.id .. "_" .. view, size)
    if not sp then return nil end
    local flat = entry.flat or false
    local s = game:addStructure("town", x, y, {
      w = size, h = size, sprite = sp, town = true, name = entry.name,
      blocking = not flat, flat = flat, solid = not flat, facing = view,
    })
    if entry.loot then
      s.site = { loot = Town.rollLoot(entry.loot), work = 7 + size * 3, progress = 0 }
      sites[#sites + 1] = s
    end
    return s
  end

  local xr, yr = ranges(Town.STREETS, W), ranges(Town.STREETS, H)
  local blocks = {}
  for _, rx in ipairs(xr) do
    for _, ry in ipairs(yr) do
      local overlap = rx[2] >= base.min and rx[1] <= base.max and ry[2] >= base.min and ry[1] <= base.max
      if not overlap then
        blocks[#blocks + 1] = { x0 = rx[1], x1 = rx[2], y0 = ry[1], y1 = ry[2],
          edge = rx[1] == 1 or ry[1] == 1 or rx[2] == W or ry[2] == H }
      end
    end
  end

  -- landmarks take the middle of three inner blocks
  local inner = {}
  for _, b in ipairs(blocks) do
    if not b.edge then inner[#inner + 1] = b end
  end
  U.shuffle(inner)
  for i, lm in ipairs(D.TOWN_LANDMARKS) do
    local b = inner[i]
    if b then
      local lx = b.x0 + math.floor((b.x1 - b.x0 + 1 - lm.size) / 2)
      local ly = b.y0 + math.floor((b.y1 - b.y0 + 1 - lm.size) / 2)
      local view = (lm.views and lm.views[1]) or "front"
      place(lm, lm.size, lx, ly, view)
      b.landmark = { lx - 1, ly - 1, lx + lm.size, ly + lm.size }
    end
  end

  local function facingFor(b, x, y, size)
    local d = {
      north = b.y0 == 1 and 99 or y - b.y0,
      south = b.y1 == H and 99 or b.y1 - (y + size - 1),
      west = b.x0 == 1 and 99 or x - b.x0,
      east = b.x1 == W and 99 or b.x1 - (x + size - 1),
    }
    local best, bd = "south", 999
    for _, side in ipairs({ "south", "east", "north", "west" }) do
      if d[side] < bd then best, bd = side, d[side] end
    end
    return FACING[best]
  end

  for _, b in ipairs(blocks) do
    local used = {}
    -- pick from a list, avoiding anything this block already has
    local function pickFrom(list)
      for _ = 1, 6 do
        local e = U.choice(list)
        if not used[e.id] then
          used[e.id] = true
          return e
        end
      end
      return nil
    end
    for sx = b.x0 + 1, b.x1 - 2, 3 do
      for sy = b.y0 + 1, b.y1 - 2, 3 do
        local lm = b.landmark
        local clash = lm and sx + 1 >= lm[1] and sx <= lm[3] and sy + 1 >= lm[2] and sy <= lm[4]
        if not clash then
          local r = love.math.random()
          local entry
          if b.edge then
            if r < 0.35 then entry = pickFrom(D.TOWN_LOTS) end
          elseif r < 0.42 then entry = pickFrom(D.TOWN_HOUSES)
          elseif r < 0.62 then entry = pickFrom(D.TOWN_SHOPS)
          elseif r < 0.68 then entry = pickFrom(D.TOWN_SPECIALS)
          elseif r < 0.80 then entry = pickFrom(D.TOWN_LOTS)
          end
          if entry then
            if not entry.loot and not entry.flat and entry.id ~= "pond" and entry.id ~= "hill" then
              entry = setmetatable({ loot = "house" }, { __index = entry })
            end
            place(entry, 2, sx, sy, facingFor(b, sx, sy, 2))
          end
        end
      end
    end
  end

  -- wrecks on the streets, never blocking both lanes
  local roadCells = {}
  for i, v in pairs(road) do
    if v < 3 then roadCells[#roadCells + 1] = i end
  end
  U.shuffle(roadCells)
  local placed = 0
  for _, i in ipairs(roadCells) do
    if placed >= 34 then break end
    local cx, cy = map:cellXY(i)
    local free = not map:structure(cx, cy)
    for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }) do
      if map:structure(cx + o[1], cy + o[2]) then free = false end
    end
    if free and not inClear(cx, cy) then
      local kind = U.choice(D.TOWN_WRECKS)
      local sp = S.townSprite(kind .. "_" .. U.choice({ "front", "left", "back", "right" }), 1)
      if sp then
        local s = game:addStructure("wreck", cx, cy, {
          sprite = sp, town = true, solid = true, fire = kind:match("fire") ~= nil,
          name = kind:match("truck") and "Wrecked Truck" or "Wrecked Car", facing = "front",
        })
        if love.math.random() < 0.5 then
          s.site = { loot = Town.rollLoot("jam"), work = 4, progress = 0 }
          sites[#sites + 1] = s
        end
        placed = placed + 1
      end
    end
  end

  -- Infected lurking around buildings and wandering the streets: rarer close
  -- to the walls, so the first trips out are survivable.
  local mid = (base.min + base.max) / 2
  for _, s in ipairs(sites) do
    local far = math.max(math.abs(s.cx - mid), math.abs(s.cy - mid))
    local chance = far < 24 and 0.1 or (far < 34 and 0.22 or 0.32)
    if s.kind ~= "wreck" and love.math.random() < chance then
      local ex, ey = Town.entrance(s)
      for _ = 1, love.math.random(1, far < 34 and 2 or 4) do
        game:spawnRoamer(ex + (love.math.random() - 0.5) * 3, ey + (love.math.random() - 0.5) * 3)
      end
    end
  end
  for k = 1, 15 do
    local i = roadCells[#roadCells - k]
    if i then
      local cx, cy = map:cellXY(i)
      if not inClear(cx, cy) then game:spawnRoamer(cx - 0.5, cy - 0.5) end
    end
  end

  game.sites = sites
end

return Town
