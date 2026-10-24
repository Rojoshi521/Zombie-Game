local U = require("src.util")
local D = require("src.data")
local Iso = require("src.iso")
local G = require("src.gfx")
local Map = require("src.map")
local Units = require("src.units")

local P = Iso.toScreen
local lg = love.graphics

local Survivor = {}
Survivor.__index = Survivor
Survivor.isSurvivor = true

local nextId = 1

local function rollAptitude()
  -- most people are middling at most things
  return love.math.random(1, 4) + love.math.random(0, 2)
end

-- Background is a weighted influence, not a job lock: a requested group only
-- makes a matching background more likely.
local function pickBackground(group)
  if group and love.math.random() < 0.6 then
    local fits = {}
    for _, bg in ipairs(D.BACKGROUNDS) do
      if bg[2] == group or bg[3] == group then fits[#fits + 1] = bg end
    end
    if #fits > 0 then return U.choice(fits) end
  end
  return U.choice(D.BACKGROUNDS)
end

function Survivor.generate(group)
  local s = setmetatable({}, Survivor)
  local bg = pickBackground(group)
  s.id = nextId
  nextId = nextId + 1
  s.name = U.choice(D.FIRST_NAMES) .. " " .. U.choice(D.LAST_NAMES)
  s.age = love.math.random(19, 64)
  s.background = bg[1]
  s.apt = {}
  for _, a in ipairs(D.APTITUDES) do s.apt[a] = rollAptitude() end
  s.apt[bg[2]] = U.clamp(s.apt[bg[2]] + love.math.random(3, 4), 1, 10)
  s.apt[bg[3]] = U.clamp(s.apt[bg[3]] + love.math.random(1, 3), 1, 10)
  s.attr = {}
  for _, a in ipairs(D.COMBAT_ATTRS) do s.attr[a] = love.math.random(2, 8) end
  if bg[2] == "Combat" or bg[3] == "Combat" then
    s.attr.Accuracy = math.min(10, s.attr.Accuracy + 2)
  end
  s.traits = U.pick(D.TRAITS, 2)
  s.prof = {}
  for _, a in ipairs(D.GROUPS) do s.prof[a] = s.apt[a] * 0.3 end
  s.maxhp = 80 + s.attr.Endurance * 4 + s:traitAdd("hp")
  s.hp = s.maxhp
  s.group = group or s:bestGroup()
  s.skin = U.choice(D.SKIN_TONES)
  s.look = love.math.random(1, 10) -- which portrait of their group they wear
  s.x, s.y, s.depth = 0, 0, 0
  s.rad = 0.22
  s.state = "work"
  s.timer = 0
  s.cd = 0
  s.anim = love.math.random() * 10
  s.face = 1
  return s
end

function Survivor:bestGroup()
  local best, bv = D.GROUPS[1], -1
  for _, g in ipairs(D.GROUPS) do
    if self.apt[g] > bv then best, bv = g, self.apt[g] end
  end
  return best
end

function Survivor:traitAdd(key)
  local v = 0
  for _, t in ipairs(self.traits) do v = v + (t.mods[key] or 0) end
  return v
end

function Survivor:traitMul(key)
  local v = 1
  for _, t in ipairs(self.traits) do v = v * (t.mods[key] or 1) end
  return v
end

function Survivor:isActive()
  return self.state ~= "downed" and self.state ~= "dead"
end

function Survivor:speed()
  local carrying = self.carry and 0.85 or 1
  return 2.1 * (0.85 + self.attr.Mobility * 0.03) * self:traitMul("speed") * carrying
end

function Survivor:vision()
  if self.group == "Scouting" then
    return D.SCOUT_VISION + self.apt.Scouting * 0.15 + self.prof.Scouting * 0.15
  end
  return D.VISION + self.attr.Awareness * 0.1
end

function Survivor:weaponDef(game)
  local w = D.WEAPONS[self.weapon or "fists"]
  if w.ranged and game.res.ammo <= 0 then return D.BASH end
  return w
end

function Survivor:range(game)
  local w = self:weaponDef(game)
  if w.ranged then return w.range + self:traitAdd("range") end
  return w.range
end

function Survivor:hitChance(game, wd)
  local c = 0.40 + self.attr.Accuracy * 0.035 + self.prof.Combat * 0.025 + self:traitAdd("acc")
  if not wd.ranged then c = c + 0.2 end
  local startle = self:traitAdd("startle")
  if startle > 0 and game:nearestZombie(self.x, self.y, 2) then c = c - startle end
  return U.clamp(c, 0.1, 0.95)
end

function Survivor:learn(game, group, amount)
  self.prof[group] = math.min(10, self.prof[group] + amount * self:traitMul("learn") * game.learnMult)
end

----------------------------------------------------------------------------
-- Movement

function Survivor:faceDir(dx, dy)
  local sdx = dx - dy
  if sdx > 0.05 then self.face = 1 elseif sdx < -0.05 then self.face = -1 end
  if math.abs(dx) + math.abs(dy) > 0.001 then self.view, self.viewFace = Units.view(dx, dy) end
end

function Survivor:walkTo(game, tx, ty)
  self.path = game.map:findPath(self.x, self.y, tx, ty)
  self.pathI = 1
  self.atWork = false
  return self.path ~= nil
end

-- Returns true once the end of the current path has been reached.
function Survivor:stepPath(dt)
  if not self.path then return true end
  local p = self.path[self.pathI]
  if not p then
    self.path = nil
    return true
  end
  local dx, dy = p[1] - self.x, p[2] - self.y
  local d = math.sqrt(dx * dx + dy * dy)
  local step = self:speed() * dt
  self.moving = true
  if d <= step then
    self.x, self.y = p[1], p[2]
    self.pathI = self.pathI + 1
    if self.pathI > #self.path then
      self.path = nil
      return true
    end
  else
    self.x, self.y = self.x + dx / d * step, self.y + dy / d * step
    self:faceDir(dx, dy)
  end
  return false
end

function Survivor:stepToward(game, tx, ty, dt)
  self.path = nil
  local dx, dy = tx - self.x, ty - self.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.01 then return end
  local step = self:speed() * dt
  local nx, ny = self.x + dx / d * step, self.y + dy / d * step
  if not game.map:blockedForSurvivor(Map.cellOf(nx, ny)) then
    self.x, self.y = nx, ny
    self.moving = true
  end
  self:faceDir(dx, dy)
end

----------------------------------------------------------------------------
-- High-level transitions

function Survivor:goWork()
  self.state = "work"
  self.timer = 0
  self.path = nil
  self.order = nil
  self.focus = nil
  self.atWork = false
end

function Survivor:mobilize(game)
  self.order, self.focus, self.path = nil, nil, nil
  if self.weapon then
    self:goRally(game)
    return
  end
  self.state = "react"
  self.timer = 0.3 + love.math.random() * 0.5 + self:traitAdd("react")
end

function Survivor:goArmory(game)
  local ax, ay = game:armorySlot(self)
  if ax and self:walkTo(game, ax, ay) then
    self.state = "toArmory"
  else
    self:goRally(game)
  end
end

function Survivor:goRally(game)
  self.order, self.focus = nil, nil
  local rx, ry = game:rallySlot(self)
  self.guardX, self.guardY = rx, ry
  if self:walkTo(game, rx, ry) then
    self.state = "toRally"
  else
    self.state = "squad"
    self.guardX, self.guardY = self.x, self.y
  end
end

function Survivor:returnToWork(game)
  self.order, self.focus = nil, nil
  if self.weapon and self.weapon ~= "improvised" then
    local ax, ay = game:armorySlot(self)
    if ax and self:walkTo(game, ax, ay) then
      self.state = "toStore"
      return
    end
  end
  if self.weapon == "improvised" then self.weapon = nil end
  self:goWork()
end

function Survivor:hurt(game, dmg)
  if not self:isActive() then return end
  self.hp = self.hp - dmg * self:traitMul("dmgTaken")
  self.hurtFlash = 0.2
  if self.hp <= 0 then
    self.hp = 0
    self.state = "downed"
    self.downTimer = game.bleedOut
    self.calm, self.rescueT = 0, 0
    self.path, self.order, self.focus = nil, nil, nil
    if game:inWalls(self.x, self.y) then
      game:message(self.name .. " is down! They have " .. game.bleedOut .. "s unless the night ends or someone reaches them.", "bad")
    else
      game:message(self.name .. " is down in the town! Get someone to them within " .. game.bleedOut .. "s.", "bad")
    end
  end
end

----------------------------------------------------------------------------
-- Update

function Survivor:update(game, dt)
  self.anim = self.anim + dt
  self.moving = false
  self.cd = math.max(0, self.cd - dt)
  if self.hurtFlash then
    self.hurtFlash = self.hurtFlash - dt
    if self.hurtFlash <= 0 then self.hurtFlash = nil end
  end
  if self.attackAnim then
    self.attackAnim = self.attackAnim - dt
    if self.attackAnim <= 0 then self.attackAnim = nil end
  end

  if self.state == "dead" then return end
  if self.state == "downed" then
    -- Outside the walls, or at night, the downed bleed out. Safe inside by
    -- day, they come round on their own.
    if game.director:isNight() or not game:inWalls(self.x, self.y) then
      self.downTimer = self.downTimer - dt
      if self.downTimer <= 0 then
        game:killSurvivor(self)
        return
      end
    else
      self.calm = (self.calm or 0) + dt
      if self.calm >= 12 then game:rescue(self) return end
    end
    -- a friend kneeling beside them, with no infected close, pulls them up
    if game:nearestSurvivor(self.x, self.y, 1.1) and not game:nearestZombie(self.x, self.y, 2.5) then
      self.rescueT = (self.rescueT or 0) + dt
      if self.rescueT >= 3 then game:rescue(self) end
    else
      self.rescueT = 0
    end
    return
  end

  if self.carry and game:inWalls(self.x, self.y) then game:deliver(self) end

  local phase = game.director.phase
  if phase ~= "night" and self.hp < self.maxhp and game.res.food > 0 then
    self.hp = math.min(self.maxhp, self.hp + 0.8 * game.healRate * dt)
  end
  if game.res.food <= 0 then
    self.hp = math.max(1, self.hp - 0.25 * dt)
  end

  local st = self.state
  if st == "work" then
    self:updateWork(game, dt)
  elseif st == "react" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:goArmory(game) end
  elseif st == "toArmory" then
    if self:stepPath(dt) then
      self.state = "arming"
      self.timer = 1.4 * self:traitMul("arm")
    end
  elseif st == "arming" then
    self.timer = self.timer - dt
    if self.timer <= 0 then
      game:issueWeapon(self)
      self:goRally(game)
    end
  elseif st == "toRally" then
    if self:stepPath(dt) then
      self.state = "squad"
      self.guardX, self.guardY = self.x, self.y
    end
  elseif st == "squad" then
    self:updateSquad(game, dt)
  elseif st == "toStore" then
    if self:stepPath(dt) then
      game:storeWeapon(self)
      self:goWork()
    end
  end
end

function Survivor:updateWork(game, dt)
  local threat = game:nearestZombie(self.x, self.y, 1.2)
  if threat then
    self:attack(game, threat)
    return
  end
  if self.path then
    if self:stepPath(dt) then self.atWork = true end
    return
  end
  self.timer = self.timer - dt
  if self.timer <= 0 then
    self.timer = love.math.random(6, 11)
    local tx, ty = game:workSpot(self.group)
    if tx and self:walkTo(game, tx, ty) then return end
  end
  if self.atWork then game:doWork(self, dt) end
end

function Survivor:updateSquad(game, dt)
  local o = self.order
  if o and o.kind == "move" then
    if self:stepPath(dt) then
      self.order = nil
      self.guardX, self.guardY = self.x, self.y
    end
    return
  end
  if o and o.kind == "search" then
    if o.site.site.searched then
      self.order = nil
      return
    end
    if self.path then
      self:stepPath(dt)
      return
    end
    -- at the door: fight off anything that comes close, otherwise search
    local threat = game:nearestZombie(self.x, self.y, 1.6)
    if threat then
      self:attack(game, threat)
    else
      game:searchTick(self, o.site, dt)
    end
    return
  end

  local hold = o and o.kind == "hold"
  if self.focus and self.focus.dead then self.focus = nil end
  local wd = self:weaponDef(game)
  local range = self:range(game)
  -- Units on guard pick up anything that comes near and close to weapon
  -- range, but stay leashed to their post. Hold position never moves.
  local search = range + 0.3
  if not hold then search = math.max(range + 3, 4) end

  local target = self.focus or game:nearestZombie(self.x, self.y, search)
  if target then
    local d = U.dist(self.x, self.y, target.x, target.y)
    local gx, gy = self.guardX or self.x, self.guardY or self.y
    if d <= range + target.def.radius then
      self:attack(game, target)
      return
    elseif not hold and (self.focus or U.dist(target.x, target.y, gx, gy) < range + 6) then
      self:stepToward(game, target.x, target.y, dt)
      return
    end
  end

  if o and o.kind == "amove" then
    if self:stepPath(dt) then
      self.order = nil
      self.guardX, self.guardY = self.x, self.y
    end
    return
  end

  -- drift back to the guard post after chasing something
  if not hold and self.guardX and U.dist(self.x, self.y, self.guardX, self.guardY) > 0.6 then
    if not self.path then self:walkTo(game, self.guardX, self.guardY) end
    self:stepPath(dt)
  end
end

function Survivor:attack(game, z)
  self:faceDir(z.x - self.x, z.y - self.y)
  if self.cd > 0 then return end
  local wd = self:weaponDef(game)
  self.cd = wd.cd * self:traitMul("cd")
  if wd.ranged then
    game.res.ammo = math.max(0, game.res.ammo - 1)
    if love.math.random() < self:traitAdd("waste") then
      game.res.ammo = math.max(0, game.res.ammo - 1)
    end
    game:noise(self.x, self.y, 10, self)
  end
  local hit = love.math.random() < self:hitChance(game, wd)
  game:attackFx(self, z, wd, hit)
  if hit then
    local dmg = wd.dmg * (0.9 + self.prof.Combat * 0.03 + self.attr.Handling * 0.01)
    z:hurt(game, dmg, self)
  end
  self:learn(game, "Combat", 0.02)
  self.attackAnim = 0.15
end

function Survivor:stateLabel()
  local st = self.state
  if st == "work" then return self.atWork and "Working" or "Walking to work" end
  if st == "react" then return "Alarm!" end
  if st == "toArmory" then return "To armory" end
  if st == "arming" then return "Gearing up" end
  if st == "toRally" then return "To rally point" end
  if st == "toStore" then return "Storing gear" end
  if st == "downed" then return string.format("DOWN (%ds)", math.ceil(self.downTimer)) end
  if st == "dead" then return "Dead" end
  local o = self.order
  if o and o.kind == "search" then return self.path and "Heading out" or "Searching" end
  if o and o.kind == "move" then return "Moving" end
  if o and o.kind == "amove" then return "Attack-moving" end
  if o and o.kind == "hold" then return "Holding" end
  if self.focus then return "Focus fire" end
  return "On guard"
end

----------------------------------------------------------------------------
-- Drawing

function Survivor:draw(game)
  local sx, sy = P(self.x, self.y, 0)
  local col = D.GROUP_COLORS[self.group]
  game:drawCastShadow(self.x, self.y, 1)
  lg.setColor(0, 0, 0, 0.5)
  lg.ellipse("fill", sx, sy, 7, 3.5)

  local id, walk = Units.survivorId(self)
  if id then
    -- the group's colour as a faint mark on the ground
    G.setc(col, 0.55)
    lg.setLineWidth(1.5)
    lg.ellipse("line", sx, sy, 6.5, 3.2)
    local h = Units.SURVIVOR_H
    if walk then
      -- the sheet's frames carry the stride; just a slight dip on each step
      if self.state == "downed" then
        id = Units.WALK_SET[self.group] .. "_side1"
        Units.draw(id, sx - self.face * 4, sy, self.face, h, 0, 0, 1, { 0.75, 0.7, 0.68 }, 0.35)
        return
      end
      local face = self.viewFace or self.face
      local lift = self.moving and math.abs(math.cos(self.anim * 10)) * 1.2 or 0
      local lean = self.attackAnim and 0.08 or 0
      Units.draw(id, sx, sy, face, h, lean, lift, 0, nil, 0.35)
      if self.hurtFlash then Units.flash(id, sx, sy, face, h, lean, lift, self.hurtFlash * 4) end
      return
    end
    if self.state == "downed" then
      Units.draw(id, sx - self.face * 4, sy, self.face, h, 0, 0, 1, { 0.75, 0.7, 0.68 }, 0.35)
      return
    end
    local step = math.sin(self.anim * 10)
    local lift = self.moving and math.abs(step) * 1.6 or 0
    local lean = self.moving and step * 0.05 + 0.04 or 0
    if self.attackAnim then lean = lean + 0.12 end
    Units.draw(id, sx, sy, self.face, h, lean, lift, 0, nil, 0.35)
    if self.hurtFlash then Units.flash(id, sx, sy, self.face, h, lean, lift, self.hurtFlash * 4) end
    return
  end

  if self.state == "downed" then
    G.setc(col, 0.6)
    lg.rectangle("fill", sx - 7, sy - 4, 11, 4)
    lg.setColor(self.skin)
    lg.circle("fill", sx + 6, sy - 2, 2.6)
    return
  end

  local bob = self.moving and math.abs(math.sin(self.anim * 10)) * 1.2 or 0
  local swing = self.moving and math.sin(self.anim * 10) * 2.2 or 0
  lg.setColor(0.13, 0.12, 0.11)
  lg.setLineWidth(2)
  lg.line(sx - 1.5, sy - 6 - bob, sx - 1.5 + swing, sy)
  lg.line(sx + 1.5, sy - 6 - bob, sx + 1.5 - swing, sy)
  G.setc(col)
  lg.rectangle("fill", sx - 3.5, sy - 14 - bob, 7, 8.5, 1.5)
  lg.setColor(0, 0, 0, 0.25)
  lg.rectangle("fill", sx + 0.5, sy - 14 - bob, 3, 8.5)
  lg.setColor(self.skin)
  lg.circle("fill", sx, sy - 17 - bob, 2.8)

  if self.weapon then
    local hx, hy = sx + self.face * 3, sy - 10 - bob
    lg.setColor(0.1, 0.1, 0.1)
    if self.weapon == "improvised" then
      local raise = self.attackAnim and 5 or 0
      lg.setLineWidth(1.8)
      lg.line(hx, hy, hx + self.face * (4 + raise), hy - 7 + raise)
    else
      local len = self.weapon == "rifle" and 10 or 5
      lg.setLineWidth(2)
      lg.line(hx - self.face * 2, hy + 1, hx + self.face * len, hy - 1)
    end
  end

  if self.hurtFlash then
    lg.setColor(1, 0.2, 0.1, self.hurtFlash * 3)
    lg.circle("fill", sx, sy - 12, 6)
  end
end

-- Selection ring and the downed marker stay readable in the dark.
function Survivor:drawOverlay(selected)
  local sx, sy = P(self.x, self.y, 0)
  if selected then
    lg.setColor(0.45, 1, 0.5, 0.95)
    lg.setLineWidth(1.5)
    lg.ellipse("line", sx, sy, 10, 5)
  end
  if self.state == "downed" then
    local pulse = 0.5 + 0.5 * math.sin(self.anim * 6)
    lg.setColor(1, 0.2, 0.15, 0.5 + pulse * 0.5)
    lg.rectangle("fill", sx - 1.5, sy - 20, 3, 9)
    lg.rectangle("fill", sx - 4.5, sy - 17, 9, 3)
  end
end

return Survivor
