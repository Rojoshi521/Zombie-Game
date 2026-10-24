local U = require("src.util")
local D = require("src.data")
local Iso = require("src.iso")
local G = require("src.gfx")
local Map = require("src.map")
local S = require("src.structures")
local Survivor = require("src.survivor")
local Zombie = require("src.zombie")
local Director = require("src.director")

local lg = love.graphics
local P = Iso.toScreen

local Game = {}
Game.__index = Game

local Town = require("src.town")
local Units = require("src.units")

local MAP_W, MAP_H = 88, 88
-- The settlement sits in the middle of the town. Layout coordinates below
-- are written relative to the base and shifted by B.
local B = 20
local F_MIN, F_MAX = 14 + B, 35 + B -- fence ring, in cells
local FOOD_PER_SURVIVOR = 0.018 -- per second
local REBUILD_COST = 8
local HP_PER_SCRAP = 25
Game.F_MIN, Game.F_MAX, Game.B = F_MIN, F_MAX, B
Game.MAP_W, Game.MAP_H = MAP_W, MAP_H

function Game.new(hqDef)
  local g = setmetatable({}, Game)
  g.hqDef = hqDef
  g.map = Map.new(MAP_W, MAP_H)
  g.structures, g.lamps = {}, {}
  g.survivors, g.zombies = {}, {}
  g.effects, g.decals, g.ruins = {}, {}, {}
  g.messages = {}
  g.selection = {}
  g.sites = {}
  g.res = { food = 40, ammo = 160, scrap = 40 }
  g.stock = { rifle = 4, pistol = 4 }
  g.time, g.speed, g.paused = 0, 1, false
  g.stats = { kills = 0, lost = 0 }
  g.foodRate = 0
  g.foodMult = hqDef.id == "farmhouse" and 1.3 or 1
  g.healRate = 1
  g.bleedOut = 25
  g.alertMult = hqDef.id == "watertower" and 2 or 1
  g.scrapMult = hqDef.id == "ferriswheel" and 1.5 or 1
  g.luck = hqDef.id == "casino" and 0.35 or 0
  g.learnMult = hqDef.id == "broadcast" and 1.4 or 1
  g.drawList = {}
  g.units = {}

  g:buildSettlement()
  g.groups = {
    Combat = { rallyX = B + 27.6, rallyY = B + 27.6 },
    Scouting = { rallyX = B + 24.5, rallyY = B + 20.2 },
    Scavenging = { rallyX = B + 21.0, rallyY = B + 31.0 },
    Agriculture = { rallyX = B + 20.6, rallyY = B + 22.0 },
  }
  for name, grp in pairs(g.groups) do
    grp.loadout = D.GROUP_LOADOUT[name]
    grp.mobilized = false
  end
  for _, c in ipairs({ { "Combat", 3 }, { "Scouting", 2 }, { "Scavenging", 2 }, { "Agriculture", 3 } }) do
    for _ = 1, c[2] do g:addSurvivor(Survivor.generate(c[1])) end
  end

  g.director = Director.new(g)
  g:initFog()
  Town.generate(g, MAP_W, MAP_H, { min = F_MIN - 3, max = F_MAX + 3, fmin = F_MIN, fmax = F_MAX })
  g.camera = Iso.newCamera(P(g.hq.cx + 1, g.hq.cy + 1))
  g:renderGround()
  g.map:computeFlow(g.hq)
  g:updateFog()
  g:message("Welcome to " .. hqDef.name .. ". Night falls in 3 minutes: explore the town while it is light.")
  g:message("The town outside is unexplored. Send scouts to look, and scavengers to search buildings.")
  g:message("Press F1 for controls.")
  return g
end

----------------------------------------------------------------------------
-- Settlement layout

function Game:addStructure(kind, x1, y1, opts)
  local s = S.new(kind, x1, y1, opts)
  self.structures[#self.structures + 1] = s
  self.map:place(s)
  return s
end

function Game:buildSettlement()
  self.hq = self:addStructure("hq", B + 23, B + 23, { hqId = self.hqDef.id, name = self.hqDef.name,
    desc = "Headquarters. " .. self.hqDef.text .. " If it falls, the settlement is lost." })
  self.garden = self:addStructure("garden", B + 16, B + 26)
  self.armory = self:addStructure("armory", B + 28, B + 17)
  self.barracks = self:addStructure("barracks", B + 29, B + 29, { repairable = true })
  self.hydroponics = self:addStructure("hydroponics", B + 17, B + 17, { repairable = true })
  self.lookout = self:addStructure("lookout", B + 23, B + 16, { repairable = true })
  self.salvageYard = self:addStructure("salvage", B + 16, B + 31, { repairable = true })

  local towers = {
    [F_MIN .. "," .. F_MIN] = true, [F_MAX .. "," .. F_MIN] = true,
    [F_MIN .. "," .. F_MAX] = true, [F_MAX .. "," .. F_MAX] = true,
    [(B + 22) .. "," .. F_MAX] = true, [(B + 26) .. "," .. F_MAX] = true,
    [F_MAX .. "," .. (B + 22)] = true, [F_MAX .. "," .. (B + 26)] = true,
  }
  -- gates are three tiles wide; the value is the slice of the gate painting
  local gates = {}
  for k = 0, 2 do
    gates[(B + 23 + k) .. "," .. F_MAX] = k
    gates[F_MAX .. "," .. (B + 23 + k)] = k
  end
  for cy = F_MIN, F_MAX do
    for cx = F_MIN, F_MAX do
      if cx == F_MIN or cx == F_MAX or cy == F_MIN or cy == F_MAX then
        local key = cx .. "," .. cy
        local dir = (cx == F_MIN or cx == F_MAX) and "y" or "x"
        if towers[key] then
          self:addStructure("tower", cx, cy, { repairable = true })
        elseif gates[key] then
          self:addStructure("gate", cx, cy, { dir = dir, strip = gates[key], repairable = true })
        else
          self:addStructure("fence", cx, cy, { dir = dir, repairable = true })
        end
      end
    end
  end
  self.hq.repairable = true
  self.armory.repairable = true

  for _, c in ipairs({ { 21, 18 }, { 33, 26 }, { 33, 29 }, { 17, 21 }, { 20, 33 }, { 31, 16 } }) do
    self:addStructure("crates", B + c[1], B + c[2], { repairable = false })
  end

  self.lamps = {
    { 23.3, 29.5, 2.2 }, { 26.7, 31.5, 2.2 }, { 29.5, 23.3, 2.2 }, { 31.5, 26.7, 2.2 },
    { 18.0, 19.5, 2.0 }, { 32.5, 17.5, 2.0 }, { 20.5, 32.0, 2.0 },
  }
  self.fires = {
    { 24.3, 30.6 }, { 29.0, 25.6 }, { 19.6, 21.3 }, { 31.5, 20.5 }, { 20.5, 29.5 },
  }
  for _, l in ipairs(self.lamps) do l[1], l[2] = l[1] + B, l[2] + B end
  for _, f in ipairs(self.fires) do
    f[1], f[2] = f[1] + B, f[2] + B
    f.isFire = true
  end

  -- light sources that cast unit shadows
  self.shadowLights = {}
  for _, l in ipairs(self.lamps) do self.shadowLights[#self.shadowLights + 1] = { l[1], l[2] } end
  for _, f in ipairs(self.fires) do self.shadowLights[#self.shadowLights + 1] = { f[1], f[2] } end
  for _, s in ipairs(self.structures) do
    if s.kind == "tower" then self.shadowLights[#self.shadowLights + 1] = { s.cx, s.cy } end
  end
end

-- Dirt tracks inside the walls (the town's streets are asphalt).
local function isRoad(cx, cy)
  cx, cy = cx - B, cy - B
  if (cx == 24 or cx == 25) and cy >= 27 and cy <= 35 then return true end
  if (cy == 24 or cy == 25) and cx >= 27 and cx <= 35 then return true end
  if cx >= 21 and cx <= 28 and cy >= 21 and cy <= 28 then
    return cx == 21 or cx == 28 or cy == 21 or cy == 28
  end
  return false
end

-- Procedural ground: layered dirt noise, damp patches, packed earth inside the
-- walls and on roads, pebbles, cracks and weeds. Rendered once into a canvas.
local GROUND_SHADER = [[
extern vec2 canvasSize;
extern vec2 isoOffset;
extern vec2 mapSize;
extern Image mask;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return v;
}
// distance to the nearest scattered point, plus a random id for it
vec2 cells(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float md = 8.0;
  float id = 0.0;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 g = vec2(float(x), float(y));
      vec2 o = vec2(hash(i + g), hash(i + g + 17.0));
      vec2 r = g + o - f;
      float d = dot(r, r);
      if (d < md) { md = d; id = hash(i + g + 31.0); }
    }
  }
  return vec2(sqrt(md), id);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 iso = tc * canvasSize + isoOffset;
  vec2 w = vec2((iso.x / 32.0 + iso.y / 16.0) * 0.5, (iso.y / 16.0 - iso.x / 32.0) * 0.5);
  float edge = min(min(w.x, w.y), min(mapSize.x - w.x, mapSize.y - w.y));
  if (edge < 0.0) return vec4(0.0);

  vec2 warp = (vec2(fbm(w * 0.6), fbm(w * 0.6 + 5.0)) - 0.5) * 0.9;
  vec2 m = Texel(mask, (w + warp) / mapSize).rg;
  float road = smoothstep(0.35, 0.7, m.r);
  float inside = smoothstep(0.3, 0.7, m.g);

  float n = fbm(w * 0.3);
  float n2 = fbm(w * 1.6 + 3.0);
  vec3 col = mix(vec3(0.20, 0.14, 0.09), vec3(0.34, 0.24, 0.15), smoothstep(0.3, 0.72, n));
  col = mix(col, vec3(0.44, 0.34, 0.22), smoothstep(0.55, 0.85, n2) * 0.45);
  col *= 1.0 - 0.3 * smoothstep(0.55, 0.78, fbm(w * 0.16 + 9.0));

  vec3 yardCol = vec3(0.38, 0.29, 0.19) * (0.82 + 0.3 * n2);
  col = mix(col, yardCol, inside * 0.6);
  vec3 roadCol = vec3(0.46, 0.36, 0.24) * (0.85 + 0.28 * n2);
  col = mix(col, roadCol, road * 0.85);

  // the town's asphalt streets: patched, cracked and dusted with dirt
  float asphalt = smoothstep(0.4, 0.6, Texel(mask, w / mapSize).b);
  vec3 asph = vec3(0.19, 0.185, 0.18) * (0.78 + 0.36 * n2);
  asph *= 1.0 - 0.28 * smoothstep(0.6, 0.76, fbm(w * 0.9 + 13.0));
  float acrack = 1.0 - smoothstep(0.0, 0.03, abs(fbm(w * 1.3 + 55.0) - 0.5));
  asph *= 1.0 - acrack * 0.55;
  asph = mix(asph, col, smoothstep(0.6, 0.85, fbm(w * 0.5 + 31.0)) * 0.6);
  col = mix(col, asph, asphalt * 0.95);
  road = max(road, asphalt);

  float weeds = smoothstep(0.6, 0.7, fbm(w * 0.45 + 20.0)) * (1.0 - inside * 0.8) * (1.0 - road * 0.7);
  float blades = noise(w * vec2(18.0, 6.0));
  col = mix(col, vec3(0.25, 0.27, 0.12) * (0.6 + 0.7 * blades), weeds * 0.75);

  vec2 st = cells(w * 3.2);
  float stone = (1.0 - smoothstep(0.1, 0.19, st.x)) * step(0.6, st.y);
  vec2 st2 = cells(w * 3.2 + vec2(0.03, 0.05));
  float lit = (1.0 - smoothstep(0.08, 0.16, st2.x)) * step(0.6, st2.y);
  vec3 stoneCol = vec3(0.30, 0.26, 0.22) * (0.75 + 0.5 * st.y);
  col = mix(col, stoneCol * 0.55, stone * (1.0 - road * 0.5));
  col = mix(col, stoneCol * 1.25, lit * stone * (1.0 - road * 0.5));

  col *= 0.86 + 0.28 * noise(w * 24.0);
  // dried cracks only in some patches, not everywhere
  float crack = 1.0 - smoothstep(0.0, 0.022, abs(fbm(w * 0.8 + 40.0) - 0.5));
  crack *= smoothstep(0.5, 0.65, fbm(w * 0.12 + 70.0)) * (1.0 - road);
  col *= 1.0 - crack * 0.3;

  return vec4(col, smoothstep(0.0, 1.5, edge));
}
]]

-- Lines, rocks and debris painted onto the ground once, on top of the shader.
local function groundDetails(decor)
  -- dashed centre lines down the town's streets
  lg.setLineWidth(1.5)
  lg.setColor(0.62, 0.56, 0.36, 0.5)
  for _, s in ipairs(Town.STREETS) do
    local t = 0.2
    while t < MAP_W do
      local crossing = false
      for _, o in ipairs(Town.STREETS) do
        if t + 0.5 > o - 1 and t < o + 1 then crossing = true end
      end
      local inside = t > F_MIN - 1 and t < F_MAX and s > F_MIN - 1 and s < F_MAX
      if not crossing and not inside then
        local ax, ay = P(t, s)
        local bx, by = P(t + 0.5, s)
        lg.line(ax, ay, bx, by)
        ax, ay = P(s, t)
        bx, by = P(s, t + 0.5)
        lg.line(ax, ay, bx, by)
      end
      t = t + 1.25
    end
  end

  -- wheel ruts along the dirt tracks inside the walls
  lg.setLineWidth(3)
  for _, off in ipairs({ 0.6, 1.4 }) do
    for _, seg in ipairs({ { B + 23 + off, B + 27, B + 23 + off, F_MAX }, { B + 27, B + 23 + off, F_MAX, B + 23 + off } }) do
      local ax, ay = P(seg[1], seg[2])
      local bx, by = P(seg[3], seg[4])
      lg.setColor(0.12, 0.09, 0.06, 0.45)
      lg.line(ax, ay, bx, by)
    end
  end

  -- loose rocks, planks and tyres, each with a little shadow
  for _, d in ipairs(decor) do
    local sx, sy = P(d.x, d.y)
    local s, g = d.s, d.g
    if d.r < 0.7 then
      lg.setColor(0, 0, 0, 0.45)
      lg.ellipse("fill", sx + s * 0.6, sy + s * 0.25, s * 1.2, s * 0.5)
      lg.setColor(g, g * 0.88, g * 0.76)
      lg.polygon("fill", sx - s, sy, sx - s * 0.4, sy - s * 0.7, sx + s * 0.6, sy - s * 0.6, sx + s, sy, sx, sy + s * 0.4)
      lg.setColor(g * 1.5, g * 1.35, g * 1.15)
      lg.polygon("fill", sx - s * 0.6, sy - s * 0.2, sx - s * 0.3, sy - s * 0.6, sx + s * 0.4, sy - s * 0.5, sx + s * 0.2, sy - s * 0.1)
    elseif d.r < 0.88 then
      local len = 8 + s * 2.5
      lg.push()
      lg.translate(sx, sy)
      lg.rotate(d.a)
      lg.setColor(0, 0, 0, 0.4)
      lg.rectangle("fill", -len / 2 + 1, 0, len, 3)
      lg.setColor(0.30, 0.21, 0.13)
      lg.rectangle("fill", -len / 2, -2, len, 3)
      lg.pop()
    else
      lg.setColor(0, 0, 0, 0.45)
      lg.ellipse("fill", sx + 1, sy + 1.5, 7, 3.5)
      lg.setColor(0.07, 0.07, 0.07)
      lg.setLineWidth(3)
      lg.ellipse("line", sx, sy, 6, 3)
    end
  end
end

-- The ground never changes, so the shader paints it once into a grid of
-- canvas chunks (one canvas would be too large for this map).
local CHUNK_W, CHUNK_H = 2048, 1024

function Game:renderGround()
  local totalW, totalH = (MAP_W + MAP_H) * Iso.HALF_W, (MAP_W + MAP_H) * Iso.HALF_H
  local originX = -MAP_H * Iso.HALF_W

  local mask = love.image.newImageData(MAP_W, MAP_H)
  local streets = self.townRoad or {}
  for cy = 1, MAP_H do
    for cx = 1, MAP_W do
      local inside = cx >= F_MIN and cx <= F_MAX and cy >= F_MIN and cy <= F_MAX
      local asphalt = streets[self.map:idx(cx, cy)] and 1 or 0
      mask:setPixel(cx - 1, cy - 1, isRoad(cx, cy) and 1 or 0, inside and 1 or 0, asphalt, 1)
    end
  end
  local maskImg = lg.newImage(mask)
  maskImg:setFilter("linear", "linear")
  local shader = lg.newShader(GROUND_SHADER)
  shader:send("mapSize", { MAP_W, MAP_H })
  shader:send("mask", maskImg)
  local white = lg.newImage(love.image.newImageData(1, 1, "rgba8", string.char(255, 255, 255, 255)))

  local decor = {}
  for _ = 1, 700 do
    decor[#decor + 1] = {
      x = 1 + love.math.random() * (MAP_W - 2), y = 1 + love.math.random() * (MAP_H - 2),
      r = love.math.random(), s = 2 + love.math.random() * 4, g = 0.22 + love.math.random() * 0.1,
      a = love.math.random() * math.pi,
    }
  end

  self.groundChunks = {}
  for oy = 0, totalH - 1, CHUNK_H do
    for ox = 0, totalW - 1, CHUNK_W do
      local cw, ch = math.min(CHUNK_W, totalW - ox), math.min(CHUNK_H, totalH - oy)
      local canvas = lg.newCanvas(cw, ch)
      local isoX, isoY = originX + ox, oy
      lg.setCanvas(canvas)
      lg.clear(0, 0, 0, 0)
      lg.push()
      lg.origin()
      shader:send("canvasSize", { cw, ch })
      shader:send("isoOffset", { isoX, isoY })
      lg.setShader(shader)
      lg.setColor(1, 1, 1)
      lg.draw(white, 0, 0, 0, cw, ch)
      lg.setShader()
      lg.translate(-isoX, -isoY)
      groundDetails(decor)
      lg.pop()
      lg.setCanvas()
      self.groundChunks[#self.groundChunks + 1] = { canvas = canvas, x = isoX, y = isoY, w = cw, h = ch }
    end
  end
end

-- Visible part of the world in iso pixels, for culling.
function Game:viewRect(margin)
  local cam = self.camera
  local w, h = lg.getDimensions()
  local x0, y0 = cam:screenToIso(0, 0)
  local x1, y1 = cam:screenToIso(w, h)
  margin = margin or 0
  return x0 - margin, y0 - margin, x1 + margin, y1 + margin
end

----------------------------------------------------------------------------
-- People

function Game:addSurvivor(s, x, y)
  x = x or (self.hq.cx + (love.math.random() - 0.5) * 3)
  y = y or (self.hq.wy2 + 0.8 + love.math.random())
  local cx, cy = self.map:nearestOpen(Map.cellOf(x, y))
  if not self.map:blockedForSurvivor(Map.cellOf(x, y)) then
    s.x, s.y = x, y
  else
    s.x, s.y = cx - 0.5, cy - 0.5
  end
  self.survivors[#self.survivors + 1] = s
  if self.groups and self.groups[s.group].mobilized then
    s:mobilize(self)
  else
    s:goWork()
  end
end

function Game:groupMembers(name, activeOnly)
  local out = {}
  for _, s in ipairs(self.survivors) do
    if s.group == name and s.state ~= "dead" and (not activeOnly or s:isActive()) then
      out[#out + 1] = s
    end
  end
  return out
end

function Game:livingCount()
  local n = 0
  for _, s in ipairs(self.survivors) do
    if s.state ~= "dead" then n = n + 1 end
  end
  return n
end

-- A spot along the front (south side) of a building, where its workers stand.
local function frontOf(s)
  return s.wx1 + 0.3 + love.math.random() * (s.w - 0.6), s.wy2 + 0.45 + love.math.random() * 0.7
end

function Game:workSpot(group)
  if group == "Agriculture" then
    local hydro = self.hydroponics and not self.hydroponics.dead and self.hydroponics
    if hydro and love.math.random() < 0.4 then return frontOf(hydro) end
    local g = self.garden
    return g.wx1 + 0.35 + love.math.random() * (g.w - 0.7), g.wy1 + 0.35 + love.math.random() * (g.h - 0.7)
  end
  if group == "Combat" then
    if self.barracks and not self.barracks.dead then return frontOf(self.barracks) end
    if not self.armory.dead then
      local a = self.armory
      return a.wx1 + 0.3 + love.math.random() * (a.w - 0.3), a.wy2 + 1.0 + love.math.random() * 1.2
    end
  end
  if group == "Scouting" and not self.lookout.dead then return frontOf(self.lookout) end
  if group == "Scavenging" and not self.salvageYard.dead then return frontOf(self.salvageYard) end
  return self.hq.cx + (love.math.random() - 0.5) * 3, self.hq.wy2 + 1 + love.math.random()
end

function Game:doWork(s, dt)
  local hungry = self.res.food <= 0 and 0.5 or 1
  if s.group == "Agriculture" then
    local rate = 0.085 * (0.6 + s.apt.Agriculture * 0.06 + s.prof.Agriculture * 0.05)
      * s:traitMul("work") * s:traitMul("farm") * self.foodMult * hungry
    self.res.food = self.res.food + rate * dt
    self.production = self.production + rate
    s:learn(self, "Agriculture", 0.004 * dt)
  elseif s.group == "Combat" then
    s:learn(self, "Combat", 0.012 * dt * (0.5 + s.apt.Combat * 0.08) * hungry)
  elseif s.group == "Scouting" then
    s:learn(self, "Scouting", 0.01 * dt * (0.5 + s.apt.Scouting * 0.08) * hungry)
  elseif s.group == "Scavenging" then
    -- picking through the scrap pile slowly turns up more
    self.scrapAcc = (self.scrapAcc or 0) + 0.02 * (0.6 + s.apt.Scavenging * 0.06) * s:traitMul("work") * hungry * dt
    if self.scrapAcc >= 1 then
      self.res.scrap = self.res.scrap + 1
      self.scrapAcc = self.scrapAcc - 1
    end
    s:learn(self, "Scavenging", 0.004 * dt)
  end
end

-- Spots in front of the armory's issue counter.
function Game:armorySlot(s)
  if self.armory.dead then return nil end
  local a = self.armory
  local k = s.id % 5
  return a.wx1 + 0.4 + k * 0.45, a.wy2 + 0.55
end

local function ringOffset(k)
  if k <= 1 then return 0, 0 end
  local ring, idx, count = 1, k - 2, 6
  while idx >= count do
    idx = idx - count
    ring = ring + 1
    count = ring * 6
  end
  local a = idx / count * math.pi * 2 + ring * 0.5
  return math.cos(a) * ring * 0.65, math.sin(a) * ring * 0.65
end

function Game:rallySlot(s)
  local grp = self.groups[s.group]
  local k = 1
  for _, o in ipairs(self:groupMembers(s.group, true)) do
    if o == s then break end
    k = k + 1
  end
  local ox, oy = ringOffset(k)
  return grp.rallyX + ox, grp.rallyY + oy
end

function Game:issueWeapon(s)
  local want = self.groups[s.group].loadout
  if want == "improvised" then
    s.weapon = "improvised"
  elseif self.stock[want] > 0 then
    self.stock[want] = self.stock[want] - 1
    s.weapon = want
  else
    s.weapon = "improvised"
    if not self.warnedStock then
      self:message("Out of " .. D.LOADOUT_LABELS[want]:lower() .. ": some survivors grabbed improvised weapons.", "alert")
      self.warnedStock = true
    end
  end
end

function Game:storeWeapon(s)
  if s.weapon == "rifle" or s.weapon == "pistol" then
    self.stock[s.weapon] = self.stock[s.weapon] + 1
  end
  s.weapon = nil
end

function Game:setMobilized(name, on)
  local grp = self.groups[name]
  grp.mobilized = on
  self.warnedStock = false
  for _, s in ipairs(self:groupMembers(name, true)) do
    if on then s:mobilize(self) else s:returnToWork(self) end
  end
  self:message(on and (name .. " mobilized: heading to the armory.") or (name .. " returning to work."), on and "alert" or nil)
end

function Game:killSurvivor(s)
  s.state = "dead"
  self.stats.lost = self.stats.lost + 1
  s.weapon = nil
  s.carry = nil
  for i = #self.selection, 1, -1 do
    if self.selection[i] == s then table.remove(self.selection, i) end
  end
  self.decals[#self.decals + 1] = { kind = "body", x = s.x, y = s.y, t = 0, life = 9999, col = D.GROUP_COLORS[s.group] }
  self:message(s.name .. " (" .. s.background .. ") has died.", "bad")
end

function Game:rescue(s)
  s.hp = s.maxhp * 0.25
  s.state = "squad"
  s.order, s.focus, s.path = nil, nil, nil
  s.guardX, s.guardY = s.x, s.y
  self:message(s.name .. " is back on their feet.", "good")
end

function Game:reviveDowned()
  for _, s in ipairs(self.survivors) do
    if s.state == "downed" then
      s.hp = s.maxhp * 0.3
      self:message(s.name .. " was pulled back to safety.", "good")
      if self.groups[s.group].mobilized then s:goRally(self) else s:returnToWork(self) end
    end
  end
end

----------------------------------------------------------------------------
-- Zombies and structures

-- Wave packs come out of the town some way beyond the walls on their side.
Game.WAVE_DISTANCE = 13

function Game:spawnZombie(kind, edge)
  local x, y
  local r = U.clamp(edge.center + (love.math.random() - 0.5) * 9, 2, MAP_W - 2)
  local d = Game.WAVE_DISTANCE
  if edge.side == "x0" then x, y = F_MIN - d, r
  elseif edge.side == "x1" then x, y = F_MAX + d, r
  elseif edge.side == "y0" then x, y = r, F_MIN - d
  else x, y = r, F_MAX + d end
  local cx, cy = Map.cellOf(x, y)
  cx, cy = self.map:nearestOpen(cx, cy, Map.blockedForZombie)
  if not cx then return end
  self.zombies[#self.zombies + 1] = Zombie.new(kind, cx - 0.5, cy - 0.5, self.director.wave)
end

function Game:killZombie(z)
  self.stats.kills = self.stats.kills + 1
  self.decals[#self.decals + 1] = { kind = "corpse", x = z.x, y = z.y, t = 0, life = 30, big = z.kind == "brute" }
end

function Game:nearestZombie(x, y, r)
  local best, bd = nil, r * r
  for _, z in ipairs(self.zombies) do
    if not z.dead then
      local dx, dy = z.x - x, z.y - y
      local d = dx * dx + dy * dy
      if d <= bd then best, bd = z, d end
    end
  end
  return best
end

function Game:nearestSurvivor(x, y, r)
  local best, bd = nil, r * r
  for _, s in ipairs(self.survivors) do
    if s:isActive() then
      local dx, dy = s.x - x, s.y - y
      local d = dx * dx + dy * dy
      if d <= bd then best, bd = s, d end
    end
  end
  return best
end

function Game:damageStructure(s, dmg, fx, fy)
  if s.dead or s.solid then return end
  s.hp = s.hp - dmg
  if (s == self.hq or s == self.armory) and self.time - (s.lastWarn or -99) > 12 then
    s.lastWarn = self.time
    self:message("The " .. s.name .. " is under attack!", "bad")
  end
  for _ = 1, 3 do
    self.effects[#self.effects + 1] = {
      kind = "spark", x = fx, y = fy, t = 0, life = 0.35,
      vx = (love.math.random() - 0.5) * 60, vy = -20 - love.math.random() * 40,
    }
  end
  if s.hp <= 0 then self:destroyStructure(s) end
end

function Game:destroyStructure(s)
  s.dead = true
  s.hp = 0
  self.map:remove(s)
  for i = #self.structures, 1, -1 do
    if self.structures[i] == s then table.remove(self.structures, i) end
  end
  local bits = {}
  for _ = 1, 6 + s.w * s.h * 4 do
    bits[#bits + 1] = {
      s.wx1 + love.math.random() * s.w, s.wy1 + love.math.random() * s.h,
      0.18 + love.math.random() * 0.18, 2 + love.math.random() * 4,
    }
  end
  self.decals[#self.decals + 1] = { kind = "rubble", bits = bits, t = 0, life = 9999 }
  if s.repairable and s.kind ~= "hq" then
    self.ruins[#self.ruins + 1] = { kind = s.kind, x1 = s.x1, y1 = s.y1, dir = s.dir, strip = s.strip, name = s.name }
  end
  if s == self.hq then
    self:gameOver("The " .. self.hqDef.name .. " has fallen.")
  elseif s == self.armory then
    self:message("The Box Truck Armory was destroyed! Mobilizing groups can no longer collect gear.", "bad")
  elseif (s.kind == "fence" or s.kind == "gate") and self.breachWarned ~= self.director.wave then
    self.breachWarned = self.director.wave
    self:message("The perimeter has been breached!", "bad")
  end
  self.map:computeFlow(self.hq)
end

function Game:repairCost()
  local cost = 0
  for _, s in ipairs(self.structures) do
    if s.repairable and s.hp < s.maxhp then cost = cost + math.ceil((s.maxhp - s.hp) / HP_PER_SCRAP) end
  end
  return cost + #self.ruins * REBUILD_COST
end

local function cellOccupied(game, cx, cy)
  for _, list in ipairs({ game.survivors, game.zombies }) do
    for _, u in ipairs(list) do
      if not u.dead and u.state ~= "dead" then
        local ux, uy = Map.cellOf(u.x, u.y)
        if ux == cx and uy == cy then return true end
      end
    end
  end
  return false
end

function Game:repairWalls()
  local spent = 0
  for _, s in ipairs(self.structures) do
    if s.repairable and s.hp < s.maxhp and self.res.scrap > 0 then
      local pay = math.min(math.ceil((s.maxhp - s.hp) / HP_PER_SCRAP), self.res.scrap)
      s.hp = math.min(s.maxhp, s.hp + pay * HP_PER_SCRAP)
      self.res.scrap = self.res.scrap - pay
      spent = spent + pay
    end
  end
  for i = #self.ruins, 1, -1 do
    local r = self.ruins[i]
    if self.res.scrap >= REBUILD_COST and not cellOccupied(self, r.x1, r.y1) then
      local s = self:addStructure(r.kind, r.x1, r.y1, { dir = r.dir, strip = r.strip, repairable = true })
      if r.kind == "armory" then self.armory = s end
      if r.kind == "barracks" then self.barracks = s end
      if r.kind == "hydroponics" then self.hydroponics = s end
      self.res.scrap = self.res.scrap - REBUILD_COST
      spent = spent + REBUILD_COST
      table.remove(self.ruins, i)
    end
  end
  self.map:computeFlow(self.hq)
  if spent > 0 then self:message("Spent " .. spent .. " scrap on repairs.", "good") end
end

----------------------------------------------------------------------------
-- Exploration: fog of war, the town's infected, searching and loot

-- Fog per cell: 0 unexplored, 1 explored but out of sight, 2 in sight.
function Game:initFog()
  self.fog = {}
  for i = 1, MAP_W * MAP_H do self.fog[i] = 0 end
  self.fogData = love.image.newImageData(MAP_W, MAP_H)
  self.fogImg = lg.newImage(self.fogData)
  self.fogImg:setFilter("linear", "linear")
  self.fogT = 0
  self.fogShader = lg.newShader([[
    extern Image fog;
    extern vec2 camPos;
    extern float zoom;
    extern vec2 screenCenter;
    extern vec2 mapSize;
    extern vec3 tint;
    extern float mode;
    extern float memory;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec2 iso = (sc - screenCenter) / zoom + camPos;
      vec2 w = vec2((iso.x / 32.0 + iso.y / 16.0) * 0.5, (iso.y / 16.0 - iso.x / 32.0) * 0.5);
      float f = Texel(fog, w / mapSize).r;
      if (w.x < 0.0 || w.y < 0.0 || w.x > mapSize.x || w.y > mapSize.y) f = 0.0;
      float seen = smoothstep(0.05, 0.4, f);
      float sight = smoothstep(0.45, 0.95, f);
      if (mode < 0.5) {
        // sky light where someone can see, a trace of it where they've been
        return vec4(tint * (sight + seen * memory), 1.0);
      }
      float m = mix(seen * (0.35 + memory * 0.5), 1.0, sight);
      return vec4(m, m, m, 1.0);
    }
  ]])
end

function Game:fogAt(x, y)
  local cx, cy = Map.cellOf(x, y)
  if cx < 1 or cy < 1 or cx > MAP_W or cy > MAP_H then return 0 end
  return self.fog[(cy - 1) * MAP_W + cx]
end

local function reveal(fog, x, y, r)
  local r2 = r * r
  for cy = math.max(1, math.floor(y - r) + 1), math.min(MAP_H, math.floor(y + r) + 1) do
    for cx = math.max(1, math.floor(x - r) + 1), math.min(MAP_W, math.floor(x + r) + 1) do
      local dx, dy = cx - 0.5 - x, cy - 0.5 - y
      if dx * dx + dy * dy <= r2 then fog[(cy - 1) * MAP_W + cx] = 2 end
    end
  end
end

function Game:updateFog()
  local fog = self.fog
  for i = 1, #fog do
    if fog[i] == 2 then fog[i] = 1 end
  end
  -- the walls and the cleared ground around them are always in sight
  for cy = F_MIN - 3, F_MAX + 3 do
    for cx = F_MIN - 3, F_MAX + 3 do fog[(cy - 1) * MAP_W + cx] = 2 end
  end
  for _, s in ipairs(self.survivors) do
    if s:isActive() then reveal(fog, s.x, s.y, s:vision() * (0.8 + 0.35 * self.director:daylight())) end
  end
  for _, s in ipairs(self.structures) do
    if s.kind == "tower" then reveal(fog, s.cx, s.cy, 7) end
  end
  for i, s in ipairs(self.sites) do
    if not s.site.known and fog[(s.y1 - 1) * MAP_W + s.x1] == 2 then s.site.known = true end
  end
  local data = self.fogData
  for cy = 1, MAP_H do
    for cx = 1, MAP_W do
      local v = fog[(cy - 1) * MAP_W + cx]
      local f = v == 2 and 1 or (v == 1 and 0.4 or 0)
      data:setPixel(cx - 1, cy - 1, f, f, f, 1)
    end
  end
  self.fogImg:replacePixels(data)
  self.minimapDirty = true
end

function Game:spawnRoamer(x, y)
  local cx, cy = Map.cellOf(x, y)
  cx, cy = self.map:nearestOpen(cx, cy, Map.blockedForZombie)
  if not cx then return end
  local z = Zombie.new(love.math.random() < 0.15 and "runner" or "walker", cx - 0.5, cy - 0.5, 1)
  z.home = { z.x, z.y }
  self.zombies[#self.zombies + 1] = z
end

function Game:waveZombieCount()
  local n = 0
  for _, z in ipairs(self.zombies) do
    if not z.home and not z.dead then n = n + 1 end
  end
  return n
end

-- Gunfire draws in idle infected from around the town.
function Game:noise(x, y, r, source)
  local r2 = r * r
  for _, z in ipairs(self.zombies) do
    if z.home and not z.target and not z.dead then
      local dx, dy = z.x - x, z.y - y
      if dx * dx + dy * dy < r2 then z.target = source end
    end
  end
end

function Game:inWalls(x, y)
  local cx, cy = Map.cellOf(x, y)
  return cx > F_MIN and cx < F_MAX and cy > F_MIN and cy < F_MAX
end

-- Searching a building: everyone standing at its door adds progress; when it
-- is done the loot is split between them to carry home.
function Game:searchTick(s, site, dt)
  local rate = (0.5 + s.apt.Scavenging * 0.06 + s.prof.Scavenging * 0.08) * (s.group == "Scavenging" and 1.5 or 1)
  site.site.progress = site.site.progress + rate * dt
  s:learn(self, "Scavenging", 0.01 * dt)
  if site.site.progress >= site.site.work then self:completeSearch(site) end
end

function Game:completeSearch(site)
  local info = site.site
  if info.searched then return end
  info.searched = true
  local crew = {}
  for _, s in ipairs(self.survivors) do
    if s:isActive() and s.order and s.order.kind == "search" and s.order.site == site then crew[#crew + 1] = s end
  end
  if #crew == 0 then return end
  local parts = {}
  for k, n in pairs(info.loot) do
    parts[#parts + 1] = n .. " " .. (k == "rifle" and "rifle" or k == "pistol" and "pistol" or k)
    for i, s in ipairs(crew) do
      local share = math.floor(n / #crew) + ((i <= n % #crew) and 1 or 0)
      if share > 0 then
        s.carry = s.carry or {}
        s.carry[k] = (s.carry[k] or 0) + share
      end
    end
  end
  for _, s in ipairs(crew) do
    s.order = nil
    s.guardX, s.guardY = s.x, s.y
  end
  if #parts == 0 then
    self:message(site.name .. " searched: nothing useful left.")
  else
    self:message(site.name .. " searched: found " .. table.concat(parts, ", ") .. ". Bring it home to use it.", "good")
  end
end

function Game:deliver(s)
  local parts = {}
  for k, n in pairs(s.carry) do
    if k == "rifle" or k == "pistol" then
      self.stock[k] = self.stock[k] + n
    else
      self.res[k] = self.res[k] + n
    end
    parts[#parts + 1] = n .. " " .. k
  end
  s.carry = nil
  if #parts > 0 then self:message(s.name .. " brought home " .. table.concat(parts, ", ") .. ".", "good") end
end

function Game:orderSearch(site)
  local list = self:selectedActive()
  local ex, ey = Town.entrance(site)
  for i, s in ipairs(list) do
    local ox, oy = ringOffset(i)
    s.state = "squad"
    s.focus = nil
    s.order = { kind = "search", site = site }
    if not s:walkTo(self, ex + ox * 0.6, ey + oy * 0.6) then s.order = nil end
    s.guardX, s.guardY = ex + ox * 0.6, ey + oy * 0.6
  end
  if #list > 0 then
    self:message("Sending " .. #list .. " to search the " .. site.name .. ".")
  end
end

-- The town building whose painting is under the mouse, front-most first.
function Game:siteAt(mx, my)
  local ix, iy = self.camera:screenToIso(mx, my)
  local best
  for _, s in ipairs(self.structures) do
    if s.town and self:fogAt(s.cx, s.cy) > 0 then
      local sp = S.spriteFor(s)
      if sp then
        local sx, sy = P(s.cx, s.cy, 0)
        local k = sp.def.scale
        local x0, y0 = sx - sp.def.ax * k, sy - sp.def.ay * k
        if ix >= x0 and ix <= x0 + sp.img:getWidth() * k and iy >= y0 and iy <= sy + s.w * 8 then
          if not best or s.depth > best.depth then best = s end
        end
      end
    end
  end
  return best
end

----------------------------------------------------------------------------
-- Orders

function Game:selectedActive()
  local out = {}
  for _, s in ipairs(self.selection) do
    if s:isActive() then out[#out + 1] = s end
  end
  return out
end

function Game:orderMove(x, y, kind)
  local list = self:selectedActive()
  for i, s in ipairs(list) do
    local ox, oy = ringOffset(i)
    local tx, ty = x + ox, y + oy
    s.state = "squad"
    s.focus = nil
    s.order = { kind = kind }
    if not s:walkTo(self, tx, ty) then s.order = nil end
    s.guardX, s.guardY = tx, ty
  end
  if #list > 0 then
    self.effects[#self.effects + 1] = { kind = "ping", x = x, y = y, t = 0, life = 0.5, amove = kind == "amove" }
  end
end

function Game:orderHold()
  for _, s in ipairs(self:selectedActive()) do
    s.state = "squad"
    s.path = nil
    s.focus = nil
    s.order = { kind = "hold" }
    s.guardX, s.guardY = s.x, s.y
  end
end

function Game:orderStop()
  for _, s in ipairs(self:selectedActive()) do
    if s.state == "squad" then
      s.path, s.order, s.focus = nil, nil, nil
      s.guardX, s.guardY = s.x, s.y
    end
  end
end

function Game:orderFocus(z)
  for _, s in ipairs(self:selectedActive()) do
    s.state = "squad"
    s.order = nil
    s.focus = z
  end
end

function Game:orderFallBack()
  for _, s in ipairs(self:selectedActive()) do s:goRally(self) end
end

function Game:selectGroup(name, add)
  if not add then self.selection = {} end
  for _, s in ipairs(self:groupMembers(name, true)) do self.selection[#self.selection + 1] = s end
end

function Game:isSelected(s)
  for _, o in ipairs(self.selection) do
    if o == s then return true end
  end
  return false
end

function Game:survivorAt(mx, my)
  local cam = self.camera
  local best, bd
  for _, s in ipairs(self.survivors) do
    if s.state ~= "dead" then
      local sx, sy = cam:worldToScreen(s.x, s.y, 0)
      local dx, dy = mx - sx, my - (sy - 9 * cam.zoom)
      if math.abs(dx) < 9 * cam.zoom and math.abs(dy) < 13 * cam.zoom then
        local d = dx * dx + dy * dy
        if not bd or d < bd then best, bd = s, d end
      end
    end
  end
  return best
end

function Game:zombieAt(mx, my)
  local cam = self.camera
  local best, bd
  for _, z in ipairs(self.zombies) do
    if not z.dead and self:fogAt(z.x, z.y) == 2 then
      local sz = z.kind == "brute" and 1.5 or 1
      local sx, sy = cam:worldToScreen(z.x, z.y, 0)
      local dx, dy = mx - sx, my - (sy - 9 * cam.zoom * sz)
      if math.abs(dx) < 10 * cam.zoom * sz and math.abs(dy) < 14 * cam.zoom * sz then
        local d = dx * dx + dy * dy
        if not bd or d < bd then best, bd = z, d end
      end
    end
  end
  return best
end

function Game:structureAt(mx, my)
  local wx, wy = self.camera:screenToWorld(mx, my)
  return self.map:structure(Map.cellOf(wx, wy))
end

----------------------------------------------------------------------------
-- Messages and effects

function Game:message(text, kind)
  table.insert(self.messages, 1, { text = text, kind = kind, t = 0 })
  if #self.messages > 7 then table.remove(self.messages) end
end

function Game:attackFx(s, z, wd, hit)
  local sx, sy = P(s.x, s.y, 0)
  local zx, zy = P(z.x, z.y, 0)
  if wd.ranged then
    local mx, my = sx + s.face * 10, sy - 11
    local tx, ty = zx, zy - 10
    if not hit then
      tx = tx + (love.math.random() - 0.5) * 30
      ty = ty + (love.math.random() - 0.5) * 20
    end
    self.effects[#self.effects + 1] = { kind = "tracer", x1 = mx, y1 = my, x2 = tx, y2 = ty, t = 0, life = 0.08 }
  else
    self.effects[#self.effects + 1] = { kind = "swing", x = (sx + zx) / 2, y = (sy + zy) / 2 - 10, t = 0, life = 0.15, face = s.face }
  end
  if hit then
    for _ = 1, 3 do
      self.effects[#self.effects + 1] = {
        kind = "blood", sx = zx, sy = zy - 10, t = 0, life = 0.4,
        vx = (love.math.random() - 0.5) * 50, vy = -10 - love.math.random() * 30,
      }
    end
  end
end

function Game:gameOver(reason)
  if self.over then return end
  local d = self.director
  local survived = (d.phase == "dusk" or d.phase == "night") and d.wave - 1 or d.wave
  self.over = { reason = reason, wave = survived }
end

----------------------------------------------------------------------------
-- Update

function Game:separate()
  local units = self.units
  local n = 0
  for _, s in ipairs(self.survivors) do
    if s:isActive() then
      n = n + 1
      units[n] = s
    end
  end
  for _, z in ipairs(self.zombies) do
    if not z.dead then
      n = n + 1
      units[n] = z
    end
  end
  for i = #units, n + 1, -1 do units[i] = nil end

  local map = self.map
  local function nudge(u, dx, dy)
    local nx, ny = u.x + dx, u.y + dy
    local blocked
    if u.isZombie then
      blocked = map:blockedForZombie(Map.cellOf(nx, ny))
    else
      blocked = map:blockedForSurvivor(Map.cellOf(nx, ny))
    end
    if not blocked then u.x, u.y = nx, ny end
  end
  for i = 1, n do
    local a = units[i]
    for j = i + 1, n do
      local b = units[j]
      local r = a.rad + b.rad
      local dx, dy = b.x - a.x, b.y - a.y
      if dx < r and dx > -r and dy < r and dy > -r then
        local d2 = dx * dx + dy * dy
        if d2 < r * r then
          local d = math.sqrt(d2)
          if d < 1e-4 then dx, dy, d = love.math.random() - 0.5, love.math.random() - 0.5, 0.5 end
          local push = (r - d) * 0.5
          local px, py = dx / d * push, dy / d * push
          nudge(a, -px, -py)
          nudge(b, px, py)
        end
      end
    end
  end
end

function Game:update(dt)
  for _, m in ipairs(self.messages) do m.t = m.t + dt end
  if self.over or self.paused then return end
  dt = dt * self.speed

  self.time = self.time + dt
  self.production = 0
  self.fogT = self.fogT - dt
  if self.fogT <= 0 then
    self.fogT = 0.25
    self:updateFog()
  end
  self.director:update(dt)
  for _, s in ipairs(self.survivors) do s:update(self, dt) end
  for _, z in ipairs(self.zombies) do
    if not z.dead then z:update(self, dt) end
  end
  for i = #self.zombies, 1, -1 do
    if self.zombies[i].dead then table.remove(self.zombies, i) end
  end
  self:separate()

  local consumption = self:livingCount() * FOOD_PER_SURVIVOR
  self.res.food = math.max(0, self.res.food - consumption * dt)
  local net = self.production - consumption
  self.foodRate = self.foodRate + (net - self.foodRate) * math.min(1, dt * 0.5)
  if self.res.food <= 0 and not self.warnedFood then
    self:message("Food has run out! Survivors weaken and work at half pace.", "bad")
    self.warnedFood = true
  elseif self.res.food > 5 then
    self.warnedFood = false
  end

  for i = #self.effects, 1, -1 do
    local e = self.effects[i]
    e.t = e.t + dt
    if e.t >= e.life then table.remove(self.effects, i) end
  end
  for i = #self.decals, 1, -1 do
    local d = self.decals[i]
    d.t = d.t + dt
    if d.t >= d.life then table.remove(self.decals, i) end
  end

  if self:livingCount() == 0 then self:gameOver("No survivors remain.") end
end

----------------------------------------------------------------------------
-- Drawing

local function drawDecal(d)
  if d.kind == "rubble" then
    S.drawRubble(d)
  elseif d.kind == "corpse" then
    local a = math.min(1, (d.life - d.t) / 5)
    local sx, sy = P(d.x, d.y, 0)
    local s = d.big and 1.5 or 1
    lg.setColor(0.25, 0.05, 0.04, 0.55 * a)
    lg.ellipse("fill", sx, sy, 9 * s, 4 * s)
    lg.setColor(0.27, 0.30, 0.22, a)
    lg.ellipse("fill", sx - 1, sy - 1.5, 6 * s, 2.4 * s)
  elseif d.kind == "body" then
    local sx, sy = P(d.x, d.y, 0)
    lg.setColor(0.3, 0.05, 0.04, 0.6)
    lg.ellipse("fill", sx, sy, 9, 4)
    G.setc(d.col, 0.45)
    lg.ellipse("fill", sx - 1, sy - 1.5, 6, 2.4)
  end
end

function Game:drawAlertMarkers()
  local phase = self.director.phase
  if phase ~= "dusk" and not (phase == "night" and #self.director.queue > 0) then return end
  local pulse = 0.5 + 0.5 * math.sin(self.time * 6)
  for _, e in ipairs(self.director.edges) do
    local mx, my, dx, dy
    local c = e.center
    if e.side == "x0" then mx, my, dx, dy = F_MIN - 4, c, 1, 0
    elseif e.side == "x1" then mx, my, dx, dy = F_MAX + 3, c, -1, 0
    elseif e.side == "y0" then mx, my, dx, dy = c, F_MIN - 4, 0, 1
    else mx, my, dx, dy = c, F_MAX + 3, 0, -1 end
    for k = 0, 2 do
      local bx, by = mx + dx * k * 0.9, my + dy * k * 0.9
      local px, py = -dy, dx
      local ax, ay = P(bx + dx * 0.6, by + dy * 0.6)
      local lx, ly = P(bx + px * 0.9, by + py * 0.9)
      local rx, ry = P(bx - px * 0.9, by - py * 0.9)
      lg.setColor(0.95, 0.15, 0.1, (0.35 + 0.5 * pulse) * (1 - k * 0.25))
      lg.polygon("fill", ax, ay, lx, ly, rx, ry)
    end
    local sx, sy = P(mx, my)
    G.glow(sx, sy, 140, { 1, 0.12, 0.08 }, 0.25 + 0.2 * pulse, true)
  end
end

function Game:drawRally(name)
  local grp = self.groups[name]
  local col = D.GROUP_COLORS[name]
  local bx, by = P(grp.rallyX, grp.rallyY, 0)
  local tx, ty = P(grp.rallyX, grp.rallyY, 1.3)
  lg.setColor(0, 0, 0, 0.35)
  lg.ellipse("fill", bx, by, 8, 4)
  lg.setColor(0.1, 0.1, 0.1)
  lg.setLineWidth(1.5)
  lg.line(bx, by, tx, ty)
  local wave = math.sin(self.time * 4) * 2
  G.setc(col)
  lg.polygon("fill", tx, ty, tx + 14, ty + 3 + wave, tx, ty + 8)
end

-- A long shadow thrown away from the nearest lamp or fire, or by day from the
-- low sun in the south-west.
function Game:drawCastShadow(x, y, size)
  local day = self.director:daylight()
  if day > 0.02 then
    local sx, sy = P(x, y, 0)
    local len = 15 * size
    lg.push()
    lg.translate(sx, sy)
    lg.rotate(-0.42)
    lg.setColor(0, 0, 0, 0.42 * day)
    lg.ellipse("fill", len * 0.45, 0, len * 0.55, 2.6 * size)
    lg.pop()
    if day > 0.6 then return end
  end
  local best, bd
  for _, l in ipairs(self.shadowLights) do
    local dx, dy = x - l[1], y - l[2]
    local d = dx * dx + dy * dy
    if d < 49 and (not bd or d < bd) then best, bd = l, d end
  end
  if not best then return end
  local sx, sy = P(x, y, 0)
  local lx, ly = P(best[1], best[2], 0)
  local d = math.sqrt(bd)
  local len = (10 + d * 4) * size
  lg.push()
  lg.translate(sx, sy)
  lg.rotate(math.atan2(sy - ly, sx - lx))
  lg.setColor(0, 0, 0, 0.5 * (1 - d / 7))
  lg.ellipse("fill", len * 0.45, 0, len * 0.55, 2.6 * size)
  lg.pop()
end

-- Sky light wherever a survivor can see; the light map is black elsewhere.
-- Moonlight at night, a hazy overcast sun by day, embers in between.
local MOONLIGHT = { 0.075, 0.08, 0.115 }
local DUSKLIGHT = { 0.50, 0.30, 0.20 }
local SUNLIGHT = { 0.88, 0.85, 0.78 }

local function mix3(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function skyLight(day)
  if day < 0.5 then return mix3(MOONLIGHT, DUSKLIGHT, day * 2) end
  return mix3(DUSKLIGHT, SUNLIGHT, (day - 0.5) * 2)
end

function Game:ensureCanvases()
  local w, h = lg.getDimensions()
  if not self.sceneCanvas or self.sceneCanvas:getWidth() ~= w or self.sceneCanvas:getHeight() ~= h then
    self.sceneCanvas = lg.newCanvas(w, h, { msaa = 4 })
    self.lightCanvas = lg.newCanvas(w, h)
  end
end

function Game:draw(ui)
  local cam = self.camera
  self:ensureCanvases()
  G.lights, G.glows, G.emissives = {}, {}, {}

  -- what's on screen (iso pixels, generous for tall paintings)
  local vx0, vy0, vx1, vy1 = self:viewRect(64)
  local function onScreen(x, y, up)
    local sx, sy = P(x, y, 0)
    return sx >= vx0 - 200 and sx <= vx1 + 200 and sy >= vy0 and sy <= vy1 + (up or 320)
  end
  local function shown(s)
    if s.town and self:fogAt(s.cx, s.cy) == 0 then return false end
    return onScreen(s.cx, s.cy, 420)
  end

  -- 1. the scene, as if fully lit
  lg.setCanvas({ self.sceneCanvas, stencil = true })
  lg.clear(0.03, 0.025, 0.02, 1)
  cam:apply()
  lg.setColor(1, 1, 1)
  for _, c in ipairs(self.groundChunks) do
    if c.x < vx1 and c.x + c.w > vx0 and c.y < vy1 and c.y + c.h > vy0 then
      lg.draw(c.canvas, c.x, c.y)
    end
  end
  for _, d in ipairs(self.decals) do drawDecal(d) end
  local drawn = {}
  for _, s in ipairs(self.structures) do
    if shown(s) then
      drawn[#drawn + 1] = s
      if s.flat then
        S.draw(s, self.time)
      elseif S.spriteFor(s) then
        S.drawSpriteGround(s)
      else
        G.contactShadow(s.cx, s.cy, (s.w + s.h) * 22, s.kind == "fence" and 0.4 or 0.6)
      end
    end
  end

  local list = self.drawList
  local n = 0
  for _, s in ipairs(drawn) do
    if not s.flat then
      n = n + 1
      list[n] = s
    end
  end
  for _, l in ipairs(self.lamps) do
    l.depth = l[1] + l[2]
    n = n + 1
    list[n] = l
  end
  for _, s in ipairs(self.survivors) do
    if s.state ~= "dead" and onScreen(s.x, s.y) then
      s.depth = s.x + s.y
      n = n + 1
      list[n] = s
    end
  end
  local seenZombies = {}
  for _, z in ipairs(self.zombies) do
    if self:fogAt(z.x, z.y) == 2 and onScreen(z.x, z.y) then
      z.depth = z.x + z.y
      n = n + 1
      list[n] = z
      seenZombies[#seenZombies + 1] = z
    end
  end
  for _, f in ipairs(self.fires) do
    f.depth = f[1] + f[2]
    n = n + 1
    list[n] = f
  end
  for i = #list, n + 1, -1 do list[i] = nil end
  table.sort(list, function(a, b) return a.depth < b.depth end)

  for _, o in ipairs(list) do
    if o.isSurvivor then
      o:draw(self)
    elseif o.isZombie then
      o:draw(self)
    elseif o.kind then
      S.draw(o, self.time)
    elseif o.isFire then
      local t = self.time
      local flicker = 0.85 + 0.15 * math.sin(t * 13 + o[1] * 3) * math.sin(t * 7.7 + o[2])
      if not S.drawPoint("firebarrel", o[1], o[2], 1, flicker) then S.drawFire(o, t) end
    else
      if not S.drawPoint("lamp", o[1], o[2]) then G.lampPost(o[1], o[2], o[3]) end
    end
  end
  for _, e in ipairs(self.effects) do
    local f = e.t / e.life
    if e.kind == "blood" then
      lg.setColor(0.55, 0.06, 0.04, 1 - f)
      lg.circle("fill", e.sx + e.vx * e.t, e.sy + e.vy * e.t + 60 * e.t * e.t, 1.4)
    end
  end
  cam:release()

  -- 2. the light map: every light queued above, plus moonlight in sight,
  -- then cut to black wherever nobody has explored
  lg.setCanvas(self.lightCanvas)
  lg.clear(0, 0, 0, 1)
  cam:apply()
  for _, s in ipairs(self.survivors) do
    if s.state ~= "dead" then
      local sx, sy = P(s.x, s.y, 0)
      G.lightAt(sx, sy - 16, 70, { 1, 0.9, 0.75 }, 0.7, 56)
    end
  end
  for _, e in ipairs(self.effects) do
    if e.kind == "tracer" then
      G.lightAt(e.x1, e.y1 + 8, 110, { 1, 0.8, 0.5 }, 1.2 * (1 - e.t / e.life), 80)
    end
  end
  G.flushLights()
  cam:release()
  local sw, sh = lg.getDimensions()
  local fs = self.fogShader
  fs:send("fog", self.fogImg)
  fs:send("camPos", { cam.x, cam.y })
  fs:send("zoom", cam.zoom)
  fs:send("screenCenter", { math.floor(sw / 2), math.floor(sh / 2) })
  fs:send("mapSize", { MAP_W, MAP_H })
  local day = self.director:daylight()
  fs:send("tint", skyLight(day))
  fs:send("memory", 0.2 + 0.35 * day)
  lg.setShader(fs)
  fs:send("mode", 0)
  lg.setBlendMode("add")
  lg.rectangle("fill", 0, 0, sw, sh)
  fs:send("mode", 1)
  lg.setBlendMode("multiply", "premultiplied")
  lg.rectangle("fill", 0, 0, sw, sh)
  lg.setBlendMode("alpha")
  lg.setShader()
  lg.setCanvas()

  -- 3. compose: scene x light
  lg.setColor(1, 1, 1)
  lg.draw(self.sceneCanvas)
  lg.setBlendMode("multiply", "premultiplied")
  lg.draw(self.lightCanvas)
  lg.setBlendMode("alpha")
  -- by day the light map tops out at 1, which still leaves the dark paintings
  -- looking like evening; add the lit scene once more, a little cooler
  if day > 0.01 then
    self.dayShader = self.dayShader or lg.newShader([[
      extern Image light;
      extern vec2 size;
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec3 l = Texel(light, sc / size).rgb;
        return vec4(Texel(tex, tc).rgb * l * color.rgb, 1.0);
      }
    ]])
    self.dayShader:send("light", self.lightCanvas)
    self.dayShader:send("size", { sw, sh })
    lg.setShader(self.dayShader)
    lg.setBlendMode("add")
    lg.setColor(0.42 * day, 0.48 * day, 0.56 * day)
    lg.draw(self.sceneCanvas)
    lg.setBlendMode("alpha")
    lg.setShader()
    lg.setColor(1, 1, 1)
  end

  -- 4. things that give off light, added on top; painted lamps and windows
  -- fade into the daylight
  cam:apply()
  G.glowScale = 1 - 0.8 * day
  G.flushEmissives()
  lg.setBlendMode("add")
  for _, s in ipairs(drawn) do S.drawEmissive(s, self.time) end
  for _, z in ipairs(seenZombies) do z:drawEyes() end
  lg.setBlendMode("alpha")
  Units.flushGlow(1 - day)
  lg.setBlendMode("add")
  lg.setBlendMode("alpha")
  for _, e in ipairs(self.effects) do
    local f = e.t / e.life
    if e.kind == "tracer" then
      lg.setColor(1, 0.85, 0.5, 1 - f)
      lg.setLineWidth(1.5)
      lg.line(e.x1, e.y1, e.x2, e.y2)
      G.glow(e.x1, e.y1, 16, G.C.amber, 0.9 * (1 - f))
    elseif e.kind == "swing" then
      lg.setColor(1, 1, 1, 0.7 * (1 - f))
      lg.setLineWidth(1.5)
      lg.arc("line", "open", e.x, e.y, 7, -1.2, 0.6)
    elseif e.kind == "spark" then
      local sx, sy = P(e.x, e.y, 0.5)
      lg.setColor(1, 0.75, 0.35, 1 - f)
      lg.circle("fill", sx + e.vx * e.t, sy + e.vy * e.t + 120 * e.t * e.t, 1.2)
    elseif e.kind == "ping" then
      local sx, sy = P(e.x, e.y, 0)
      if e.amove then lg.setColor(1, 0.35, 0.25, 1 - f) else lg.setColor(0.45, 1, 0.5, 1 - f) end
      lg.setLineWidth(1.5)
      lg.ellipse("line", sx, sy, 6 + f * 10, 3 + f * 5)
    end
  end

  G.flushGlows()
  G.glowScale = 1

  -- 5. readable overlays, never darkened
  self:drawAlertMarkers()
  if ui.rallyMode then self:drawRally(ui.rallyMode) end
  for _, name in ipairs(D.GROUPS) do
    if self.groups[name].mobilized and ui.rallyMode ~= name then self:drawRally(name) end
  end
  for _, s in ipairs(self.survivors) do
    if s.state ~= "dead" then s:drawOverlay(self:isSelected(s)) end
  end
  -- buildings the scouts have seen that still hold something
  local pulse = 0.75 + 0.25 * math.sin(self.time * 3)
  for _, s in ipairs(drawn) do
    local info = s.site
    if info and info.known and not info.searched and next(info.loot) then
      local sx, sy = P(s.cx, s.cy, s.kind == "wreck" and 1.6 or 3.2)
      lg.setColor(0, 0, 0, 0.6)
      lg.circle("fill", sx, sy, 7)
      lg.setColor(1, 0.72, 0.3, pulse)
      lg.polygon("fill", sx, sy - 5, sx + 4.5, sy, sx, sy + 5, sx - 4.5, sy)
      if info.progress > 0 then
        G.bar(sx - 12, sy + 9, 24, 3, info.progress / info.work, { 1, 0.72, 0.3 })
      end
    end
  end
  G.flushGlows()

  -- health bars on top of everything in the world
  for _, s in ipairs(self.structures) do
    if not s.flat and s.hp < s.maxhp then
      local sx, sy = P(s.cx, s.cy, s.def.barZ or 1)
      local w = s.kind == "hq" and 60 or (s.kind == "armory" and 40 or 22)
      G.bar(sx - w / 2, sy - 8, w, 3, s.hp / s.maxhp, G.hpColor(s.hp / s.maxhp))
    end
  end
  for _, s in ipairs(self.survivors) do
    if s:isActive() and (s.hp < s.maxhp or self:isSelected(s)) then
      local sx, sy = P(s.x, s.y, 0)
      G.bar(sx - 8, sy - 25, 16, 2, s.hp / s.maxhp, G.hpColor(s.hp / s.maxhp))
    end
  end
  for _, z in ipairs(seenZombies) do
    if z.hp < z.maxhp then
      local sx, sy = P(z.x, z.y, 0)
      local h = z.kind == "brute" and 34 or 24
      G.bar(sx - 8, sy - h, 16, 2, z.hp / z.maxhp, { 0.75, 0.2, 0.15 })
    end
  end

  cam:release()

  local w, h = lg.getDimensions()
  lg.setColor(1, 1, 1)
  lg.draw(G.vignetteImg, 0, 0, 0, w / G.vignetteImg:getWidth(), h / G.vignetteImg:getHeight())
end

return Game
