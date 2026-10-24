-- The survival cycle: Day -> Dusk -> Night -> Dawn. Days are for scouting,
-- scavenging and repairs; the horde comes at night and the night lasts until
-- it is beaten back.
local U = require("src.util")
local Survivor = require("src.survivor")

local Director = {}
Director.__index = Director

-- Map edges, named by where they sit on screen.
Director.EDGES = {
  { name = "north-west", side = "x0" },
  { name = "north-east", side = "y0" },
  { name = "south-east", side = "x1" },
  { name = "south-west", side = "y1" },
}

local FIRST_DAY = 180
local DAY = 150
local DUSK = 20
local DAWN = 10

function Director.new(game)
  return setmetatable({
    game = game, phase = "day", timer = FIRST_DAY, wave = 0, duskLen = DUSK,
    queue = {}, spawnT = 0, flowT = 0, edges = {},
  }, Director)
end

-- 1 in full day, 0 at night, easing through dusk and dawn.
function Director:daylight()
  local p = self.phase
  local t
  if p == "day" then
    t = 1
  elseif p == "dusk" then
    t = self.timer / self.duskLen
  elseif p == "dawn" then
    t = 1 - self.timer / DAWN
  else
    t = 0
  end
  t = U.clamp(t, 0, 1)
  return t * t * (3 - 2 * t)
end

function Director:isNight()
  return self.phase == "night"
end

function Director:update(dt)
  local g = self.game
  if self.phase == "day" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:startDusk(false) end
  elseif self.phase == "dusk" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:startNight() end
  elseif self.phase == "night" then
    self.spawnT = self.spawnT - dt
    while self.spawnT <= 0 and #self.queue > 0 do
      local e = table.remove(self.queue, 1)
      g:spawnZombie(e.kind, e.edge)
      self.spawnT = self.spawnT + e.gap
    end
    self.flowT = self.flowT - dt
    if self.flowT <= 0 then
      self.flowT = 2
      g.map:computeFlow(g.hq)
    end
    if #self.queue == 0 and g:waveZombieCount() == 0 then self:endWave() end
  elseif self.phase == "dawn" then
    self.timer = self.timer - dt
    if self.timer <= 0 then
      self.phase = "day"
      self.timer = DAY
      g:message(string.format("Day %d. Sunset in %s: scout, scavenge and repair while it's light.",
        self.wave + 1, U.formatTime(DAY)))
    end
  end
end

function Director:waveSize()
  return 5 + self.wave * 3
end

function Director:startDusk(early)
  local g = self.game
  self.wave = self.wave + 1
  self.early = early
  self.phase = "dusk"
  self.duskLen = DUSK * g.alertMult
  self.timer = self.duskLen
  -- Each approach is a pack arriving at one point along its edge.
  self.edges = {}
  for i, e in ipairs(U.pick(Director.EDGES, self.wave >= 4 and 2 or 1)) do
    self.edges[i] = { name = e.name, side = e.side, center = love.math.random(16, 33) + g.B }
  end

  local count = self:waveSize()
  local gap = 18 / count
  self.queue = {}
  for i = 1, count do
    local kind = "walker"
    if self.wave >= 3 and love.math.random() < 0.22 then kind = "runner" end
    if self.wave >= 5 and i % 8 == 0 then kind = "brute" end
    self.queue[i] = { kind = kind, edge = self.edges[i % #self.edges + 1], gap = gap }
  end

  local names = {}
  for i, e in ipairs(self.edges) do names[i] = e.name:upper() end
  g:message(string.format("Sundown. Scouts: about %d infected gathering to the %s!", count, table.concat(names, " and ")), "alert")
  if early then g:message("Calling the night early: +50% scrap if you hold.", "good") end
  local outside = 0
  for _, s in ipairs(g.survivors) do
    if s:isActive() and not g:inWalls(s.x, s.y) then outside = outside + 1 end
  end
  if outside > 0 then
    g:message(string.format("%d survivor%s still outside the walls. Get them home before dark!",
      outside, outside == 1 and " is" or "s are"), "alert")
  end
end

function Director:startNight()
  self.phase = "night"
  self.spawnT = 0
  self.flowT = 0
  self.game:message("Night " .. self.wave .. ": they're here!", "bad")
end

function Director:endWave()
  local g = self.game
  self.phase = "dawn"
  self.timer = DAWN
  self.queue = {}

  local ammo = 40 + self.wave * 12
  local scrap = (15 + self.wave * 6) * g.scrapMult
  if self.early then scrap = scrap * 1.5 end
  scrap = math.floor(scrap)
  g.res.ammo = g.res.ammo + ammo
  g.res.scrap = g.res.scrap + scrap
  local found = string.format("Dawn. Night %d survived! Salvaged %d ammo and %d scrap", self.wave, ammo, scrap)
  if self.wave % 2 == 0 then
    g.stock.rifle = g.stock.rifle + 1
    found = found .. ", plus a rifle"
  end
  g:message(found .. ".", "good")
  if love.math.random() < g.luck then
    local caches = {
      { "60 ammo", function() g.res.ammo = g.res.ammo + 60 end },
      { "a rifle", function() g.stock.rifle = g.stock.rifle + 1 end },
      { "two pistols", function() g.stock.pistol = g.stock.pistol + 2 end },
      { "30 food", function() g.res.food = g.res.food + 30 end },
      { "30 scrap", function() g.res.scrap = g.res.scrap + 30 end },
    }
    local c = U.choice(caches)
    c[2]()
    g:message("Lucky break: survivors found a hidden cache with " .. c[1] .. ".", "good")
  end
  g:reviveDowned()

  local s = Survivor.generate()
  g:addSurvivor(s, g.B + 24.5, g.B + 33.0)
  g:message(string.format("%s, a former %s, arrives at the gate and joins %s.", s.name, s.background, s.group), "good")
end

function Director:callEarly()
  if self.phase == "day" then self:startDusk(true) end
end

return Director
