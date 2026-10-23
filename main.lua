local D = require("src.data")
local G = require("src.gfx")
local S = require("src.structures")
local UI = require("src.ui")
local Game = require("src.game")

local lg = love.graphics

local screen = "menu"
local game
local drag -- left-drag selection box, in screen space
local panning -- middle-drag camera pan
local lastKey, lastKeyTime = nil, 0
local menuTime = 0
local autotest

local function startGame(hqDef)
  game = Game.new(hqDef)
  UI.tab, UI.rallyMode, UI.amove, UI.help = "Combat", nil, false, false
  screen = "game"
end

UI.onRestart = function()
  game = nil
  screen = "menu"
end

----------------------------------------------------------------------------
-- Menu

local function drawMenu()
  local w, h = lg.getDimensions()
  UI.beginFrame()
  lg.clear(0.03, 0.025, 0.02)
  lg.setColor(1, 1, 1)
  lg.draw(G.vignetteImg, 0, 0, 0, w / 256, h / 256)

  local top = math.max(16, h * 0.04)
  UI.text("SURVIVOR RTS", 0, top, G.font.title, UI.COL.amber, w, "center")
  UI.text("A living settlement. Ten working groups. One shared fight for survival.",
    0, top + 74, G.font.l, UI.COL.dim, w, "center")
  UI.text("Choose the ruined landmark that becomes your headquarters", 0, top + 104, G.font.m, UI.COL.text, w, "center")

  local cols = 3
  local gap = 18
  local y0 = top + 132
  local cw = math.min(420, (w - 80 - gap * (cols - 1)) / cols)
  local ch = math.min(330, (h - y0 - 50 - gap) / 2)
  local x0 = (w - (cols * cw + (cols - 1) * gap)) / 2
  local mx, my = love.mouse.getPosition()
  for i, hq in ipairs(D.HQS) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = x0 + col * (cw + gap), y0 + row * (ch + gap)
    local hover = mx >= x and mx <= x + cw and my >= y and my <= y + ch
    lg.setColor(hover and { 0.12, 0.10, 0.085, 0.97 } or { 0.07, 0.062, 0.055, 0.95 })
    lg.rectangle("fill", x, y, cw, ch, 4)
    lg.setColor(hover and UI.COL.amber or UI.COL.border)
    lg.setLineWidth(hover and 2 or 1)
    lg.rectangle("line", x + 0.5, y + 0.5, cw - 1, ch - 1, 4)

    local art = ch - 128
    lg.setScissor(x + 2, y + 2, cw - 4, art + 8)
    S.drawPreview(hq.id, x + cw / 2, y + 8 + art / 2, math.min(cw - 30, art * 1.45), menuTime)
    lg.setScissor()

    UI.text(hq.name, x, y + art + 14, G.font.l, UI.COL.text, cw, "center")
    UI.text("Passive: " .. hq.passive, x, y + art + 37, G.font.m, UI.COL.amber, cw, "center")
    UI.text(hq.text, x + 18, y + art + 57, G.font.s, UI.COL.dim, cw - 36, "center")
    UI.button(x + cw / 2 - 70, y + ch - 36, 140, 28, "Settle here", function() startGame(hq) end,
      { active = hover })
  end

  UI.text("Prototype build: Combat and Agriculture groups, one farm and one armory. F1 in game for controls.",
    0, h - 34, G.font.s, UI.COL.dim, w, "center")
end

----------------------------------------------------------------------------
-- Callbacks

-- In autotest runs, print crashes to the console and quit instead of
-- waiting on the error screen.
local defaultErrorHandler = love.errorhandler
function love.errorhandler(msg)
  if autotest then
    print(debug.traceback("Error: " .. tostring(msg), 3))
    return function() return 1 end
  end
  return defaultErrorHandler(msg)
end

-- Debug view: every painted sprite at game scale over its 4x4 footprint.
local calibrate = false

local function drawCalibration()
  local Iso = require("src.iso")
  lg.clear(0.12, 0.12, 0.14)
  local ids = {}
  for id in pairs(D.SPRITES) do ids[#ids + 1] = id end
  table.sort(ids)
  for i, id in ipairs(ids) do
    local sp = S.sprites[id]
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local cx, cy = 200 + col * 400, 260 + row * 420
    local k = sp.def.scale
    lg.setColor(1, 1, 1)
    lg.draw(sp.img, cx - sp.def.ax * k, cy - sp.def.ay * k, 0, k, k)
    local pts = {}
    for _, c in ipairs({ { -2, -2 }, { 2, -2 }, { 2, 2 }, { -2, 2 } }) do
      local x, y = Iso.toScreen(c[1], c[2])
      pts[#pts + 1] = cx + x
      pts[#pts + 1] = cy + y
    end
    lg.setColor(0, 1, 0.3)
    lg.setLineWidth(2)
    lg.polygon("line", pts)
    lg.setColor(1, 0, 1)
    lg.circle("fill", cx, cy, 3)
    UI.text(id, cx - 100, cy + 150, G.font.m, { 1, 1, 1 }, 200, "center")
  end
end

function love.load(args)
  love.graphics.setDefaultFilter("linear", "linear")
  G.init()
  S.loadSprites()
  for i, a in ipairs(args or {}) do
    if a == "--calibrate" then calibrate = true end
    if a == "--autotest" then autotest = { t = 0, step = 1, hq = D.HQS[1] } end
    if a == "--hq" and autotest then
      for _, hq in ipairs(D.HQS) do
        if hq.id == args[i + 1] then autotest.hq = hq end
      end
    end
    if a == "--process-art" then
      require("tools.process_art")(args[i + 1])
      love.event.quit()
      return
    end
  end
end

local function updateCamera(dt)
  local cam = game.camera
  local w, h = lg.getDimensions()
  local speed = 700 * dt / cam.zoom
  local dx, dy = 0, 0
  if love.keyboard.isDown("left") then dx = dx - 1 end
  if love.keyboard.isDown("right") then dx = dx + 1 end
  if love.keyboard.isDown("up") then dy = dy - 1 end
  if love.keyboard.isDown("down") then dy = dy + 1 end
  if love.window.hasMouseFocus() and not panning and not autotest then
    local mx, my = love.mouse.getPosition()
    if mx <= 3 then dx = dx - 1 elseif mx >= w - 4 then dx = dx + 1 end
    if my <= 3 then dy = dy - 1 elseif my >= h - 4 then dy = dy + 1 end
  end
  cam.x = cam.x + dx * speed
  cam.y = cam.y + dy * speed
  cam.x = math.max(-48 * 32, math.min(48 * 32, cam.x))
  cam.y = math.max(0, math.min(96 * 16, cam.y))
end

local function runAutotest(dt)
  local a = autotest
  a.t = a.t + dt
  local steps = {
    { 0.6, function() lg.captureScreenshot("shot_menu.png") end },
    { 0.8, function() startGame(a.hq) end },
    { 2.0, function()
      game.selection = { game.survivors[1] }
      lg.captureScreenshot("shot_base.png")
    end },
    { 2.4, function()
      game.selection = {}
      game.speed = 3
      game.director.timer = 2
    end },
    { 3.2, function()
      game:setMobilized("Combat", true)
      lg.captureScreenshot("shot_alert.png")
    end },
    { 13, function()
      game.camera.zoom = 1.4
      lg.captureScreenshot("shot_wave.png")
    end },
    { 22, function()
      game.camera.zoom = 1
      lg.captureScreenshot("shot_wave2.png")
    end },
    { 30, function()
      a.report()
      lg.captureScreenshot("shot_late.png")
    end },
    { 45, function()
      a.report()
      game:setMobilized("Combat", false)
    end },
    { 60, function()
      a.report()
      lg.captureScreenshot("shot_after.png")
    end },
    { 61, function() love.event.quit() end },
  }
  a.report = function()
    local states = {}
    for _, s in ipairs(game.survivors) do states[#states + 1] = s.state end
    print(string.format("AUTOTEST t=%.0f phase=%s wave=%d zombies=%d kills=%d living=%d food=%.1f ammo=%d scrap=%d rifles=%d over=%s states=%s",
      game.time, game.director.phase, game.director.wave, #game.zombies, game.stats.kills, game:livingCount(),
      game.res.food, game.res.ammo, game.res.scrap, game.stock.rifle, tostring(game.over and game.over.reason),
      table.concat(states, ",")))
  end
  local s = steps[a.step]
  if s and a.t >= s[1] then
    s[2]()
    a.step = a.step + 1
  end
end

function love.update(dt)
  dt = math.min(dt, 1 / 20)
  menuTime = menuTime + dt
  if autotest then runAutotest(dt) end
  if screen == "game" and game then
    updateCamera(dt)
    game:update(dt)
  end
end

function love.draw()
  if calibrate then
    drawCalibration()
    if menuTime > 0.5 then
      lg.captureScreenshot("calibrate.png")
      calibrate = false
      love.event.quit()
    end
    return
  end
  if screen == "menu" then
    drawMenu()
    return
  end
  game:draw(UI)
  if drag then
    local x, y = math.min(drag.x0, drag.x1), math.min(drag.y0, drag.y1)
    local w, h = math.abs(drag.x1 - drag.x0), math.abs(drag.y1 - drag.y0)
    if w > 4 or h > 4 then
      lg.setColor(0.45, 1, 0.5, 0.12)
      lg.rectangle("fill", x, y, w, h)
      lg.setColor(0.45, 1, 0.5, 0.8)
      lg.setLineWidth(1)
      lg.rectangle("line", x + 0.5, y + 0.5, w, h)
    end
  end
  UI.draw(game)
end

function love.mousepressed(x, y, b)
  if screen == "menu" then
    UI.mousepressed(x, y, b)
    return
  end
  if UI.mousepressed(x, y, b) then return end
  if game.over then return end

  if b == 3 then
    panning = { x = x, y = y }
    return
  end
  if b == 2 then
    if UI.rallyMode or UI.amove then
      UI.rallyMode, UI.amove = nil, false
      return
    end
    local z = game:zombieAt(x, y)
    if z then
      game:orderFocus(z)
    else
      local wx, wy = game.camera:screenToWorld(x, y)
      game:orderMove(wx, wy, "move")
    end
    return
  end
  if b == 1 then
    local wx, wy = game.camera:screenToWorld(x, y)
    if UI.rallyMode then
      local grp = game.groups[UI.rallyMode]
      grp.rallyX, grp.rallyY = wx, wy
      if grp.mobilized then
        for _, s in ipairs(game:groupMembers(UI.rallyMode, true)) do
          if s.state == "squad" or s.state == "toRally" then s:goRally(game) end
        end
      end
      game:message(UI.rallyMode .. " rally point set.")
      UI.rallyMode = nil
      return
    end
    if UI.amove then
      game:orderMove(wx, wy, "amove")
      UI.amove = false
      return
    end
    drag = { x0 = x, y0 = y, x1 = x, y1 = y }
  end
end

function love.mousemoved(x, y, dx, dy)
  if drag then drag.x1, drag.y1 = x, y end
  if panning and game then
    game.camera.x = game.camera.x - dx / game.camera.zoom
    game.camera.y = game.camera.y - dy / game.camera.zoom
  end
end

function love.mousereleased(x, y, b)
  if b == 3 then panning = nil end
  if b ~= 1 or not drag or not game then
    drag = nil
    return
  end
  local add = love.keyboard.isDown("lshift", "rshift")
  local x0, y0 = math.min(drag.x0, x), math.min(drag.y0, y)
  local x1, y1 = math.max(drag.x0, x), math.max(drag.y0, y)
  drag = nil
  if not add then game.selection = {} end
  if x1 - x0 < 5 and y1 - y0 < 5 then
    local s = game:survivorAt(x, y)
    if s and not game:isSelected(s) then game.selection[#game.selection + 1] = s end
    if s then UI.tab = s.group end
    return
  end
  local cam = game.camera
  for _, s in ipairs(game.survivors) do
    if s:isActive() and not game:isSelected(s) then
      local sx, sy = cam:worldToScreen(s.x, s.y, 0)
      sy = sy - 8 * cam.zoom
      if sx >= x0 and sx <= x1 and sy >= y0 and sy <= y1 then
        game.selection[#game.selection + 1] = s
      end
    end
  end
end

function love.wheelmoved(dx, dy)
  if screen ~= "game" or not game then return end
  local mx, my = love.mouse.getPosition()
  game.camera:zoomAt(mx, my, dy > 0 and 1.12 or 1 / 1.12)
end

function love.keypressed(key)
  if screen ~= "game" then
    if key == "escape" then love.event.quit() end
    return
  end
  if game.over then return end
  local now = love.timer.getTime()
  local double = key == lastKey and now - lastKeyTime < 0.35
  lastKey, lastKeyTime = key, now

  if key == "space" then
    game.paused = not game.paused
  elseif key == "escape" then
    if UI.help then UI.help = false
    elseif UI.rallyMode or UI.amove then UI.rallyMode, UI.amove = nil, false
    else game.selection = {} end
  elseif key == "f1" or key == "/" then
    UI.help = not UI.help
  elseif key == "a" then
    if #game:selectedActive() > 0 then UI.amove = true end
  elseif key == "h" then
    game:orderHold()
  elseif key == "s" then
    game:orderStop()
  elseif key == "f" then
    game:orderFallBack()
  elseif key == "m" then
    game:setMobilized(UI.tab, not game.groups[UI.tab].mobilized)
  elseif key == "1" or key == "2" then
    local name = D.GROUPS[tonumber(key)]
    UI.tab = name
    if double then game:selectGroup(name) end
  end
end
