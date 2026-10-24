-- Settlement structures: definitions and their code-drawn art.
local Iso = require("src.iso")
local G = require("src.gfx")
local D = require("src.data")

local C = G.C
local P = Iso.toScreen
local lg = love.graphics

local S = {}

----------------------------------------------------------------------------
-- Painted sprites

S.sprites = {}

function S.loadSprites()
  for id, def in pairs(D.SPRITES) do
    local path = "assets/buildings/" .. id .. ".png"
    if love.filesystem.getInfo(path) then
      local img = lg.newImage(path, { mipmaps = true })
      local glow = lg.newImage("assets/buildings/" .. id .. "_glow.png", { mipmaps = true })
      img:setMipmapFilter("linear")
      glow:setMipmapFilter("linear")
      S.sprites[id] = { img = img, glow = glow, def = def }
    end
  end
end

-- Town sprites carry their own anchors (assets/town/index.lua). Their scale
-- depends on the footprint they are given, so each size gets its own entry.
function S.townSprite(id, size)
  local key = id .. "@" .. size
  if S.sprites[key] then return key end
  S.townIndex = S.townIndex or (love.filesystem.getInfo("assets/town/index.lua")
    and love.filesystem.load("assets/town/index.lua")() or {})
  local meta = S.townIndex[id]
  if not meta then return nil end
  local img = lg.newImage("assets/town/" .. id .. ".png", { mipmaps = true })
  local glow = lg.newImage("assets/town/" .. id .. "_glow.png", { mipmaps = true })
  img:setMipmapFilter("linear")
  glow:setMipmapFilter("linear")
  S.sprites[key] = {
    img = img, glow = glow,
    def = { ax = meta.ax, ay = meta.ay, scale = size * 64 / meta.plate, foot = size },
  }
  return key
end

function S.spriteFor(s)
  return s.sprite and S.sprites[s.sprite] or nil
end

----------------------------------------------------------------------------
-- Painted props

S.props = {}

function S.loadProps()
  for id, def in pairs(D.PROPS) do
    local path = "assets/props/" .. id .. ".png"
    if love.filesystem.getInfo(path) then
      local img = lg.newImage(path, { mipmaps = true })
      local glow = lg.newImage("assets/props/" .. id .. "_glow.png", { mipmaps = true })
      img:setMipmapFilter("linear")
      glow:setMipmapFilter("linear")
      local p = { img = img, glow = glow, def = def }
      if def.wall then
        local w, h = img:getDimensions()
        p.cw = (def.u1 - def.u0) / def.cells
        p.k = 32 / p.cw -- one slice spans one tile: 32 px across on screen
        p.quads = {}
        for i = 1, def.cells do
          p.quads[i] = lg.newQuad(def.u0 + (i - 1) * p.cw, 0, p.cw, h, w, h)
        end
      end
      S.props[id] = p
    end
  end
end

-- A prop standing on world point (x, y). Returns false if its art is missing.
function S.drawPoint(id, x, y, tint, flicker)
  local p = S.props[id]
  if not p then return false end
  local d = p.def
  local sx, sy = P(x, y, 0)
  local k = d.scale
  local c = tint or 1
  flicker = flicker or 1
  lg.setColor(c, c, c)
  lg.draw(p.img, sx, sy, 0, k, k, d.ax, d.ay)
  G.queueEmissive(p.glow, nil, sx, sy, k, k, d.ax, d.ay, 0, flicker)
  if d.light then
    local lx, ly = sx + (d.light[1] - d.ax) * k, sy + (d.light[2] - d.ay) * k
    local st = d.light[3] * flicker
    G.glow(lx, ly, 12 * st, { 1, 0.92, 0.75 }, 0.8)
    G.glow(lx, ly, 40 * st, C.amber, 0.25)
    G.lightAt(lx, (ly + sy) / 2 + 10, 200 * st, G.LIGHT, 1.05, 150 * st)
  end
  return true
end

-- One tile of a fence or gate: its own vertical slice of the wall painting,
-- sheared so the wall's bottom edge follows the tile grid.
local function drawWall(s)
  local p = S.props[s.gate and "gate" or "fence"]
  if not p then return false end
  local d = p.def
  local idx = s.strip or ((s.dir == "x" and s.x1 or s.y1) % d.cells)
  local quad = p.quads[idx + 1]
  local uc = d.u0 + (idx + 0.5) * p.cw
  local oy = d.base + d.slope * (uc - d.u0)
  local fx = s.dir == "x" and 1 or -1
  local sx, sy = P(s.cx, s.cy, 0)
  local c = 0.5 + 0.5 * (s.hp / s.maxhp)
  local ky = 0.5 - d.slope
  lg.setColor(c, c, c)
  lg.draw(p.img, quad, sx, sy, 0, fx * p.k, p.k, p.cw / 2, oy, 0, ky)
  G.queueEmissive(p.glow, quad, sx, sy, fx * p.k, p.k, p.cw / 2, oy, ky, 1)
  return true
end

-- Draws a building's painting (or its glow layer) over its footprint,
-- mirrored when the building is flipped.
local function drawSprite(s, sp, img)
  local sx, sy = P(s.cx, s.cy, 0)
  local d, k = sp.def, sp.def.scale
  lg.draw(img or sp.img, sx, sy, 0, s.flip and -k or k, k, d.ax, d.ay)
end
S.drawSpriteAt = drawSprite

-- The painting's on-screen box: left, top, width, height.
local function spriteBox(s, sp)
  local sx, sy = P(s.cx, s.cy, 0)
  local d, k = sp.def, sp.def.scale
  local w, h = sp.img:getWidth() * k, sp.img:getHeight() * k
  local left = s.flip and sx - (sp.img:getWidth() - d.ax) * k or sx - d.ax * k
  return left, sy - d.ay * k, w, h
end

-- The whole painting goes down in the ground pass so its yard lies under
-- units; the building itself is drawn again, clipped to its footprint, in the
-- depth-sorted pass so it can stand in front of people behind it.
function S.drawSpriteGround(s)
  local sp = S.spriteFor(s)
  lg.setColor(1, 1, 1)
  drawSprite(s, sp)
end

local function footprintStencil(s, m)
  local lx, ly = P(s.wx1 - m, s.wy2 + m)
  local bx, by = P(s.wx2 + m, s.wy2 + m)
  local rx, ry = P(s.wx2 + m, s.wy1 - m)
  lg.polygon("fill", lx, ly, bx, by, rx, ry, rx, ry - 4000, lx, ly - 4000)
end

local function drawSpriteBody(s)
  local sp = S.spriteFor(s)
  lg.setColor(1, 1, 1)
  if s.flat then
    -- walkable ground art (the garden): always under the people on it
    drawSprite(s, sp)
  else
    lg.stencil(function() footprintStencil(s, 0.45) end, "replace", 1)
    lg.setStencilTest("greater", 0)
    drawSprite(s, sp)
    lg.setStencilTest()
  end
  local x, y, w, h = spriteBox(s, sp)
  if s.fire then
    -- burning wrecks light the street around them
    local sx, sy = P(s.cx, s.cy, 0)
    local f = 0.8 + 0.2 * math.sin(love.timer.getTime() * 11 + s.seed) * math.sin(love.timer.getTime() * 6.3)
    G.glow(sx, sy - 14, 30 * f, { 1, 0.55, 0.2 }, 0.45)
    G.lightAt(sx, sy, 230 * f, { 1, 0.62, 0.3 }, 1.2, 160 * f)
  elseif not s.town then
    -- base paintings have their lighting baked in, so light them fully
    G.lightAt(x + w / 2, y + h * 0.55, w * 0.68, G.LIGHT, 1.7, h * 0.62)
  end
end

-- Lit windows, lamps and neon, added on top after the darkness is applied.
function S.drawEmissive(s, t)
  local sp = S.spriteFor(s)
  if not sp then return end
  local f = 0.85 + 0.15 * math.sin(t * 5.3 + s.seed) * math.sin(t * 2.1)
  lg.setColor(f, f * 0.95, f * 0.9, 0.9 * G.glowScale)
  drawSprite(s, sp, sp.glow)
end

-- Menu card preview: the painting or the code-drawn stand-in, centred.
function S.drawPreview(hqId, x, y, size, t)
  local sp = S.sprites[hqId]
  if sp then
    local w, h = sp.img:getDimensions()
    local k = size / w
    lg.setColor(1, 1, 1)
    lg.draw(sp.img, x - w * k / 2, y - h * k / 2, 0, k, k)
    lg.setBlendMode("add")
    lg.setColor(0.6, 0.55, 0.5)
    lg.draw(sp.glow, x - w * k / 2, y - h * k / 2, 0, k, k)
    lg.setBlendMode("alpha")
    return
  end
  S.previewStruct = S.previewStruct or {}
  local ps = S.previewStruct[hqId] or S.new("hq", 1, 1, { hqId = hqId })
  S.previewStruct[hqId] = ps
  local k = size / 330
  lg.push()
  lg.translate(x, y - 80 * k)
  lg.scale(k)
  S.draw(ps, t)
  G.flushGlows()
  G.lights = {}
  lg.pop()
end

-- Burning barrel: the main warm light of the yards.
function S.drawFire(f, t)
  local x, y = f[1], f[2]
  G.cylinder(x, y, 0.17, 0, 0.42, C.rustDark)
  local sx, sy = P(x, y, 0.42)
  local flick = 0.8 + 0.2 * math.sin(t * 13 + x * 3) * math.sin(t * 7.7 + y)
  for i = 0, 4 do
    local ox = (i - 2) * 2.4
    local hgt = (9 + 5 * math.sin(t * 9 + i * 1.7 + x)) * flick
    lg.setColor(1, 0.45 + i % 2 * 0.25, 0.1, 0.9)
    lg.polygon("fill", sx + ox - 2.5, sy, sx + ox + 2.5, sy, sx + ox + math.sin(t * 6 + i) * 1.5, sy - hgt)
  end
  G.glow(sx, sy - 4, 16, { 1, 0.85, 0.5 }, 0.9 * flick)
  G.glow(sx, sy - 4, 50, { 1, 0.5, 0.15 }, 0.35 * flick)
  G.lightAt(sx, sy + 14, 230 * flick, { 1, 0.7, 0.4 }, 1.15, 160 * flick)
end

-- The specialization foundations, from the design bible. Each belongs to a
-- group, whose members work there; the player builds them during the day
-- (see Game:placeBuilding). Leadership has none and works at the HQ.
local function foundation(group, name, sprite, desc, extra)
  local d = { w = 3, h = 3, hp = 500, blocking = true, barZ = 2.4, group = group, name = name, sprite = sprite,
    desc = desc, repairable = true }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end

S.DEFS = {
  hq = { w = 4, h = 4, hp = 1500, blocking = true, barZ = 4.2 },

  garden = foundation("Agriculture", "Salvage Garden", "salvage_garden",
    "Agriculture farms here. Traditional low-tech crop growing.",
    { w = 4, h = 4, hp = 1, blocking = false, flat = true, repairable = false }),
  hydroponics = foundation("Agriculture", "Hydroponic Container", "hydroponic_shipping_containers",
    "Agriculture farms here. Compact technical farming in shipping containers.", { barZ = 2.2 }),

  barracks = foundation("Combat", "School Bus Barracks", "school_bus_barracks",
    "Combat drills here. A repurposed school bus for housing and training combat personnel.", { hp = 650, barZ = 2.6 }),
  armory = foundation("Combat", "Box Truck Armory", "box_truck_armory",
    "Stores rifles and pistols and issues them to mobilizing groups; without it they collect gear at the HQ.",
    { w = 4, h = 3, hp = 700 }),
  trailer = foundation("Combat", "Trailer Blockade", "trailer_blockade",
    "Combat drills here. Trailers welded into a fortified line that takes a beating.", { hp = 1000, barZ = 1.8 }),

  workshop = foundation("Engineering", "Tow-Truck Workshop", "tow_truck_workshop",
    "Engineering works here, patching walls and buildings for free.", { hp = 550, barZ = 2.2 }),
  excavator = foundation("Engineering", "Excavator Graveyard", "excavator_graveyard",
    "Engineering works here. Dead earthmovers fused into a construction complex."),
  truckstop = foundation("Engineering", "Truck Stop", "truck_stop",
    "Engineering works here. A roadside garage and fuelling area for utilities."),

  lookout = foundation("Scouting", "Water Park Lifeguard Tower", "water_park_lifeguard_tower",
    "Scouting keeps watch here. An elevated station; scouts slide down to respond.", { barZ = 3.2 }),
  billboard = foundation("Scouting", "Billboard Observation Nest", "billboard_observation_nest",
    "Scouting keeps watch here from a raised billboard.", { barZ = 3.4 }),
  stormvan = foundation("Scouting", "Storm-Chaser Van", "storm_chaser_van",
    "Scouting works here. A sensor van for watching the approaches.", { barZ = 1.8 }),

  salvage = foundation("Scavenging", "Garbage Compactor Truck", "garbage_compactor_truck",
    "Scavenging sorts scrap here, and it slowly yields more.", { hp = 550, barZ = 1.8 }),
  carousel = foundation("Scavenging", "Airport Baggage Carousel", "airport_baggage_carousel",
    "Scavenging sorts scrap here on a recovered luggage conveyor."),
  lockers = foundation("Scavenging", "Storage Locker Labyrinth", "storage_lock_labyrinth",
    "Scavenging sorts scrap here, cataloguing recovered goods."),

  icecream = foundation("Medicine", "Ice Cream Truck Pharmacy", "ice_cream_truck_pharmacy",
    "Medicine works here; the wounded heal faster.", { barZ = 2.0 }),
  laundromat = foundation("Medicine", "Laundromat Sterilization Ward", "laundromat_sterilization_ward",
    "Medicine works here. Washers, sinks and partitions for infection control; the wounded heal faster."),
  bloodmobile = foundation("Medicine", "Bloodmobile Clinic", "bloodmobile_clinic",
    "Medicine works here. A donation bus turned triage ward; the wounded heal faster.", { barZ = 2.0 }),

  arcade = foundation("Research", "Derelict Arcade Lab", "derelict_arcade_lab",
    "Research works here. Rewired cabinets and salvaged electronics; everyone learns faster.", { hp = 450 }),
  aquarium = foundation("Research", "Aquarium Containment Lab", "aquarium_containment_lab",
    "Research works here, studying the infected in old exhibit tanks; everyone learns faster."),
  bowling = foundation("Research", "Bowling Alley Test Facility", "bowling_alley_test_facility",
    "Research works here, testing weapons down the lanes; everyone learns faster."),

  forge = foundation("Fabrication", "Pizza Parlor Forge", "pizza_parlor_forge",
    "Fabrication works here, turning scrap into ammunition in the old pizza ovens.", { hp = 550, barZ = 2.2 }),
  gunsmith = foundation("Fabrication", "Pawnshop Gunsmith", "pawnshop_gunsmith",
    "Fabrication works here, turning scrap into ammunition at the reloading benches."),
  cannery = foundation("Fabrication", "Soda Cannery Factory", "soda_cannery_factory",
    "Fabrication works here, turning scrap into ammunition on the old canning line."),

  vending = foundation("Logistics", "Vending Machine Supply Wall", "vending_machine_supply_wall",
    "Logistics works here, rationing supplies so the settlement eats less."),
  garage = foundation("Logistics", "Parking Garage Stockpile", "parking_garage_stockpile",
    "Logistics works here, rationing supplies so the settlement eats less.", { barZ = 3.0 }),
  vault = foundation("Logistics", "Drive-Thru Bank Vault", "drive_thru_bank_vault",
    "Logistics works here, rationing supplies so the settlement eats less.", { hp = 800 }),

  -- a town building: size, sprite and solidity are set per instance
  town = { w = 2, h = 2, hp = 1, blocking = true },
  wreck = { w = 1, h = 1, hp = 1, blocking = true },
  fence = { w = 1, h = 1, hp = 220, blocking = true, barZ = 1.1, name = "Salvage Fence", desc = "Zombies must smash through." },
  gate = {
    w = 1, h = 1, hp = 320, blocking = true, gate = true, barZ = 1.3, name = "Gate",
    desc = "Survivors pass through; zombies have to break it.",
  },
  tower = { w = 1, h = 1, hp = 380, blocking = true, barZ = 3.0, name = "Watchtower", desc = "Lights the perimeter." },
  crates = { w = 1, h = 1, hp = 120, blocking = true, barZ = 1.0, name = "Supply Crates", desc = "Salvaged stock." },
}

-- Which foundations each group can build, in the bible's order.
S.FOUNDATIONS = {}
for _, group in ipairs(D.GROUPS) do S.FOUNDATIONS[group] = {} end
for _, kind in ipairs({ "garden", "hydroponics", "barracks", "armory", "trailer", "workshop", "excavator",
                        "truckstop", "lookout", "billboard", "stormvan", "salvage", "carousel", "lockers",
                        "icecream", "laundromat", "bloodmobile", "arcade", "aquarium", "bowling", "forge",
                        "gunsmith", "cannery", "vending", "garage", "vault" }) do
  local list = S.FOUNDATIONS[S.DEFS[kind].group]
  list[#list + 1] = kind
end
S.BUILD_COST = 40 -- scrap

function S.new(kind, x1, y1, opts)
  local def = S.DEFS[kind]
  local s = {
    kind = kind, def = def, x1 = x1, y1 = y1, w = def.w, h = def.h,
    hp = def.hp, maxhp = def.hp, blocking = def.blocking, gate = def.gate, flat = def.flat,
    name = def.name, desc = def.desc, seed = love.math.random(1, 9999),
    group = def.group, repairable = def.repairable,
  }
  if opts then
    for k, v in pairs(opts) do s[k] = v end
  end
  -- a flipped building is the painting mirrored, which turns its footprint
  if s.flip then s.w, s.h = def.h, def.w end
  s.sprite = s.sprite or def.sprite or (kind == "hq" and s.hqId) or nil
  s.wx1, s.wy1 = x1 - 1, y1 - 1
  s.wx2, s.wy2 = s.wx1 + s.w, s.wy1 + s.h
  s.cx, s.cy = (s.wx1 + s.wx2) / 2, (s.wy1 + s.wy2) / 2
  s.depth = s.cx + s.cy
  return s
end

local function hash(a, b, c)
  local n = math.sin(a * 12.9898 + b * 78.233 + (c or 0) * 37.719) * 43758.5453
  return n - math.floor(n)
end

local function crates(x, y, n, seed)
  for i = 0, n - 1 do
    local ox = (hash(seed, i, 1) - 0.5) * 0.25
    local col = hash(seed, i, 2) > 0.5 and C.olive or { 0.36, 0.30, 0.20 }
    G.box(x + ox, y + i * 0.02, x + ox + 0.42, y + 0.42, i * 0.36, i * 0.36 + 0.34, col)
  end
end

local function antenna(x, y, z0, z1, t)
  local bx, by = P(x, y, z0)
  local tx, ty = P(x, y, z1)
  lg.setColor(0.12, 0.11, 0.1)
  lg.setLineWidth(1.5)
  lg.line(bx, by, tx, ty)
  lg.line(bx - 3, by - (by - ty) * 0.35, bx + 3, by - (by - ty) * 0.35)
  if math.sin(t * 3 + x) > -0.2 then
    lg.setColor(1, 0.25, 0.2)
    lg.circle("fill", tx, ty, 1.8)
    G.glow(tx, ty, 12, { 1, 0.2, 0.15 }, 0.8)
  end
end

----------------------------------------------------------------------------
-- Headquarters variants

local function drawFarmhouse(s, t)
  local x1, y1, x2, y2 = s.wx1, s.wy1, s.wx2, s.wy2
  G.flat(x1 + 0.05, y1 + 0.05, x2 - 0.05, y2 - 0.05, C.yard)

  -- house, front left
  local hx1, hy1, hx2, hy2 = x1 + 0.25, y1 + 1.35, x1 + 2.25, y2 - 0.75
  G.box(hx1, hy1, hx2, hy2, 0, 1.15, C.wood)
  G.windowY(hy2, hx1 + 0.3, hx1 + 0.7, 0.4, 0.85, true)
  G.windowY(hy2, hx1 + 1.25, hx1 + 1.65, 0.4, 0.85, true)
  G.windowX(hx2, hy1 + 0.4, hy1 + 0.8, 0.4, 0.85, hash(s.seed, 1) > 0.3)
  G.roofX(hx1 - 0.12, hy1 - 0.12, hx2 + 0.12, hy2 + 0.12, 1.15, 0.75, { 0.42, 0.31, 0.26 })
  -- porch
  G.box(hx1, hy2, hx2, hy2 + 0.55, 0, 0.1, C.woodDark)
  for i = 0, 3 do
    local px = hx1 + 0.1 + i * 0.6
    G.box(px, hy2 + 0.45, px + 0.06, hy2 + 0.51, 0.1, 0.8, C.woodDark, true)
  end
  G.box(hx1, hy2 + 0.02, hx2, hy2 + 0.58, 0.8, 0.86, C.rust)

  -- water tank between the buildings
  G.cylinder(x1 + 2.35, y1 + 0.75, 0.35, 0.0, 1.9, C.metal)

  -- barn, back right
  local bx1, by1, bx2, by2 = x1 + 2.45, y1 + 0.2, x2 - 0.15, y1 + 2.65
  local barn = { 0.47, 0.15, 0.11 }
  G.box(bx1, by1, bx2, by2, 0, 1.45, barn)
  G.quadX(bx2, by1 + 0.7, by1 + 1.6, 0, 1.05, { 0.12, 0.05, 0.04 })
  G.quadX(bx2, by1 + 0.78, by1 + 1.52, 0.02, 0.95, { 1, 0.72, 0.38 }, 0.55)
  local doorX, doorY = P(bx2, by1 + 1.15, 0.5)
  G.glow(doorX, doorY, 40, C.amber, 0.45)
  G.bannerY(by2, bx1 + 0.35, bx1 + 1.05, 0.25, 1.25)
  G.roofY(bx1 - 0.1, by1 - 0.1, bx2 + 0.1, by2 + 0.1, 1.45, 0.85, C.rust)

  crates(x2 - 0.65, y2 - 0.7, 2, s.seed)
  G.box(x1 + 2.6, y2 - 0.8, x1 + 3.1, y2 - 0.45, 0, 0.3, { 0.62, 0.52, 0.28 }) -- hay bale
  G.lampPost(x1 + 0.1, y2 - 0.1, 2.0)
  G.lampPost(x2 - 0.1, y1 + 2.9, 2.2)
end

local function drawWaterTower(s, t)
  local x1, y1, x2, y2 = s.wx1, s.wy1, s.wx2, s.wy2
  local cx, cy = s.cx, s.cy
  G.flat(x1 + 0.05, y1 + 0.05, x2 - 0.05, y2 - 0.05, C.yard)

  local legTop = 2.7
  local function leg(ax, ay)
    local bx, by = P(ax, ay, 0)
    local tx, ty = P(cx + (ax - cx) * 0.75, cy + (ay - cy) * 0.75, legTop)
    lg.setColor(0.25, 0.15, 0.09)
    lg.setLineWidth(4)
    lg.line(bx, by, tx, ty)
  end
  local function brace(ax, ay, bx, by, z)
    local f = 1 - 0.25 * z / legTop
    local p1x, p1y = P(cx + (ax - cx) * f, cy + (ay - cy) * f, z)
    local p2x, p2y = P(cx + (bx - cx) * f, cy + (by - cy) * f, z)
    lg.setColor(0.22, 0.13, 0.08)
    lg.setLineWidth(2)
    lg.line(p1x, p1y, p2x, p2y)
  end
  local r = 1.55
  leg(cx - r, cy - r)
  leg(cx + r, cy - r)
  leg(cx - r, cy + r)
  brace(cx - r, cy - r, cx + r, cy - r, 1.4)
  brace(cx - r, cy - r, cx - r, cy + r, 1.4)

  -- command shack under the tank
  G.box(cx - 1.05, cy - 0.95, cx + 1.05, cy + 1.05, 0, 0.95, C.metal)
  G.windowY(cy + 1.05, cx - 0.75, cx - 0.2, 0.3, 0.7, true)
  G.quadY(cy + 1.05, cx + 0.15, cx + 0.6, 0, 0.8, { 0.1, 0.08, 0.06 })
  G.windowX(cx + 1.05, cy - 0.6, cy - 0.1, 0.3, 0.7, true)
  G.box(cx - 1.15, cy - 1.05, cx + 1.15, cy + 1.15, 0.95, 1.02, C.rustDark)

  leg(cx + r, cy + r)
  brace(cx - r, cy + r, cx + r, cy + r, 1.4)
  brace(cx + r, cy - r, cx + r, cy + r, 1.4)

  -- the tank
  G.cylinder(cx, cy, 1.5, legTop, 4.0, C.rust)
  local sx, sy = P(cx, cy, 0)
  local _, bTop = P(cx, cy, 3.75)
  local _, bBot = P(cx, cy, 2.95)
  local fy = 22.6 * 1.5
  lg.setColor(C.banner)
  lg.rectangle("fill", sx - 13, bTop + fy * 0.9, 26, bBot - bTop)
  G.emblem(sx, bTop + fy * 0.9 + (bBot - bTop) * 0.45, 2.1)
  local _, ry = P(cx, cy, 4.05)
  lg.setColor(0.15, 0.1, 0.07)
  lg.setLineWidth(1.5)
  lg.ellipse("line", sx, ry, 1.62 * 45.25, 1.62 * 22.63)
  antenna(cx + 0.6, cy - 0.6, 4.0, 5.2, t)

  crates(x1 + 0.15, y2 - 0.6, 2, s.seed)
  G.lampPost(x1 + 0.1, y2 - 0.1, 2.1)
  G.lampPost(x2 - 0.1, y1 + 0.1, 2.1)
end

----------------------------------------------------------------------------

local function drawArmory(s, t)
  local x1, y1, x2, y2 = s.wx1, s.wy1, s.wx2, s.wy2
  -- wheels
  for _, wx in ipairs({ x1 + 0.55, x1 + 1.75, x2 - 0.45 }) do
    local sx, sy = P(wx, y2 - 0.12, 0.18)
    lg.setColor(0.06, 0.06, 0.06)
    lg.ellipse("fill", sx, sy, 7, 6)
  end
  -- cargo box
  local fade = { 0.62, 0.60, 0.54 }
  G.box(x1 + 0.1, y1 + 0.2, x2 - 0.85, y2 - 0.12, 0.3, 1.5, fade)
  G.quadY(y2 - 0.12, x1 + 0.1, x2 - 0.85, 0.3, 0.45, { 0.55, 0.15, 0.1 })
  G.bannerY(y2 - 0.12, x1 + 0.75, x1 + 1.35, 0.55, 1.4)
  G.quadY(y2 - 0.12, x1 + 1.6, x1 + 1.9, 0.5, 1.3, { 0.42, 0.24, 0.14 }) -- rust streak
  -- cab
  G.box(x2 - 0.85, y1 + 0.3, x2 - 0.08, y2 - 0.2, 0.3, 1.05, { 0.58, 0.19, 0.14 })
  G.quadX(x2 - 0.08, y1 + 0.42, y2 - 0.32, 0.65, 0.98, { 0.12, 0.14, 0.15 })
  G.quadY(y2 - 0.2, x2 - 0.7, x2 - 0.3, 0.6, 0.95, { 0.12, 0.14, 0.15 })
  -- headlight
  local hx, hy = P(x2 - 0.08, y2 - 0.32, 0.45)
  lg.setColor(1, 0.85, 0.55)
  lg.circle("fill", hx, hy, 2)
  G.glow(hx, hy, 26, C.amber, 0.5)
  -- tarp awning over the issue counter
  local ax, ay = P(x1 + 0.1, y2 - 0.12, 1.35)
  local bx, by = P(x2 - 0.9, y2 - 0.12, 1.35)
  local cx, cy = P(x2 - 0.9, y2 + 0.75, 0.95)
  local dx, dy = P(x1 + 0.1, y2 + 0.75, 0.95)
  G.setc(C.tarp, 0.95)
  lg.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
  lg.setColor(C.outline)
  lg.polygon("line", ax, ay, bx, by, cx, cy, dx, dy)
  for _, px in ipairs({ x1 + 0.15, x2 - 0.95 }) do
    local p1x, p1y = P(px, y2 + 0.72, 0)
    local p2x, p2y = P(px, y2 + 0.72, 0.95)
    lg.setColor(0.12, 0.1, 0.08)
    lg.setLineWidth(1.5)
    lg.line(p1x, p1y, p2x, p2y)
  end
  local lx, ly = P(x1 + 1.0, y2 + 0.3, 0.9)
  lg.setColor(1, 0.8, 0.5)
  lg.circle("fill", lx, ly, 1.8)
  G.glow(lx, ly, 34, C.amber, 0.55)
  G.light(x1 + 1.0, y2 + 0.3, 0.9, 0.7)

  crates(x2 - 0.5, y1 - 0.05, 2, s.seed)
  G.lampPost(x1 - 0.2, y2 + 0.9, 2.0)
end

local function drawGarden(s, t)
  local x1, y1, x2, y2 = s.wx1, s.wy1, s.wx2, s.wy2
  G.flat(x1 + 0.08, y1 + 0.08, x2 - 0.08, y2 - 0.08, { 0.19, 0.12, 0.075 })
  -- crop rows
  for r = 0, 4 do
    local y = y1 + 0.38 + r * 0.56
    local ax, ay = P(x1 + 0.2, y, 0)
    local bx, by = P(x2 - 0.2, y, 0)
    lg.setColor(0.13, 0.08, 0.05)
    lg.setLineWidth(3)
    lg.line(ax, ay + 1, bx, by + 1)
    local x = x1 + 0.3
    local k = 0
    while x < x2 - 0.25 do
      local sx, sy = P(x, y, 0)
      local h = hash(s.seed, r, k)
      local sway = math.sin(t * 1.5 + x * 2 + r) * 0.6
      lg.setColor(C.crop[1] * (0.75 + h * 0.4), C.crop[2] * (0.75 + h * 0.4), C.crop[3])
      lg.polygon("fill", sx - 3, sy, sx + 3, sy, sx + sway, sy - 6 - h * 4)
      lg.setColor(0.45, 0.66, 0.28)
      lg.circle("fill", sx + sway * 0.6, sy - 4 - h * 3, 1.6)
      x = x + 0.34
      k = k + 1
    end
  end
  -- low salvage edging along the front
  for i = 0, 5 do
    local px = x1 + 0.15 + i * 0.54
    local ax, ay = P(px, y2 - 0.06, 0)
    local bx, by = P(px, y2 - 0.06, 0.35)
    lg.setColor(0.2, 0.14, 0.09)
    lg.setLineWidth(2)
    lg.line(ax, ay, bx, by)
  end
  G.cylinder(x2 - 0.3, y1 + 0.3, 0.2, 0, 0.5, { 0.22, 0.34, 0.45 })
  G.lampPost(x1 + 0.1, y1 + 0.1, 1.8)
end

local FENCE_COLORS = { C.rust, C.metal, C.wood, { 0.40, 0.33, 0.28 } }

local function drawFence(s, t)
  local x, y = s.wx1, s.wy1
  local frac = s.hp / s.maxhp
  local col = FENCE_COLORS[s.seed % #FENCE_COLORS + 1]
  local h = 0.4 + 0.5 * frac
  if s.gate then
    col = C.metalDark
    h = 0.55 + 0.5 * frac
  end
  if s.dir == "x" then
    G.box(x - 0.04, y + 0.37, x + 0.08, y + 0.63, 0, h + 0.15, C.metalDark)
    G.box(x, y + 0.42, x + 1, y + 0.58, 0, h, col)
    if s.gate then
      G.quadY(y + 0.58, x + 0.05, x + 0.95, h - 0.2, h - 0.08, { 0.75, 0.6, 0.15 })
      for i = 1, 4 do
        local ax, ay = P(x + i * 0.2, y + 0.58, 0.05)
        local bx, by = P(x + i * 0.2, y + 0.58, h - 0.22)
        lg.setColor(0.1, 0.1, 0.1)
        lg.line(ax, ay, bx, by)
      end
    elseif frac < 0.5 then
      G.quadY(y + 0.58, x + 0.3, x + 0.55, h * 0.4, h, { 0.05, 0.04, 0.03 })
    end
  else
    G.box(x + 0.37, y - 0.04, x + 0.63, y + 0.08, 0, h + 0.15, C.metalDark)
    G.box(x + 0.42, y, x + 0.58, y + 1, 0, h, col)
    if s.gate then
      G.quadX(x + 0.58, y + 0.05, y + 0.95, h - 0.2, h - 0.08, { 0.75, 0.6, 0.15 }, 0.7)
      for i = 1, 4 do
        local ax, ay = P(x + 0.58, y + i * 0.2, 0.05)
        local bx, by = P(x + 0.58, y + i * 0.2, h - 0.22)
        lg.setColor(0.1, 0.1, 0.1)
        lg.line(ax, ay, bx, by)
      end
    elseif frac < 0.5 then
      G.quadX(x + 0.58, y + 0.3, y + 0.55, h * 0.4, h, { 0.05, 0.04, 0.03 })
    end
  end
end

local function drawTower(s, t)
  local x, y = s.wx1, s.wy1
  local top = 2.0
  local function leg(lx, ly)
    local ax, ay = P(lx, ly, 0)
    local bx, by = P(lx, ly, top)
    lg.setColor(0.24, 0.17, 0.1)
    lg.setLineWidth(3)
    lg.line(ax, ay, bx, by)
  end
  leg(x + 0.15, y + 0.15)
  leg(x + 0.85, y + 0.15)
  leg(x + 0.15, y + 0.85)
  leg(x + 0.85, y + 0.85)
  local a1x, a1y = P(x + 0.15, y + 0.85, 0.2)
  local a2x, a2y = P(x + 0.85, y + 0.85, 1.6)
  lg.setLineWidth(1.5)
  lg.line(a1x, a1y, a2x, a2y)
  G.box(x - 0.1, y - 0.1, x + 1.1, y + 1.1, top, top + 0.14, C.wood)
  G.box(x + 0.05, y + 0.05, x + 0.95, y + 0.95, top + 0.14, top + 0.72, C.metal)
  G.windowY(y + 0.95, x + 0.2, x + 0.8, top + 0.38, top + 0.55, true)
  G.windowX(x + 0.95, y + 0.2, y + 0.8, top + 0.38, top + 0.55, true)
  G.box(x - 0.15, y - 0.15, x + 1.15, y + 1.15, top + 0.72, top + 0.82, C.rustDark)
  G.light(x + 0.5, y + 0.5, top + 1.0, 1.3)
  local lx, ly = P(x + 0.5, y + 0.5, top + 1.0)
  lg.setColor(1, 0.85, 0.55)
  lg.rectangle("fill", lx - 4, ly - 3, 8, 5)
end

local function drawCrates(s, t)
  crates(s.wx1 + 0.25, s.wy1 + 0.25, 2, s.seed)
  G.box(s.wx1 + 0.55, s.wy1 + 0.5, s.wx1 + 0.95, s.wy1 + 0.92, 0, 0.3, { 0.36, 0.30, 0.20 })
end

local HQ_DRAW = { farmhouse = drawFarmhouse, watertower = drawWaterTower }

function S.draw(s, t)
  local k = s.kind
  local tint = 0.55 + 0.45 * (s.hp / s.maxhp)
  if S.spriteFor(s) then drawSpriteBody(s)
  elseif k == "hq" then (HQ_DRAW[s.hqId] or drawWaterTower)(s, t)
  elseif k == "armory" then drawArmory(s, t)
  elseif k == "garden" then drawGarden(s, t)
  elseif k == "fence" or k == "gate" then
    if not drawWall(s) then drawFence(s, t) end
  elseif k == "tower" then
    if not S.drawPoint("watchtower", s.cx, s.cy, tint) then drawTower(s, t) end
  elseif k == "crates" then
    if not S.drawPoint("crates", s.cx, s.cy, tint) then drawCrates(s, t) end
  else
    G.box(s.wx1 + 0.1, s.wy1 + 0.1, s.wx2 - 0.1, s.wy2 - 0.1, 0, 1.2, C.metal)
  end
end

-- Broken pieces left on the ground when a structure falls.
function S.drawRubble(r)
  for i = 1, #r.bits do
    local b = r.bits[i]
    local sx, sy = P(b[1], b[2], 0)
    lg.setColor(b[3], b[3] * 0.8, b[3] * 0.65, r.alpha or 1)
    lg.polygon("fill", sx - b[4], sy, sx, sy - b[4] * 0.6, sx + b[4], sy, sx, sy + b[4] * 0.5)
  end
end

return S
