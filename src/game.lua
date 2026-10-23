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

local MAP_W, MAP_H = 48, 48
local F_MIN, F_MAX = 14, 35 -- fence ring, in cells
local FOOD_PER_SURVIVOR = 0.025 -- per second
local REBUILD_COST = 8
local HP_PER_SCRAP = 25

function Game.new(hqDef)
  local g = setmetatable({}, Game)
  g.hqDef = hqDef
  g.map = Map.new(MAP_W, MAP_H)
  g.structures, g.lamps = {}, {}
  g.survivors, g.zombies = {}, {}
  g.effects, g.decals, g.ruins = {}, {}, {}
  g.messages = {}
  g.selection = {}
  g.res = { food = 35, ammo = 160, scrap = 40 }
  g.stock = { rifle = 4, pistol = 4 }
  g.time, g.speed, g.paused = 0, 1, false
  g.stats = { kills = 0, lost = 0 }
  g.foodRate = 0
  g.foodMult = hqDef.id == "farmhouse" and 1.3 or 1
  g.healRate = hqDef.id == "hospital" and 3 or 1
  g.bleedOut = hqDef.id == "hospital" and 50 or 25
  g.alertMult = hqDef.id == "watertower" and 2 or 1
  g.scrapMult = hqDef.id == "ferriswheel" and 1.5 or 1
  g.luck = hqDef.id == "casino" and 0.35 or 0
  g.learnMult = hqDef.id == "broadcast" and 1.4 or 1
  g.drawList = {}
  g.units = {}

  g:buildSettlement()
  g.groups = {
    Combat = { loadout = "rifle", mobilized = false, rallyX = 27.6, rallyY = 27.6 },
    Agriculture = { loadout = "improvised", mobilized = false, rallyX = 20.6, rallyY = 22.0 },
  }
  for _ = 1, 4 do g:addSurvivor(Survivor.generate("Combat")) end
  for _ = 1, 4 do g:addSurvivor(Survivor.generate("Agriculture")) end

  g.director = Director.new(g)
  g.camera = Iso.newCamera(P(g.hq.cx + 1, g.hq.cy + 1))
  g:renderGround()
  g.map:computeFlow(g.hq)
  g:message("Welcome to " .. hqDef.name .. ". The first wave comes in 75 seconds.")
  g:message("Combat drills at the armory while Agriculture farms. Press F1 for controls.")
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
  self.hq = self:addStructure("hq", 23, 23, { hqId = self.hqDef.id, name = self.hqDef.name,
    desc = "Headquarters. " .. self.hqDef.text .. " If it falls, the settlement is lost." })
  self.garden = self:addStructure("garden", 17, 26)
  self.armory = self:addStructure("armory", 28, 18)

  local towers = {
    [F_MIN .. "," .. F_MIN] = true, [F_MAX .. "," .. F_MIN] = true,
    [F_MIN .. "," .. F_MAX] = true, [F_MAX .. "," .. F_MAX] = true,
    ["23," .. F_MAX] = true, ["26," .. F_MAX] = true,
    [F_MAX .. ",23"] = true, [F_MAX .. ",26"] = true,
  }
  local gates = {
    ["24," .. F_MAX] = true, ["25," .. F_MAX] = true,
    [F_MAX .. ",24"] = true, [F_MAX .. ",25"] = true,
  }
  for cy = F_MIN, F_MAX do
    for cx = F_MIN, F_MAX do
      if cx == F_MIN or cx == F_MAX or cy == F_MIN or cy == F_MAX then
        local key = cx .. "," .. cy
        local dir = (cx == F_MIN or cx == F_MAX) and "y" or "x"
        if towers[key] then
          self:addStructure("tower", cx, cy, { repairable = true })
        elseif gates[key] then
          self:addStructure("gate", cx, cy, { dir = dir, repairable = true })
        else
          self:addStructure("fence", cx, cy, { dir = dir, repairable = true })
        end
      end
    end
  end
  self.hq.repairable = true
  self.armory.repairable = true

  for _, c in ipairs({ { 20, 18 }, { 21, 18 }, { 31, 28 }, { 32, 29 }, { 17, 21 }, { 16, 31 } }) do
    self:addStructure("crates", c[1], c[2], { repairable = false })
  end

  self.lamps = {
    { 23.3, 29.5, 2.2 }, { 26.7, 31.5, 2.2 }, { 29.5, 23.3, 2.2 }, { 31.5, 26.7, 2.2 },
    { 18.0, 19.5, 2.0 }, { 32.5, 17.5, 2.0 }, { 17.0, 32.5, 2.0 },
  }
  self.fires = {
    { 24.3, 30.6, isFire = true }, { 29.0, 25.6, isFire = true }, { 19.6, 21.3, isFire = true },
    { 31.5, 20.5, isFire = true }, { 20.5, 29.5, isFire = true },
  }

  -- light sources that cast unit shadows
  self.shadowLights = {}
  for _, l in ipairs(self.lamps) do self.shadowLights[#self.shadowLights + 1] = { l[1], l[2] } end
  for _, f in ipairs(self.fires) do self.shadowLights[#self.shadowLights + 1] = { f[1], f[2] } end
  for _, s in ipairs(self.structures) do
    if s.kind == "tower" then self.shadowLights[#self.shadowLights + 1] = { s.cx, s.cy } end
  end
end

local function isRoad(cx, cy)
  if (cx == 24 or cx == 25) and cy >= 27 and cy <= MAP_H then return true end
  if (cy == 24 or cy == 25) and cx >= 27 and cx <= MAP_W then return true end
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

  float weeds = smoothstep(0.6, 0.7, fbm(w * 0.45 + 20.0)) * (1.0 - inside * 0.8) * (1.0 - road);
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

function Game:renderGround()
  local w, h = (MAP_W + MAP_H) * Iso.HALF_W, (MAP_W + MAP_H) * Iso.HALF_H
  self.groundOX, self.groundOY = -MAP_H * Iso.HALF_W, 0

  local mask = love.image.newImageData(MAP_W, MAP_H)
  for cy = 1, MAP_H do
    for cx = 1, MAP_W do
      local inside = cx >= F_MIN and cx <= F_MAX and cy >= F_MIN and cy <= F_MAX
      mask:setPixel(cx - 1, cy - 1, isRoad(cx, cy) and 1 or 0, inside and 1 or 0, 0, 1)
    end
  end
  local maskImg = lg.newImage(mask)
  maskImg:setFilter("linear", "linear")
  local shader = lg.newShader(GROUND_SHADER)
  shader:send("canvasSize", { w, h })
  shader:send("isoOffset", { self.groundOX, self.groundOY })
  shader:send("mapSize", { MAP_W, MAP_H })
  shader:send("mask", maskImg)
  local white = lg.newImage(love.image.newImageData(1, 1, "rgba8", string.char(255, 255, 255, 255)))

  local canvas = lg.newCanvas(w, h)
  lg.setCanvas(canvas)
  lg.clear(0, 0, 0, 0)
  lg.push()
  lg.origin()
  lg.setShader(shader)
  lg.setColor(1, 1, 1)
  lg.draw(white, 0, 0, 0, w, h)
  lg.setShader()
  lg.translate(-self.groundOX, -self.groundOY)

  -- wheel ruts along the roads
  lg.setLineWidth(3)
  for _, off in ipairs({ 0.6, 1.4 }) do
    for _, seg in ipairs({ { 23 + off, 27, 23 + off, MAP_H }, { 27, 23 + off, MAP_W, 23 + off } }) do
      local ax, ay = P(seg[1], seg[2])
      local bx, by = P(seg[3], seg[4])
      lg.setColor(0.12, 0.09, 0.06, 0.45)
      lg.line(ax, ay, bx, by)
    end
  end

  -- loose rocks, planks and tyres, each with a little shadow
  for _ = 1, 220 do
    local x, y = 1 + love.math.random() * (MAP_W - 2), 1 + love.math.random() * (MAP_H - 2)
    local sx, sy = P(x, y)
    local r = love.math.random()
    if r < 0.7 then
      local s = 2 + love.math.random() * 4
      lg.setColor(0, 0, 0, 0.45)
      lg.ellipse("fill", sx + s * 0.6, sy + s * 0.25, s * 1.2, s * 0.5)
      local g = 0.22 + love.math.random() * 0.1
      lg.setColor(g, g * 0.88, g * 0.76)
      lg.polygon("fill", sx - s, sy, sx - s * 0.4, sy - s * 0.7, sx + s * 0.6, sy - s * 0.6, sx + s, sy, sx, sy + s * 0.4)
      lg.setColor(g * 1.5, g * 1.35, g * 1.15)
      lg.polygon("fill", sx - s * 0.6, sy - s * 0.2, sx - s * 0.3, sy - s * 0.6, sx + s * 0.4, sy - s * 0.5, sx + s * 0.2, sy - s * 0.1)
    elseif r < 0.88 then
      local a = love.math.random() * math.pi
      local len = 8 + love.math.random() * 10
      lg.push()
      lg.translate(sx, sy)
      lg.rotate(a)
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
  lg.pop()
  lg.setCanvas()
  self.groundCanvas = canvas
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

function Game:workSpot(group)
  if group == "Agriculture" and self.garden then
    local g = self.garden
    return g.wx1 + 0.35 + love.math.random() * (g.w - 0.7), g.wy1 + 0.35 + love.math.random() * (g.h - 0.7)
  end
  if group == "Combat" and not self.armory.dead then
    local a = self.armory
    return a.wx1 + 0.3 + love.math.random() * (a.w - 0.3), a.wy2 + 1.0 + love.math.random() * 1.2
  end
  return self.hq.cx + (love.math.random() - 0.5) * 3, self.hq.wy2 + 1 + love.math.random()
end

function Game:doWork(s, dt)
  local hungry = self.res.food <= 0 and 0.5 or 1
  if s.group == "Agriculture" then
    local rate = 0.07 * (0.6 + s.apt.Agriculture * 0.06 + s.prof.Agriculture * 0.05)
      * s:traitMul("work") * s:traitMul("farm") * self.foodMult * hungry
    self.res.food = self.res.food + rate * dt
    self.production = self.production + rate
    s:learn(self, "Agriculture", 0.004 * dt)
  elseif s.group == "Combat" then
    s:learn(self, "Combat", 0.012 * dt * (0.5 + s.apt.Combat * 0.08) * hungry)
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
  for i = #self.selection, 1, -1 do
    if self.selection[i] == s then table.remove(self.selection, i) end
  end
  self.decals[#self.decals + 1] = { kind = "body", x = s.x, y = s.y, t = 0, life = 9999, col = D.GROUP_COLORS[s.group] }
  self:message(s.name .. " (" .. s.background .. ") has died.", "bad")
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

function Game:spawnZombie(kind, edge)
  local x, y
  local r = U.clamp(edge.center + (love.math.random() - 0.5) * 9, 2, MAP_W - 2)
  if edge.side == "x0" then x, y = 0.5, r
  elseif edge.side == "x1" then x, y = MAP_W - 0.5, r
  elseif edge.side == "y0" then x, y = r, 0.5
  else x, y = r, MAP_H - 0.5 end
  self.zombies[#self.zombies + 1] = Zombie.new(kind, x, y, self.director.wave)
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
  if s.dead then return end
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
    self.ruins[#self.ruins + 1] = { kind = s.kind, x1 = s.x1, y1 = s.y1, dir = s.dir, name = s.name }
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
      local s = self:addStructure(r.kind, r.x1, r.y1, { dir = r.dir, repairable = true })
      if r.kind == "armory" then self.armory = s end
      self.res.scrap = self.res.scrap - REBUILD_COST
      spent = spent + REBUILD_COST
      table.remove(self.ruins, i)
    end
  end
  self.map:computeFlow(self.hq)
  if spent > 0 then self:message("Spent " .. spent .. " scrap on repairs.", "good") end
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
    if not z.dead then
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
  self.over = { reason = reason, wave = self.director.wave }
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
  if phase ~= "alert" and not (phase == "wave" and #self.director.queue > 0) then return end
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

-- A long shadow thrown away from the nearest lamp or fire.
function Game:drawCastShadow(x, y, size)
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

local AMBIENT = { 0.045, 0.045, 0.065 }

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
  G.lights, G.glows = {}, {}

  -- 1. the scene, as if fully lit
  lg.setCanvas({ self.sceneCanvas, stencil = true })
  lg.clear(0.03, 0.025, 0.02, 1)
  cam:apply()
  lg.setColor(1, 1, 1)
  lg.draw(self.groundCanvas, self.groundOX, self.groundOY)
  for _, d in ipairs(self.decals) do drawDecal(d) end
  for _, s in ipairs(self.structures) do
    if s.flat then
      S.draw(s, self.time)
    elseif S.spriteFor(s) then
      S.drawSpriteGround(s)
    else
      G.contactShadow(s.cx, s.cy, (s.w + s.h) * 22, s.kind == "fence" and 0.4 or 0.6)
    end
  end

  local list = self.drawList
  local n = 0
  for _, s in ipairs(self.structures) do
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
    if s.state ~= "dead" then
      s.depth = s.x + s.y
      n = n + 1
      list[n] = s
    end
  end
  for _, z in ipairs(self.zombies) do
    z.depth = z.x + z.y
    n = n + 1
    list[n] = z
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
      S.drawFire(o, self.time)
    else
      G.lampPost(o[1], o[2], o[3])
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

  -- 2. the light map: near-black ambient plus every light queued above
  lg.setCanvas(self.lightCanvas)
  lg.clear(AMBIENT[1], AMBIENT[2], AMBIENT[3], 1)
  cam:apply()
  for _, s in ipairs(self.survivors) do
    if s.state ~= "dead" then
      local sx, sy = P(s.x, s.y, 0)
      G.lightAt(sx, sy - 6, 58, { 1, 0.9, 0.75 }, 0.55, 40)
    end
  end
  for _, e in ipairs(self.effects) do
    if e.kind == "tracer" then
      G.lightAt(e.x1, e.y1 + 8, 110, { 1, 0.8, 0.5 }, 1.2 * (1 - e.t / e.life), 80)
    end
  end
  G.flushLights()
  cam:release()
  lg.setCanvas()

  -- 3. compose: scene x light
  lg.setColor(1, 1, 1)
  lg.draw(self.sceneCanvas)
  lg.setBlendMode("multiply", "premultiplied")
  lg.draw(self.lightCanvas)
  lg.setBlendMode("alpha")

  -- 4. things that give off light, added on top
  cam:apply()
  lg.setBlendMode("add")
  for _, s in ipairs(self.structures) do S.drawEmissive(s, self.time) end
  for _, z in ipairs(self.zombies) do z:drawEyes() end
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

  -- 5. readable overlays, never darkened
  self:drawAlertMarkers()
  if ui.rallyMode then self:drawRally(ui.rallyMode) end
  for _, name in ipairs(D.GROUPS) do
    if self.groups[name].mobilized and ui.rallyMode ~= name then self:drawRally(name) end
  end
  for _, s in ipairs(self.survivors) do
    if s.state ~= "dead" then s:drawOverlay(self:isSelected(s)) end
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
  for _, z in ipairs(self.zombies) do
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
