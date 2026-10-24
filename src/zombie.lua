local U = require("src.util")
local D = require("src.data")
local Iso = require("src.iso")
local Map = require("src.map")
local Units = require("src.units")

local P = Iso.toScreen
local lg = love.graphics

local Zombie = {}
Zombie.__index = Zombie
Zombie.isZombie = true

local SHIRTS = {
  { 0.30, 0.28, 0.24 }, { 0.26, 0.30, 0.34 }, { 0.36, 0.24, 0.20 }, { 0.30, 0.32, 0.22 },
}

function Zombie.new(kind, x, y, wave)
  local def = D.ZOMBIES[kind]
  local z = setmetatable({ kind = kind, def = def, x = x, y = y, depth = x + y }, Zombie)
  z.maxhp = def.hp * (1 + (wave - 1) * 0.07)
  z.hp = z.maxhp
  z.rad = def.radius
  z.speed = def.speed * (0.9 + love.math.random() * 0.2)
  z.cd = 0
  z.retarget = 0
  z.anim = love.math.random() * 10
  z.face = 1
  z.shirt = U.choice(SHIRTS)
  z.look = love.math.random(1, 10)
  return z
end

function Zombie:faceDir(dx, dy)
  local sdx = dx - dy
  if sdx > 0.05 then self.face = 1 elseif sdx < -0.05 then self.face = -1 end
end

-- The town's infected are sluggish and short-sighted by day and restless at night.
function Zombie:aggro(game)
  if not self.home then return self.def.aggro end
  return self.def.aggro * (1.4 - 0.6 * game.director:daylight())
end

function Zombie:update(game, dt)
  self.anim = self.anim + dt
  self.cd = math.max(0, self.cd - dt)
  self.moving = false
  if self.hurtFlash then
    self.hurtFlash = self.hurtFlash - dt
    if self.hurtFlash <= 0 then self.hurtFlash = nil end
  end
  if self.attackAnim then
    self.attackAnim = self.attackAnim - dt
    if self.attackAnim <= 0 then self.attackAnim = nil end
  end

  self.retarget = self.retarget - dt
  if self.retarget <= 0 then
    self.retarget = 0.4 + love.math.random() * 0.3
    local near = game:nearestSurvivor(self.x, self.y, self:aggro(game))
    if near then self.target = near end
  end

  local t = self.target
  if t and not t:isActive() then
    self.target, t = nil, nil
  end
  if t and U.dist(self.x, self.y, t.x, t.y) > self:aggro(game) * 2 then
    self.target, t = nil, nil
  end

  local tx, ty
  if t then
    local d = U.dist(self.x, self.y, t.x, t.y)
    if d <= self.def.radius + 0.45 then
      self:faceDir(t.x - self.x, t.y - self.y)
      if self.cd <= 0 then
        self.cd = self.def.cd
        self.attackAnim = 0.25
        t:hurt(game, self.def.dmg)
      end
      return
    end
    tx, ty = t.x, t.y
  elseif self.home then
    -- the town's infected shuffle around where they were found
    self.wanderT = (self.wanderT or 0) - dt
    if self.wanderT <= 0 or not self.wx then
      self.wanderT = 3 + love.math.random() * 5
      self.wx = self.home[1] + (love.math.random() - 0.5) * 4
      self.wy = self.home[2] + (love.math.random() - 0.5) * 4
    end
    if U.dist(self.x, self.y, self.wx, self.wy) < 0.3 then return end
    self:moveToward(game, self.wx, self.wy, dt * (0.7 - 0.3 * game.director:daylight()))
    return
  else
    local nx, ny = game.map:flowNext(Map.cellOf(self.x, self.y))
    if nx then
      tx, ty = nx - 0.5, ny - 0.5
    else
      tx, ty = game.hq.cx, game.hq.cy
    end
  end
  self:moveToward(game, tx, ty, dt)
end

function Zombie:moveToward(game, tx, ty, dt)
  local dx, dy = tx - self.x, ty - self.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.001 then return end
  dx, dy = dx / d, dy / d
  self:faceDir(dx, dy)
  local map = game.map
  local step = math.min(d, self.speed * dt)
  local nx, ny = self.x + dx * step, self.y + dy * step
  local cx, cy = Map.cellOf(nx, ny)
  if not map:blockedForZombie(cx, cy) then
    self.x, self.y = nx, ny
    self.moving = true
    return
  end
  -- Slide along the obstacle when that still makes real progress; otherwise
  -- start smashing whatever is in the way.
  if math.abs(dx) > 0.5 and not map:blockedForZombie(Map.cellOf(nx, self.y)) then
    self.x = nx
    self.moving = true
    return
  end
  if math.abs(dy) > 0.5 and not map:blockedForZombie(Map.cellOf(self.x, ny)) then
    self.y = ny
    self.moving = true
    return
  end
  local s = map:structure(cx, cy)
  if s and s.solid then
    -- can't smash a whole building: shuffle round it instead
    if not map:blockedForZombie(Map.cellOf(nx, self.y)) then
      self.x = nx
    elseif not map:blockedForZombie(Map.cellOf(self.x, ny)) then
      self.y = ny
    end
    return
  end
  if s and self.cd <= 0 then
    self.cd = self.def.cd
    self.attackAnim = 0.25
    game:damageStructure(s, self.def.structDmg, self.x + dx * 0.4, self.y + dy * 0.4)
  end
end

function Zombie:hurt(game, dmg, by)
  if self.dead then return end
  self.hp = self.hp - dmg
  self.hurtFlash = 0.12
  if by and by:isActive() and U.dist(self.x, self.y, by.x, by.y) < self.def.aggro * 1.6 then
    self.target = by
  end
  if self.hp <= 0 then
    self.dead = true
    game:killZombie(self)
  end
end

function Zombie:headPos()
  local sx, sy = P(self.x, self.y, 0)
  local s = self.kind == "brute" and 1.55 or 1
  local bob = self.moving and math.abs(math.sin(self.anim * (self.kind == "runner" and 13 or 6))) * 1.2 or 0
  local lean = self.face * 2.2 * s
  return sx + lean * 1.35, sy - 14 * s - bob - 2.6 * s, s
end

-- The painted figure's pose this frame: lurching bob and lean.
function Zombie:pose()
  local fast = self.kind == "runner"
  local step = math.sin(self.anim * (fast and 12 or 5))
  local lift = self.moving and math.abs(step) * (fast and 1.8 or 1.1) or 0
  local lean = (self.moving and step * (fast and 0.05 or 0.08) or math.sin(self.anim * 1.3) * 0.03)
    + (fast and 0.12 or 0.05)
  if self.attackAnim then lean = lean + 0.18 end
  return lean, lift, Units.ZOMBIE_H[self.kind] or Units.ZOMBIE_H.walker
end

-- Eyes glow in the dark, so the horde is visible before the lamps reach it.
function Zombie:drawEyes()
  local id = Units.zombieId(self)
  if id then
    local sx, sy = P(self.x, self.y, 0)
    local lean, lift, h = self:pose()
    local hx, hy = Units.headAt(id, sx, sy, self.face, h, lift)
    -- the figure leans about its feet, so the head swings forward with it
    local up = sy - hy
    hx, hy = hx + self.face * up * math.sin(lean), sy - up * math.cos(lean) + h * 0.045
    local ex = hx + self.face * h * 0.03
    lg.setColor(1, 0.18, 0.1, 0.95)
    lg.circle("fill", ex, hy, 0.75)
    lg.circle("fill", ex - self.face * 1.5, hy, 0.6)
    lg.setColor(1, 0.1, 0.05, 0.22)
    lg.circle("fill", ex, hy, 3.2)
    return
  end
  local hx, hy, s = self:headPos()
  local ex = hx + self.face * 1.3 * s
  lg.setColor(1, 0.18, 0.1, 0.95)
  lg.circle("fill", ex, hy - 0.3 * s, 0.9 * s)
  lg.circle("fill", ex - self.face * 1.4 * s, hy - 0.3 * s, 0.7 * s)
  lg.setColor(1, 0.1, 0.05, 0.25)
  lg.circle("fill", ex, hy, 3.5 * s)
end

function Zombie:draw(game)
  local sx, sy = P(self.x, self.y, 0)
  local s = self.kind == "brute" and 1.55 or 1
  local thin = self.kind == "runner" and 0.8 or 1
  game:drawCastShadow(self.x, self.y, s)
  lg.setColor(0, 0, 0, 0.5)
  lg.ellipse("fill", sx, sy, 7 * s, 3.5 * s)

  local id = Units.zombieId(self)
  if id then
    local lean, lift, h = self:pose()
    Units.draw(id, sx, sy, self.face, h, lean, lift, 0, { 0.92, 0.95, 0.9 }, 0.16)
    if self.hurtFlash then Units.flash(id, sx, sy, self.face, h, lean, lift, self.hurtFlash * 5) end
    return
  end

  local speed = self.kind == "runner" and 13 or 6
  local bob = self.moving and math.abs(math.sin(self.anim * speed)) * 1.2 or 0
  local swing = self.moving and math.sin(self.anim * speed) * 2 * s or 0
  local lean = self.face * 2.2 * s

  lg.setColor(0.16, 0.15, 0.13)
  lg.setLineWidth(2 * s)
  lg.line(sx - 1.5 * s, sy - 6 * s, sx - 1.5 * s + swing, sy)
  lg.line(sx + 1.5 * s, sy - 6 * s, sx + 1.5 * s - swing, sy)

  local w = 3.3 * s * thin
  local top = sy - 14 * s - bob
  lg.setColor(self.shirt)
  lg.polygon("fill", sx - w, sy - 6 * s, sx + w, sy - 6 * s, sx + w + lean, top, sx - w + lean, top)
  lg.setColor(0, 0, 0, 0.25)
  lg.polygon("fill", sx, sy - 6 * s, sx + w, sy - 6 * s, sx + w + lean, top, sx + lean, top)

  local reach = self.attackAnim and 3 or 0
  local skin = { 0.62, 0.70, 0.52 }
  lg.setColor(skin)
  lg.setLineWidth(1.6 * s)
  local shx, shy = sx + lean, top + 2 * s
  lg.line(shx, shy, shx + self.face * (6 * s + reach), shy + 1.5 * s)
  lg.line(shx - self.face * 1.5 * s, shy + 1 * s, shx + self.face * (5 * s + reach), shy + 3 * s)
  local hx, hy = sx + lean * 1.35, top - 2.6 * s
  lg.circle("fill", hx, hy, 2.7 * s)

  if self.hurtFlash then
    lg.setColor(1, 1, 1, self.hurtFlash * 4)
    lg.circle("fill", sx, sy - 10 * s, 5 * s)
  end
end

return Zombie
