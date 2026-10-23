-- The survival cycle: Prepare -> Alert -> Wave -> Recover.
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

local FIRST_PREP = 75
local PREP = 55
local ALERT = 15
local RECOVER = 8

function Director.new(game)
  return setmetatable({
    game = game, phase = "prepare", timer = FIRST_PREP, wave = 0,
    queue = {}, spawnT = 0, flowT = 0, edges = {},
  }, Director)
end

function Director:update(dt)
  local g = self.game
  if self.phase == "prepare" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:startAlert(false) end
  elseif self.phase == "alert" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:startWave() end
  elseif self.phase == "wave" then
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
    if #self.queue == 0 and #g.zombies == 0 then self:endWave() end
  elseif self.phase == "recover" then
    self.timer = self.timer - dt
    if self.timer <= 0 then
      self.phase = "prepare"
      self.timer = PREP
      g:message("Prepare. The next wave comes in " .. PREP .. " seconds.")
    end
  end
end

function Director:waveSize()
  return 5 + self.wave * 3
end

function Director:startAlert(early)
  local g = self.game
  self.wave = self.wave + 1
  self.early = early
  self.phase = "alert"
  self.timer = ALERT * g.alertMult
  -- Each approach is a pack arriving at one point along its edge.
  self.edges = {}
  for i, e in ipairs(U.pick(Director.EDGES, self.wave >= 4 and 2 or 1)) do
    self.edges[i] = { name = e.name, side = e.side, center = love.math.random(16, 33) }
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
  g:message(string.format("Scouts: about %d infected approaching from the %s!", count, table.concat(names, " and ")), "alert")
  if early then g:message("Calling the wave early: +50% scrap if you hold.", "good") end
end

function Director:startWave()
  self.phase = "wave"
  self.spawnT = 0
  self.flowT = 0
  self.game:message("Wave " .. self.wave .. ": they're here!", "bad")
end

function Director:endWave()
  local g = self.game
  self.phase = "recover"
  self.timer = RECOVER
  self.queue = {}

  local ammo = 40 + self.wave * 12
  local scrap = (15 + self.wave * 6) * g.scrapMult
  if self.early then scrap = scrap * 1.5 end
  scrap = math.floor(scrap)
  g.res.ammo = g.res.ammo + ammo
  g.res.scrap = g.res.scrap + scrap
  local found = string.format("Wave %d survived! Salvaged %d ammo and %d scrap", self.wave, ammo, scrap)
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
  g:addSurvivor(s, 24.5, 33.0)
  g:message(string.format("%s, a former %s, arrives at the gate and joins %s.", s.name, s.background, s.group), "good")
end

function Director:callEarly()
  if self.phase == "prepare" then self:startAlert(true) end
end

return Director
