local U = {}

function U.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

function U.dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

function U.choice(t)
  return t[love.math.random(#t)]
end

function U.shuffle(t)
  for i = #t, 2, -1 do
    local j = love.math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- n distinct random entries from t
function U.pick(t, n)
  local copy = {}
  for i = 1, #t do copy[i] = t[i] end
  U.shuffle(copy)
  local out = {}
  for i = 1, math.min(n, #copy) do out[i] = copy[i] end
  return out
end

function U.inRect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

function U.formatTime(t)
  t = math.max(0, math.ceil(t))
  return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

-- Binary min-heap, used by pathfinding.
local Heap = {}
Heap.__index = Heap

function U.newHeap()
  return setmetatable({ items = {}, keys = {}, n = 0 }, Heap)
end

function Heap:push(item, key)
  local n = self.n + 1
  self.n = n
  local items, keys = self.items, self.keys
  items[n], keys[n] = item, key
  while n > 1 do
    local p = math.floor(n / 2)
    if keys[p] <= keys[n] then break end
    items[p], items[n] = items[n], items[p]
    keys[p], keys[n] = keys[n], keys[p]
    n = p
  end
end

function Heap:pop()
  local n = self.n
  if n == 0 then return nil end
  local items, keys = self.items, self.keys
  local top, topKey = items[1], keys[1]
  items[1], keys[1] = items[n], keys[n]
  items[n], keys[n] = nil, nil
  n = n - 1
  self.n = n
  local i = 1
  while true do
    local l, r, s = i * 2, i * 2 + 1, i
    if l <= n and keys[l] < keys[s] then s = l end
    if r <= n and keys[r] < keys[s] then s = r end
    if s == i then break end
    items[s], items[i] = items[i], items[s]
    keys[s], keys[i] = keys[i], keys[s]
    i = s
  end
  return top, topKey
end

function Heap:empty()
  return self.n == 0
end

return U
