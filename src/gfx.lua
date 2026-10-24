-- Drawing helpers for the code-drawn placeholder art: isometric boxes, roofs,
-- face details and additive amber lighting.
local Iso = require("src.iso")

local G = {}
local lg = love.graphics
local P = Iso.toScreen

G.C = {
  ground = { 0.15, 0.115, 0.085 },
  ground2 = { 0.185, 0.14, 0.10 },
  yard = { 0.23, 0.175, 0.12 },
  road = { 0.29, 0.225, 0.16 },
  rust = { 0.47, 0.27, 0.15 },
  rustDark = { 0.30, 0.17, 0.10 },
  metal = { 0.36, 0.35, 0.33 },
  metalDark = { 0.21, 0.21, 0.20 },
  concrete = { 0.45, 0.42, 0.37 },
  wood = { 0.40, 0.29, 0.18 },
  woodDark = { 0.26, 0.18, 0.11 },
  tarp = { 0.47, 0.43, 0.33 },
  banner = { 0.58, 0.11, 0.10 },
  bone = { 0.90, 0.86, 0.78 },
  amber = { 1.0, 0.66, 0.28 },
  window = { 1.0, 0.74, 0.40 },
  crop = { 0.33, 0.52, 0.20 },
  olive = { 0.29, 0.32, 0.20 },
  outline = { 0.05, 0.04, 0.03, 0.85 },
}
local C = G.C

function G.init()
  local size = 64
  local data = love.image.newImageData(size, size)
  data:mapPixel(function(x, y)
    local dx = (x + 0.5) / size * 2 - 1
    local dy = (y + 0.5) / size * 2 - 1
    local d = math.min(1, math.sqrt(dx * dx + dy * dy))
    return 1, 1, 1, (1 - d) * (1 - d)
  end)
  G.glowImg = lg.newImage(data)

  local vs = 256
  local v = love.image.newImageData(vs, vs)
  v:mapPixel(function(x, y)
    local dx = (x + 0.5) / vs * 2 - 1
    local dy = (y + 0.5) / vs * 2 - 1
    local d = math.sqrt(dx * dx + dy * dy) / 1.414
    local a = math.max(0, (d - 0.4) / 0.6)
    return 0, 0, 0, math.min(1, a * a * 0.95)
  end)
  G.vignetteImg = lg.newImage(v)

  G.font = {
    s = lg.newFont(11),
    m = lg.newFont(13),
    l = lg.newFont(17),
    xl = lg.newFont(28),
    title = lg.newFont(64),
  }
end

function G.setc(col, f, a)
  f = f or 1
  lg.setColor(col[1] * f, col[2] * f, col[3] * f, a or col[4] or 1)
end

-- A flat quad on the ground (or at height z).
function G.flat(x1, y1, x2, y2, col, z)
  z = z or 0
  local ax, ay = P(x1, y1, z)
  local bx, by = P(x2, y1, z)
  local cx, cy = P(x2, y2, z)
  local dx, dy = P(x1, y2, z)
  G.setc(col)
  lg.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
end

-- An axis-aligned box. Only the faces turned toward the camera are drawn:
-- the top, the y = y2 face (lower left) and the x = x2 face (lower right).
function G.box(x1, y1, x2, y2, z0, z1, col, noOutline)
  local ax, ay = P(x1, y2, z0)
  local bx, by = P(x2, y2, z0)
  local cx, cy = P(x2, y1, z0)
  local dx, dy = P(x1, y2, z1)
  local ex, ey = P(x2, y2, z1)
  local fx, fy = P(x2, y1, z1)
  local gx, gy = P(x1, y1, z1)
  G.setc(col, 0.74)
  lg.polygon("fill", ax, ay, bx, by, ex, ey, dx, dy)
  G.setc(col, 0.52)
  lg.polygon("fill", bx, by, cx, cy, fx, fy, ex, ey)
  G.setc(col)
  lg.polygon("fill", gx, gy, fx, fy, ex, ey, dx, dy)
  if not noOutline then
    lg.setColor(C.outline)
    lg.setLineWidth(1)
    lg.polygon("line", ax, ay, bx, by, cx, cy, fx, fy, gx, gy, dx, dy)
    lg.line(dx, dy, ex, ey, fx, fy)
    lg.line(ex, ey, bx, by)
  end
end

-- Gable roof with its ridge running along the x axis.
function G.roofX(x1, y1, x2, y2, z, peak, col)
  local ym, zp = (y1 + y2) / 2, z + peak
  local a = { P(x1, y1, z) }
  local b = { P(x2, y1, z) }
  local c = { P(x2, y2, z) }
  local d = { P(x1, y2, z) }
  local e = { P(x1, ym, zp) }
  local f = { P(x2, ym, zp) }
  G.setc(col, 0.8)
  lg.polygon("fill", a[1], a[2], b[1], b[2], f[1], f[2], e[1], e[2])
  G.setc(col, 0.5)
  lg.polygon("fill", b[1], b[2], c[1], c[2], f[1], f[2])
  G.setc(col)
  lg.polygon("fill", d[1], d[2], c[1], c[2], f[1], f[2], e[1], e[2])
  lg.setColor(C.outline)
  lg.setLineWidth(1)
  lg.polygon("line", d[1], d[2], c[1], c[2], b[1], b[2], f[1], f[2], e[1], e[2])
  lg.line(c[1], c[2], f[1], f[2])
end

-- Gable roof with its ridge running along the y axis.
function G.roofY(x1, y1, x2, y2, z, peak, col)
  local xm, zp = (x1 + x2) / 2, z + peak
  local a = { P(x1, y1, z) }
  local b = { P(x2, y1, z) }
  local c = { P(x2, y2, z) }
  local d = { P(x1, y2, z) }
  local e = { P(xm, y1, zp) }
  local f = { P(xm, y2, zp) }
  G.setc(col, 0.85)
  lg.polygon("fill", a[1], a[2], d[1], d[2], f[1], f[2], e[1], e[2])
  G.setc(col, 0.72)
  lg.polygon("fill", d[1], d[2], c[1], c[2], f[1], f[2])
  G.setc(col, 0.6)
  lg.polygon("fill", b[1], b[2], c[1], c[2], f[1], f[2], e[1], e[2])
  lg.setColor(C.outline)
  lg.setLineWidth(1)
  lg.polygon("line", d[1], d[2], c[1], c[2], b[1], b[2], e[1], e[2], f[1], f[2])
  lg.line(d[1], d[2], f[1], f[2])
end

-- Rectangles painted onto a face of constant y or constant x.
function G.quadY(y, xa, xb, za, zb, col, f)
  local ax, ay = P(xa, y, za)
  local bx, by = P(xb, y, za)
  local cx, cy = P(xb, y, zb)
  local dx, dy = P(xa, y, zb)
  G.setc(col, f)
  lg.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
end

function G.quadX(x, ya, yb, za, zb, col, f)
  local ax, ay = P(x, ya, za)
  local bx, by = P(x, yb, za)
  local cx, cy = P(x, yb, zb)
  local dx, dy = P(x, ya, zb)
  G.setc(col, f)
  lg.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
end

function G.windowY(y, xa, xb, za, zb, lit)
  if lit then
    G.quadY(y, xa, xb, za, zb, C.window, 0.95)
    local sx, sy = P((xa + xb) / 2, y, (za + zb) / 2)
    G.glow(sx, sy, 22, C.amber, 0.35)
    G.lightAt(sx, sy + 8, 46, G.LIGHT, 0.7)
  else
    G.quadY(y, xa, xb, za, zb, { 0.07, 0.06, 0.05 })
  end
end

function G.windowX(x, ya, yb, za, zb, lit)
  if lit then
    G.quadX(x, ya, yb, za, zb, C.window, 0.8)
    local sx, sy = P(x, (ya + yb) / 2, (za + zb) / 2)
    G.glow(sx, sy, 22, C.amber, 0.3)
    G.lightAt(sx, sy + 8, 46, G.LIGHT, 0.6)
  else
    G.quadX(x, ya, yb, za, zb, { 0.07, 0.06, 0.05 })
  end
end

-- The settlement's winged emblem, in screen space.
function G.emblem(cx, cy, s)
  lg.setColor(C.bone)
  lg.polygon("fill", cx, cy + 3 * s, cx - 6 * s, cy - 3 * s, cx - 1.2 * s, cy - 0.6 * s)
  lg.polygon("fill", cx, cy + 3 * s, cx + 6 * s, cy - 3 * s, cx + 1.2 * s, cy - 0.6 * s)
  lg.circle("fill", cx, cy - 2.4 * s, 1.3 * s)
end

function G.bannerY(y, xa, xb, za, zb)
  G.quadY(y, xa, xb, za, zb, C.banner)
  local sx, sy = P((xa + xb) / 2, y, (za + zb) / 2 + 0.05)
  G.emblem(sx, sy, (xb - xa) * 2.6)
end

function G.bannerX(x, ya, yb, za, zb)
  G.quadX(x, ya, yb, za, zb, C.banner, 0.8)
  local sx, sy = P(x, (ya + yb) / 2, (za + zb) / 2 + 0.05)
  G.emblem(sx, sy, (yb - ya) * 2.6)
end

-- Vertical cylinder (tanks, barrels).
function G.cylinder(x, y, r, z0, z1, col)
  local sx, sy0 = P(x, y, z0)
  local _, sy1 = P(x, y, z1)
  local rx, ry = r * 45.25, r * 22.63
  G.setc(col, 0.55)
  lg.ellipse("fill", sx, sy0, rx, ry)
  lg.rectangle("fill", sx - rx, sy1, rx * 2, sy0 - sy1)
  G.setc(col, 0.78)
  lg.rectangle("fill", sx - rx, sy1, rx * 0.95, sy0 - sy1)
  G.setc(col)
  lg.ellipse("fill", sx, sy1, rx, ry)
  lg.setColor(C.outline)
  lg.setLineWidth(1)
  lg.ellipse("line", sx, sy1, rx, ry)
  lg.line(sx - rx, sy1, sx - rx, sy0)
  lg.line(sx + rx, sy1, sx + rx, sy0)
end

function G.shadow(x, y, rx, ry, a)
  local sx, sy = P(x, y, 0)
  lg.setColor(0, 0, 0, a or 0.35)
  lg.ellipse("fill", sx, sy, rx, ry)
end

-- Glows are queued during the scene and drawn together, additively, at the end.
G.glows = {}

function G.glow(sx, sy, r, col, a, flat)
  local g = G.glows
  g[#g + 1] = { sx, sy, r, col[1], col[2], col[3], a or 1, flat }
end

function G.flushGlows()
  lg.setBlendMode("add")
  for _, g in ipairs(G.glows) do
    lg.setColor(g[4], g[5], g[6], g[7] * G.glowScale)
    local s = g[3] / 32
    lg.draw(G.glowImg, g[1], g[2], 0, s, g[8] and s * 0.5 or s, 32, 32)
  end
  lg.setBlendMode("alpha")
  G.glows = {}
end

-- Glow layers of painted art, queued with the same transform as the art and
-- added on top once the darkness has been applied.
G.emissives = {}
G.glowScale = 1 -- dimmed by day, when painted lights hardly show

function G.queueEmissive(img, quad, x, y, sx, sy, ox, oy, ky, a)
  local e = G.emissives
  e[#e + 1] = { img, quad, x, y, sx, sy, ox, oy, ky, a or 1 }
end

function G.flushEmissives()
  lg.setBlendMode("add")
  for _, e in ipairs(G.emissives) do
    lg.setColor(1, 1, 1, e[10] * G.glowScale)
    if e[2] then
      lg.draw(e[1], e[2], e[3], e[4], 0, e[5], e[6], e[7], e[8], 0, e[9])
    else
      lg.draw(e[1], e[3], e[4], 0, e[5], e[6], e[7], e[8], 0, e[9])
    end
  end
  lg.setBlendMode("alpha")
  G.emissives = {}
end

-- Lights are queued during the scene and drawn additively into the light map,
-- which then multiplies the whole scene. Anything left unlit falls to black.
G.lights = {}
G.LIGHT = { 1.0, 0.80, 0.55 }

function G.lightAt(sx, sy, r, col, intensity, ry)
  local l = G.lights
  l[#l + 1] = { sx, sy, r, col[1] * intensity, col[2] * intensity, col[3] * intensity, ry or r * 0.62 }
end

function G.flushLights()
  lg.setBlendMode("add")
  for _, l in ipairs(G.lights) do
    lg.setColor(l[4], l[5], l[6], 1)
    lg.draw(G.glowImg, l[1], l[2], 0, l[3] / 32, l[7] / 32, 32, 32)
  end
  lg.setBlendMode("alpha")
  G.lights = {}
end

-- A lamp: a hot point, a soft bloom, and a pool of light around it.
function G.light(x, y, z, strength, col)
  strength = strength or 1
  local sx, sy = P(x, y, z)
  G.glow(sx, sy, 12 * strength, { 1, 0.92, 0.75 }, 0.95)
  G.glow(sx, sy, 42 * strength, col or C.amber, 0.28)
  local gx, gy = P(x, y, 0)
  G.lightAt(gx, (gy + sy) / 2 + 10, 200 * strength, G.LIGHT, 1.05, 150 * strength)
end

-- Soft dark blob where something meets the ground.
function G.contactShadow(cx, cy, rx, a)
  local sx, sy = P(cx, cy, 0)
  lg.setColor(0, 0, 0, a or 0.55)
  lg.draw(G.glowImg, sx, sy, 0, rx / 32, rx * 0.5 / 32, 32, 32)
end

function G.lampPost(x, y, h)
  local bx, by = P(x, y, 0)
  local tx, ty = P(x, y, h)
  lg.setColor(0.09, 0.08, 0.07)
  lg.setLineWidth(2)
  lg.line(bx, by, tx, ty)
  lg.line(tx, ty, tx + 5, ty - 2)
  G.setc(C.amber)
  lg.rectangle("fill", tx + 1, ty - 5, 8, 5)
  G.light(x, y, h + 0.1, 1)
end

function G.bar(x, y, w, h, frac, col, back)
  lg.setColor(back or { 0, 0, 0, 0.7 })
  lg.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
  G.setc(col)
  lg.rectangle("fill", x, y, w * math.max(0, math.min(1, frac)), h)
end

function G.hpColor(frac)
  if frac > 0.6 then return { 0.45, 0.78, 0.35 } end
  if frac > 0.3 then return { 0.92, 0.70, 0.22 } end
  return { 0.90, 0.25, 0.18 }
end

return G
