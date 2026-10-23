-- World space is measured in tiles: x grows toward the lower right of the
-- screen, y toward the lower left, z straight up.
local Iso = {}

Iso.HALF_W = 32
Iso.HALF_H = 16
Iso.Z = 28

function Iso.toScreen(x, y, z)
  return (x - y) * Iso.HALF_W, (x + y) * Iso.HALF_H - (z or 0) * Iso.Z
end

function Iso.toWorld(sx, sy)
  local a, b = sx / Iso.HALF_W, sy / Iso.HALF_H
  return (a + b) / 2, (b - a) / 2
end

local Camera = {}
Camera.__index = Camera

function Iso.newCamera(x, y)
  return setmetatable({ x = x, y = y, zoom = 1 }, Camera)
end

function Camera:apply()
  local w, h = love.graphics.getDimensions()
  love.graphics.push()
  love.graphics.translate(math.floor(w / 2), math.floor(h / 2))
  love.graphics.scale(self.zoom)
  love.graphics.translate(-self.x, -self.y)
end

function Camera:release()
  love.graphics.pop()
end

function Camera:screenToIso(mx, my)
  local w, h = love.graphics.getDimensions()
  return (mx - math.floor(w / 2)) / self.zoom + self.x, (my - math.floor(h / 2)) / self.zoom + self.y
end

function Camera:isoToScreen(ix, iy)
  local w, h = love.graphics.getDimensions()
  return (ix - self.x) * self.zoom + math.floor(w / 2), (iy - self.y) * self.zoom + math.floor(h / 2)
end

function Camera:screenToWorld(mx, my)
  return Iso.toWorld(self:screenToIso(mx, my))
end

function Camera:worldToScreen(x, y, z)
  return self:isoToScreen(Iso.toScreen(x, y, z))
end

function Camera:zoomAt(mx, my, factor)
  local bx, by = self:screenToIso(mx, my)
  self.zoom = math.max(0.45, math.min(2.2, self.zoom * factor))
  local ax, ay = self:screenToIso(mx, my)
  self.x = self.x + (bx - ax)
  self.y = self.y + (by - ay)
end

return Iso
