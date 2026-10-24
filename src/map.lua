-- Tile grid: which structure sits on each cell, survivor pathfinding (A*)
-- and the zombie flow field (Dijkstra toward the headquarters).
local U = require("src.util")

local Map = {}
Map.__index = Map

local DIRS = {
  { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
  { 1, 1, 1.414 }, { 1, -1, 1.414 }, { -1, 1, 1.414 }, { -1, -1, 1.414 },
}

function Map.new(w, h)
  return setmetatable({ w = w, h = h, structAt = {}, flow = {} }, Map)
end

function Map.cellOf(x, y)
  return math.floor(x) + 1, math.floor(y) + 1
end

function Map:idx(cx, cy)
  return (cy - 1) * self.w + cx
end

function Map:cellXY(i)
  return (i - 1) % self.w + 1, math.floor((i - 1) / self.w) + 1
end

function Map:inBounds(cx, cy)
  return cx >= 1 and cy >= 1 and cx <= self.w and cy <= self.h
end

function Map:structure(cx, cy)
  if not self:inBounds(cx, cy) then return nil end
  return self.structAt[self:idx(cx, cy)]
end

function Map:place(s)
  for cy = s.y1, s.y1 + s.h - 1 do
    for cx = s.x1, s.x1 + s.w - 1 do
      self.structAt[self:idx(cx, cy)] = s
    end
  end
end

function Map:remove(s)
  for cy = s.y1, s.y1 + s.h - 1 do
    for cx = s.x1, s.x1 + s.w - 1 do
      local i = self:idx(cx, cy)
      if self.structAt[i] == s then self.structAt[i] = nil end
    end
  end
end

-- Survivors walk through gates and across flat structures such as crop fields.
function Map:blockedForSurvivor(cx, cy)
  if not self:inBounds(cx, cy) then return true end
  local s = self.structAt[self:idx(cx, cy)]
  return s ~= nil and s.blocking and not s.gate
end

function Map:blockedForZombie(cx, cy)
  if not self:inBounds(cx, cy) then return true end
  local s = self.structAt[self:idx(cx, cy)]
  return s ~= nil and s.blocking
end

function Map:canStep(cx, cy, dx, dy, blocked)
  if blocked(self, cx + dx, cy + dy) then return false end
  if dx ~= 0 and dy ~= 0 then
    -- no squeezing diagonally past a corner
    if blocked(self, cx + dx, cy) or blocked(self, cx, cy + dy) then return false end
  end
  return true
end

function Map:nearestOpen(cx, cy, blocked)
  blocked = blocked or Map.blockedForSurvivor
  if not blocked(self, cx, cy) then return cx, cy end
  for r = 1, 10 do
    local bx, by, bd
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r and not blocked(self, cx + dx, cy + dy) then
          local d = dx * dx + dy * dy
          if not bd or d < bd then bx, by, bd = cx + dx, cy + dy, d end
        end
      end
    end
    if bx then return bx, by end
  end
  return nil
end

-- A* for survivors. Returns a list of world points ending at (tx, ty), or nil.
function Map:findPath(x, y, tx, ty)
  local blocked = Map.blockedForSurvivor
  local sx, sy = Map.cellOf(x, y)
  local gx, gy = Map.cellOf(tx, ty)
  local exact = not blocked(self, gx, gy)
  gx, gy = self:nearestOpen(gx, gy, blocked)
  if not gx then return nil end
  if blocked(self, sx, sy) then
    sx, sy = self:nearestOpen(sx, sy, blocked)
    if not sx then return nil end
  end
  local endX, endY = tx, ty
  if not exact then endX, endY = gx - 0.5, gy - 0.5 end

  local start, goal = self:idx(sx, sy), self:idx(gx, gy)
  if start == goal then return { { endX, endY } } end

  local function h(cx, cy)
    local dx, dy = math.abs(cx - gx), math.abs(cy - gy)
    return math.max(dx, dy) + 0.414 * math.min(dx, dy)
  end

  local open = U.newHeap()
  local g, came, closed = { [start] = 0 }, {}, {}
  open:push(start, h(sx, sy))
  local found, expanded = false, 0
  while not open:empty() do
    local cur = open:pop()
    if cur == goal then found = true break end
    if not closed[cur] then
      closed[cur] = true
      expanded = expanded + 1
      if expanded > 25000 then break end
      local cx, cy = self:cellXY(cur)
      for _, d in ipairs(DIRS) do
        if self:canStep(cx, cy, d[1], d[2], blocked) then
          local nx, ny = cx + d[1], cy + d[2]
          local ni = self:idx(nx, ny)
          local ng = g[cur] + d[3]
          if not closed[ni] and (not g[ni] or ng < g[ni]) then
            g[ni] = ng
            came[ni] = cur
            open:push(ni, ng + h(nx, ny))
          end
        end
      end
    end
  end
  if not found then return nil end

  local cells = {}
  local cur = goal
  while cur ~= start do
    table.insert(cells, 1, cur)
    cur = came[cur]
  end
  local path = {}
  for i, c in ipairs(cells) do
    local cx, cy = self:cellXY(c)
    path[i] = { cx - 0.5, cy - 0.5 }
  end
  path[#path] = { endX, endY }
  return path
end

-- Cost for a zombie to move into a cell: free cells are cheap, structures
-- cost more the sturdier they are, because they have to be smashed first.
-- Solid town buildings can't be smashed at all (nil: impassable).
function Map:enterCost(i, goal)
  local s = self.structAt[i]
  if not s or not s.blocking or s == goal then return 1 end
  if s.solid then return nil end
  return 1 + s.hp / 15
end

function Map:computeFlow(goal)
  local dist = {}
  local heap = U.newHeap()
  for cy = goal.y1, goal.y1 + goal.h - 1 do
    for cx = goal.x1, goal.x1 + goal.w - 1 do
      local i = self:idx(cx, cy)
      dist[i] = 0
      heap:push(i, 0)
    end
  end
  local blocked = Map.blockedForZombie
  while not heap:empty() do
    local cur, d = heap:pop()
    local cost = self:enterCost(cur, goal)
    if cost and d <= dist[cur] then
      local cx, cy = self:cellXY(cur)
      for _, dd in ipairs(DIRS) do
        local nx, ny = cx + dd[1], cy + dd[2]
        if self:inBounds(nx, ny) then
          local ok = true
          if dd[1] ~= 0 and dd[2] ~= 0 then
            ok = not blocked(self, cx + dd[1], cy) and not blocked(self, cx, cy + dd[2])
          end
          local ni = self:idx(nx, ny)
          local ns = self.structAt[ni]
          if ok and not (ns and ns.solid) then
            local nd = d + dd[3] * cost
            if not dist[ni] or nd < dist[ni] then
              dist[ni] = nd
              heap:push(ni, nd)
            end
          end
        end
      end
    end
  end
  self.flow = dist
end

-- The neighbouring cell a zombie standing on (cx, cy) should head for.
function Map:flowNext(cx, cy)
  if not self:inBounds(cx, cy) then return nil end
  local best = self.flow[self:idx(cx, cy)]
  if not best then return nil end
  local bx, by
  local blocked = Map.blockedForZombie
  for _, d in ipairs(DIRS) do
    local nx, ny = cx + d[1], cy + d[2]
    if self:inBounds(nx, ny) then
      local ok = true
      if d[1] ~= 0 and d[2] ~= 0 then
        ok = not blocked(self, cx + d[1], cy) and not blocked(self, cx, cy + d[2])
      end
      local v = ok and self.flow[self:idx(nx, ny)]
      if v and v < best then best, bx, by = v, nx, ny end
    end
  end
  return bx, by
end

return Map
