-- Painted survivor and zombie sprites (assets/units, cut by
-- tools/process_units.lua). Portraits are one standing pose facing
-- screen-right; facing left mirrors it, and walking, attacking and falling
-- are done by bobbing, leaning and tipping the whole figure about its feet.
-- Walk sheets add real views and stride frames on top of that.
local lg = love.graphics

local Units = {}

-- Which portrait set dresses each group.
Units.GROUP_SET = {
  Combat = "combat",
  Engineering = "worker",
  Scouting = "leader",
  Scavenging = "worker",
  Medicine = "leader",
  Research = "leader",
  Agriculture = "farmer",
  Fabrication = "worker",
  Logistics = "farmer",
  Leadership = "leader",
}

-- Which zombie portraits play each kind.
Units.ZOMBIE_SET = {
  walker = { 1, 4, 6, 7, 8, 9, 10 },
  runner = { 2, 5 },
  brute = { 3 },
}

-- Groups with a walk sheet (front, side, three-quarter and back views, two
-- stride frames each), cut by `--process-units --sheet <name>`. These take
-- the place of the group's portraits.
Units.WALK_SET = {
  Combat = "soldier",
}

-- On-screen height in pixels at zoom 1.
Units.SURVIVOR_H = 48
Units.ZOMBIE_H = { walker = 46, runner = 44, brute = 64 }

local info = {}
local images = {}

function Units.load()
  local ok, index = pcall(love.filesystem.load, "assets/units/index.lua")
  if not ok or not index then return end
  info = index() or {}
  for id in pairs(info) do
    local path = "assets/units/" .. id .. ".png"
    if love.filesystem.getInfo(path) then
      local img = lg.newImage(path, { mipmaps = true })
      img:setFilter("linear", "linear")
      img:setMipmapFilter("linear", -0.5)
      images[id] = img
    end
  end
end

function Units.get(id)
  local img = images[id]
  if img then return img, info[id] end
end

-- Count of portraits in a set, e.g. Units.count("combat") == 10.
function Units.count(set)
  local n = 0
  while images[set .. (n + 1)] do n = n + 1 end
  return n
end

-- Which view of a walk sheet shows a figure heading along world (dx, dy),
-- and whether to mirror it. The sheet's side views face screen-right.
function Units.view(dx, dy)
  local sx, sy = (dx - dy) * 2, dx + dy -- screen direction
  local face = sx < 0 and -1 or 1
  local ax = math.abs(sx)
  if sy > 0 and ax < sy * 0.5 then return "front", 1 end
  if sy < 0 and ax < -sy * 0.5 then return "back", 1 end
  if sy > 0 then return "q", face end
  return "side", face
end

-- The sprite id for a survivor in their current group. Groups with a walk
-- sheet pick the frame for the survivor's heading and stride.
function Units.survivorId(s)
  local walk = Units.WALK_SET[s.group]
  if walk and images[walk .. "_front1"] then
    local frame = s.moving and math.floor(s.anim * 10 / math.pi) % 2 + 1 or 1
    return walk .. "_" .. (s.view or "q") .. frame, true
  end
  local set = Units.GROUP_SET[s.group]
  local n = set and Units.count(set) or 0
  if n == 0 then return nil end
  return set .. ((s.look - 1) % n + 1)
end

function Units.zombieId(z)
  local list = Units.ZOMBIE_SET[z.kind] or Units.ZOMBIE_SET.walker
  local id = "zombie" .. list[(z.look - 1) % #list + 1]
  if images[id] then return id end
end

-- Draw a figure standing at screen point (sx, sy).
--   face   1 = facing right, -1 = mirrored
--   height on-screen height in pixels
--   lean   tilt in radians about the feet (positive leans forward)
--   lift   pixels the figure is raised (walking bob)
--   down   0..1, how far the figure has toppled onto its side
--   glow   how strongly the figure shows through the dark (see flushGlow)
function Units.draw(id, sx, sy, face, height, lean, lift, down, tint, glow)
  local img, d = images[id], info[id]
  if not img then return false end
  local k = height / (d.u or d.h)
  local r = face * (lean or 0) + face * (down or 0) * 1.45
  if tint then lg.setColor(tint) else lg.setColor(1, 1, 1) end
  lg.draw(img, sx, sy - (lift or 0), r, face * k, k, d.ax, d.ay)
  if glow then
    local q = Units.glowQueue
    q[#q + 1] = { img, sx, sy - (lift or 0), r, face * k, k, d.ax, d.ay, glow }
  end
  return true
end

-- The painted figures are dark, and at night the light map would swallow
-- them. A faint copy of each is added back on top after the darkness, so
-- units stay readable as silhouettes, scaled by how dark it is.
Units.glowQueue = {}

function Units.flushGlow(strength)
  local q = Units.glowQueue
  if strength > 0.01 then
    lg.setBlendMode("add")
    for _, e in ipairs(q) do
      local a = e[9] * strength
      lg.setColor(a, a * 0.95, a * 0.9)
      lg.draw(e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8])
    end
    lg.setBlendMode("alpha")
  end
  Units.glowQueue = {}
end

-- Where the head of a drawn figure sits, for glowing eyes.
function Units.headAt(id, sx, sy, face, height, lift)
  local d = info[id]
  if not d then return sx, sy - height end
  local k = height / (d.u or d.h)
  return sx + face * (d.hx - d.ax) * k, sy - (lift or 0) - (d.ay - d.hy) * k, k
end

-- A brief white flash over the figure when it is hit.
function Units.flash(id, sx, sy, face, height, lean, lift, a)
  local img, d = images[id], info[id]
  if not img or a <= 0 then return end
  local k = height / (d.u or d.h)
  lg.setBlendMode("add")
  lg.setColor(a, a * 0.85, a * 0.8)
  lg.draw(img, sx, sy - (lift or 0), face * (lean or 0), face * k, k, d.ax, d.ay)
  lg.setBlendMode("alpha")
end

return Units
