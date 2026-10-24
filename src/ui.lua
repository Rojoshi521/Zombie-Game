-- Immediate-mode HUD. Buttons are registered while drawing and checked on the
-- next click.
local U = require("src.util")
local D = require("src.data")
local G = require("src.gfx")
local S = require("src.structures")

local lg = love.graphics

local UI = {
  buttons = {},
  panels = {},
  tab = "Combat",
  groupOpen = false, -- whether the panel for UI.tab is showing
  placing = nil, -- the building being placed: kind, turn (rot) and footprint
  rallyMode = nil,
  amove = false,
  help = false,
}

local COL = {
  panel = { 0.075, 0.07, 0.065, 0.93 },
  panel2 = { 0.12, 0.105, 0.09, 0.95 },
  border = { 0.42, 0.28, 0.16 },
  text = { 0.92, 0.87, 0.77 },
  dim = { 0.62, 0.57, 0.50 },
  amber = { 1.0, 0.70, 0.30 },
  good = { 0.55, 0.85, 0.45 },
  bad = { 0.95, 0.35, 0.28 },
  alert = { 1.0, 0.62, 0.25 },
}
UI.COL = COL

local function text(str, x, y, font, col, limit, align)
  lg.setFont(font or G.font.m)
  lg.setColor(col or COL.text)
  if limit then
    lg.printf(str, math.floor(x), math.floor(y), limit, align or "left")
  else
    lg.print(str, math.floor(x), math.floor(y))
  end
end
UI.text = text

local function panel(x, y, w, h)
  UI.panels[#UI.panels + 1] = { x, y, w, h }
  lg.setColor(COL.panel)
  lg.rectangle("fill", x, y, w, h, 3)
  lg.setColor(COL.border)
  lg.setLineWidth(1)
  lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3)
end
UI.panel = panel

local function button(x, y, w, h, label, fn, opts)
  opts = opts or {}
  local mx, my = love.mouse.getPosition()
  local hover = U.inRect(mx, my, x, y, w, h) and not opts.disabled
  UI.buttons[#UI.buttons + 1] = { x = x, y = y, w = w, h = h, fn = fn, disabled = opts.disabled }
  local bg = opts.color or { 0.20, 0.17, 0.14 }
  if opts.active then bg = { 0.55, 0.36, 0.14 } end
  if opts.disabled then bg = { 0.12, 0.11, 0.10 } end
  local f = hover and 1.3 or 1
  lg.setColor(bg[1] * f, bg[2] * f, bg[3] * f, 0.97)
  lg.rectangle("fill", x, y, w, h, 3)
  lg.setColor(opts.disabled and { 0.25, 0.2, 0.16 } or COL.border)
  lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3)
  local font = opts.font or G.font.m
  text(label, x, y + (h - font:getHeight()) / 2, font, opts.disabled and COL.dim or COL.text, w, "center")
end
UI.button = button

function UI.beginFrame()
  UI.buttons = {}
  UI.panels = {}
end

function UI.mousepressed(x, y, b)
  local m = UI.mm
  if m and U.inRect(x, y, m.x, m.y, m.w, m.h) then
    if b == 1 then
      UI.minimapDrag = true
      UI.minimapJump(x, y)
    end
    return true
  end
  if b ~= 1 then
    for _, p in ipairs(UI.panels) do
      if U.inRect(x, y, p[1], p[2], p[3], p[4]) then return true end
    end
    return false
  end
  for i = #UI.buttons, 1, -1 do
    local bt = UI.buttons[i]
    if U.inRect(x, y, bt.x, bt.y, bt.w, bt.h) then
      if bt.fn and not bt.disabled then bt.fn() end
      return true
    end
  end
  for _, p in ipairs(UI.panels) do
    if U.inRect(x, y, p[1], p[2], p[3], p[4]) then return true end
  end
  return false
end

----------------------------------------------------------------------------


local function topBar(game, w)
  panel(0, 0, w, 38)
  local x = 12
  local function chip(label, value, col, extra)
    text(label, x, 5, G.font.s, COL.dim)
    text(value, x, 17, G.font.l, col or COL.text)
    local vw = G.font.l:getWidth(value)
    if extra then text(extra, x + vw + 5, 21, G.font.s, extra:sub(1, 1) == "-" and COL.bad or COL.good) end
    x = x + math.max(G.font.s:getWidth(label), vw + (extra and G.font.s:getWidth(extra) + 6 or 0)) + 22
  end
  local fr = game.foodRate
  chip("FOOD", tostring(math.floor(game.res.food)), game.res.food <= 0 and COL.bad or nil,
    string.format("%s%.1f/min", fr >= 0 and "+" or "-", math.abs(fr * 60)))
  chip("AMMO", tostring(game.res.ammo), game.res.ammo <= 0 and COL.bad or nil)
  chip("SCRAP", tostring(game.res.scrap))
  chip("RIFLES", tostring(game.stock.rifle))
  chip("PISTOLS", tostring(game.stock.pistol))
  chip("SURVIVORS", tostring(game:livingCount()))

  local d = game.director
  local label
  if d.phase == "day" then
    label = string.format("DAY %d  ·  SUNSET IN %s", d.wave + 1, U.formatTime(d.timer))
  elseif d.phase == "dusk" then
    label = string.format("DUSK  ·  NIGHT %d FALLS IN %s", d.wave, U.formatTime(d.timer))
  elseif d.phase == "dawn" then
    label = string.format("DAWN  ·  DAY %d IN %s", d.wave + 1, U.formatTime(d.timer))
  else
    label = string.format("NIGHT %d  ·  %d infected left", d.wave, game:waveZombieCount() + #d.queue)
  end
  local col = d.phase == "night" and COL.bad or (d.phase == "dusk" and COL.alert or COL.amber)
  text(label, 0, 9, G.font.l, col, w, "center")

  local bx = w - 10
  local function rbutton(label, bw, fn, opts)
    bx = bx - bw
    button(bx, 6, bw, 26, label, fn, opts)
    bx = bx - 6
  end
  rbutton("?", 28, function() UI.help = not UI.help end, { active = UI.help })
  rbutton("x3", 34, function() game.speed = 3 end, { active = game.speed == 3 })
  rbutton("x2", 34, function() game.speed = 2 end, { active = game.speed == 2 })
  rbutton("x1", 34, function() game.speed = 1 end, { active = game.speed == 1 })
  rbutton(game.paused and "Resume" or "Pause", 70, function() game.paused = not game.paused end, { active = game.paused })
  local cost = game:repairCost()
  if cost > 0 then
    rbutton(string.format("Repair (%d scrap)", cost), 150, function() game:repairWalls() end,
      { disabled = d.phase == "night" or game.res.scrap <= 0 })
  end
  if d.phase == "day" then
    rbutton("Call night early", 130, function() d:callEarly() end, { color = { 0.38, 0.12, 0.09 } })
  end
end

local function messages(game, w)
  local y = 46
  for _, m in ipairs(game.messages) do
    local a = 1
    if m.t > 9 then a = math.max(0, 1 - (m.t - 9) / 2) end
    if a > 0 then
      local col = COL[m.kind] or COL.text
      local tw = G.font.m:getWidth(m.text)
      lg.setColor(0, 0, 0, 0.55 * a)
      lg.rectangle("fill", (w - tw) / 2 - 8, y - 2, tw + 16, 19, 3)
      lg.setColor(col[1], col[2], col[3], a)
      lg.setFont(G.font.m)
      lg.print(m.text, math.floor((w - tw) / 2), y)
      y = y + 21
    end
  end
end

-- A small drawn emblem for each group, centred on (x, y).
local function groupIcon(name, x, y, col)
  lg.setColor(col)
  lg.setLineWidth(2)
  if name == "Combat" then
    lg.circle("line", x, y, 7)
    lg.line(x - 11, y, x - 3, y)
    lg.line(x + 3, y, x + 11, y)
    lg.line(x, y - 11, x, y - 3)
    lg.line(x, y + 3, x, y + 11)
  elseif name == "Engineering" then
    lg.circle("line", x, y, 5)
    for i = 0, 5 do
      local a = i * math.pi / 3
      lg.line(x + math.cos(a) * 6, y + math.sin(a) * 6, x + math.cos(a) * 10, y + math.sin(a) * 10)
    end
  elseif name == "Scouting" then
    lg.ellipse("line", x, y, 11, 6)
    lg.circle("fill", x, y, 3.5)
  elseif name == "Scavenging" then
    lg.line(x - 7, y + 9, x + 5, y - 5)
    lg.arc("line", "open", x + 5, y - 5, 8, math.pi * 0.75, math.pi * 1.75)
  elseif name == "Medicine" then
    lg.rectangle("fill", x - 3, y - 10, 6, 20)
    lg.rectangle("fill", x - 10, y - 3, 20, 6)
  elseif name == "Research" then
    local pts = {}
    for i = 0, 5 do
      local a = i * math.pi / 3 + math.pi / 6
      pts[#pts + 1] = x + math.cos(a) * 9
      pts[#pts + 1] = y + math.sin(a) * 9
    end
    lg.polygon("line", pts)
    lg.circle("fill", x, y, 2.5)
  elseif name == "Agriculture" then
    lg.push()
    lg.translate(x, y)
    lg.rotate(-0.7)
    lg.ellipse("fill", 0, -2, 5, 9)
    lg.pop()
    lg.line(x - 7, y + 9, x, y + 1)
  elseif name == "Fabrication" then
    lg.line(x - 7, y + 9, x + 3, y - 3)
    lg.push()
    lg.translate(x + 3, y - 3)
    lg.rotate(-0.785)
    lg.rectangle("fill", -8, -4, 16, 7)
    lg.pop()
  elseif name == "Logistics" then
    lg.rectangle("line", x - 9, y - 8, 18, 16)
    lg.line(x - 9, y - 2, x + 9, y - 2)
    lg.line(x, y - 8, x, y - 2)
  elseif name == "Leadership" then
    lg.polygon("fill", x - 10, y + 7, x - 10, y - 6, x - 5, y, x, y - 9, x + 5, y, x + 10, y - 6, x + 10, y + 7)
  end
end

UI.BAR_H = 112

-- The specialization bar along the bottom: one card per group. Clicking a
-- card (or its hotkey) opens that group's panel.
local function specBar(game, w, h)
  local bh = UI.BAR_H
  local y = h - bh
  local right = 232 -- the minimap sits at the right end
  panel(0, y, w, bh)
  lg.setColor(0.55, 0.38, 0.18)
  lg.rectangle("fill", 0, y, w, 2)
  text("SPECIALIZATION CONTROL  ·  " .. #D.GROUPS .. " GROUPS", 14, y + 7, G.font.s, COL.dim)

  local anyOff = false
  for _, name in ipairs(D.GROUPS) do
    if not game.groups[name].mobilized then anyOff = true end
  end
  button(w - right - 160, y + 4, 150, 20, anyOff and "ALARM: ALL GROUPS" or "ALL RETURN TO WORK", function()
    for _, name in ipairs(D.GROUPS) do
      if game.groups[name].mobilized ~= anyOff then game:setMobilized(name, anyOff) end
    end
  end, { color = anyOff and { 0.45, 0.11, 0.08 } or { 0.16, 0.26, 0.14 }, font = G.font.s })
  text("SELECT TO MANAGE", 0, y + 7, G.font.s, COL.dim, w - right - 172, "right")

  local n = #D.GROUPS
  local gap = 5
  local cw = (w - right - 12 - gap * (n - 1)) / n
  local cy, ch = y + 28, bh - 36
  local mx, my = love.mouse.getPosition()
  local narrow = cw < 110
  for i, name in ipairs(D.GROUPS) do
    local cx = 10 + (i - 1) * (cw + gap)
    local grp = game.groups[name]
    local open = UI.groupOpen and UI.tab == name
    local hover = U.inRect(mx, my, cx, cy, cw, ch)
    UI.buttons[#UI.buttons + 1] = { x = cx, y = cy, w = cw, h = ch, fn = function()
      if open then UI.groupOpen = false else UI.tab, UI.groupOpen = name, true end
    end }
    local base = open and 0.2 or (hover and 0.17 or 0.13)
    lg.setColor(base, base * 0.95, base * 0.88, 0.97)
    lg.rectangle("fill", cx, cy, cw, ch, 4)
    lg.setColor(open and COL.amber or COL.border)
    lg.setLineWidth(open and 2 or 1)
    lg.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 1, 4)
    local col = D.GROUP_COLORS[name]
    lg.setColor(col[1], col[2], col[3], 0.9)
    lg.rectangle("fill", cx + 4, cy + ch - 4, cw - 8, 2)

    -- hotkey, and a status light: green working, pulsing red mobilized
    text(tostring(i % 10), cx + 6, cy + 4, G.font.s, COL.dim)
    if grp.mobilized then
      local p = 0.6 + 0.4 * math.sin(game.time * 6)
      lg.setColor(0.95, 0.3, 0.2, p)
    else
      lg.setColor(0.45, 0.8, 0.4)
    end
    lg.circle("fill", cx + cw - 9, cy + 9, 3.5)

    groupIcon(name, cx + cw / 2, cy + 17, col)
    text(name, cx, cy + 32, narrow and G.font.s or G.font.m, COL.text, cw, "center")
    local members = game:groupMembers(name)
    local down = 0
    for _, s in ipairs(members) do
      if s.state == "downed" then down = down + 1 end
    end
    local sub, subCol = #members .. " ASSIGNED", COL.dim
    if down > 0 then
      sub, subCol = sub .. " · " .. down .. " DOWN", COL.bad
    elseif #members > 0 and not game:canWork(name) then
      sub, subCol = "NO BUILDING", COL.alert
    end
    text(sub, cx, cy + 52, G.font.s, subCol, cw, "center")
  end
end

local function groupPanel(game, w, h)
  if not UI.groupOpen then return end
  local name = UI.tab
  local grp = game.groups[name]
  local members = game:groupMembers(name)
  local rows = math.max(1, math.ceil(math.min(#members, 8) / 2))
  local pw, ph = 790, 182 + rows * 20 + (#members > 8 and 16 or 0)
  local x, y = 10, h - UI.BAR_H - ph - 8
  panel(x, y, pw, ph)

  groupIcon(name, x + 22, y + 20, D.GROUP_COLORS[name])
  text(name:upper(), x + 40, y + 10, G.font.l, COL.text)
  local nw = G.font.l:getWidth(name:upper())
  local status, scol = "Working: " .. D.GROUP_WORKPLACE[name], COL.good
  if grp.mobilized then
    status, scol = "MOBILIZED", COL.bad
  elseif not game:canWork(name) then
    status, scol = "No building yet: waiting at the HQ, doing nothing", COL.alert
  end
  text(status, x + 52 + nw, y + 14, G.font.m, scol)
  button(x + pw - 34, y + 8, 24, 24, "x", function() UI.groupOpen = false end)

  local ready, downed, armed = 0, 0, 0
  for _, s in ipairs(members) do
    if s.state == "downed" then downed = downed + 1 else ready = ready + 1 end
    if s.weapon then armed = armed + 1 end
  end
  local cy = y + 42
  text(string.format("%d assigned · %d active · %d down · %d armed", #members, ready, downed, armed),
    x + 12, cy, G.font.m, COL.dim)

  -- the group's foundations, each placed on the map like a StarCraft building
  cy = cy + 24
  local kinds = S.FOUNDATIONS[name]
  text("Build (" .. S.BUILD_COST .. " scrap):", x + 12, cy + 5, G.font.s, COL.dim)
  if #kinds == 0 then
    text("Leadership has no building; it works from the headquarters.", x + 128, cy + 5, G.font.s, COL.dim)
  end
  local why = game:buildBlocker()
  local bx = x + 128
  local bw = (pw - 140 - 8) / 3
  for _, kind in ipairs(kinds) do
    local def = S.DEFS[kind]
    local built = 0
    for _, b in ipairs(game:buildingsOf(name)) do
      if b.kind == kind then built = built + 1 end
    end
    button(bx, cy, bw, 24, def.name .. (built > 0 and (" (" .. built .. ")") or ""), function()
      UI.placing = { kind = kind, rot = 0 }
      UI.rallyMode, UI.amove = nil, false
    end, { disabled = why ~= nil, font = G.font.s, active = UI.placing and UI.placing.kind == kind })
    bx = bx + bw + 4
  end

  cy = cy + 32
  text("Loadout:", x + 12, cy + 5, G.font.m, COL.dim)
  local lx = x + 78
  for _, key in ipairs(D.LOADOUTS) do
    local label = D.LOADOUT_LABELS[key]
    if game.stock[key] then label = label .. " (" .. game.stock[key] .. ")" end
    button(lx, cy, 118, 24, label, function() grp.loadout = key end, { active = grp.loadout == key })
    lx = lx + 122
  end

  cy = cy + 32
  if grp.mobilized then
    button(x + 12, cy, 180, 30, "RETURN TO WORK", function() game:setMobilized(name, false) end,
      { color = { 0.16, 0.26, 0.14 }, font = G.font.l })
  else
    button(x + 12, cy, 180, 30, "MOBILIZE", function() game:setMobilized(name, true) end,
      { color = { 0.45, 0.11, 0.08 }, font = G.font.l })
  end
  button(x + 198, cy, 140, 30, UI.rallyMode == name and "Click the map..." or "Set rally point",
    function() UI.rallyMode = UI.rallyMode ~= name and name or nil end, { active = UI.rallyMode == name })
  button(x + 344, cy, 120, 30, "Select group", function() game:selectGroup(name, love.keyboard.isDown("lshift", "rshift")) end)

  cy = cy + 40
  local colW = (pw - 24) / 2
  if #members == 0 then
    text("Nobody works here. Select a survivor and reassign them from their profile.", x + 12, cy, G.font.s, COL.dim)
  end
  for i, s in ipairs(members) do
    if i > 8 then
      text("+" .. (#members - 8) .. " more", x + 12, y + ph - 18, G.font.s, COL.dim)
      break
    end
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local rx, ry = x + 12 + col * colW, cy + row * 20
    local sel = game:isSelected(s)
    UI.buttons[#UI.buttons + 1] = { x = rx, y = ry, w = colW - 6, h = 18, fn = function()
      if love.keyboard.isDown("lshift", "rshift") then
        if not sel then game.selection[#game.selection + 1] = s end
      else
        game.selection = { s }
      end
    end }
    lg.setColor(sel and { 0.3, 0.45, 0.25, 0.6 } or { 1, 1, 1, 0.04 })
    lg.rectangle("fill", rx, ry, colW - 6, 18, 2)
    G.bar(rx + 4, ry + 7, 24, 4, s.hp / s.maxhp, G.hpColor(s.hp / s.maxhp))
    text(s.name, rx + 34, ry + 2, G.font.s, s.state == "downed" and COL.bad or COL.text)
    local wpn = s.weapon and D.WEAPONS[s.weapon].name or ""
    text(s:stateLabel() .. (wpn ~= "" and (" · " .. wpn) or ""), rx, ry + 2, G.font.s, COL.dim, colW - 12, "right")
  end
end

local function profilePanel(game, w, h)
  local sel = game.selection
  if #sel == 0 then return end
  local pw = 320
  local x, y = w - pw - 10, 48

  if #sel > 1 then
    panel(x, y, pw, 92)
    text(#sel .. " survivors selected", x + 12, y + 10, G.font.l)
    text("Right-click: move · A + click: attack-move\nRight-click a zombie: focus fire\nH: hold · S: stop · F: fall back to rally",
      x + 12, y + 34, G.font.s, COL.dim, pw - 24)
    return
  end

  local s = sel[1]
  local ph = 562
  panel(x, y, pw, ph)
  local cy = y + 10
  text(s.name, x + 12, cy, G.font.l)
  text(s.age .. " yrs", x + 12, cy + 3, G.font.s, COL.dim, pw - 24, "right")
  cy = cy + 22
  text("Former " .. s.background, x + 12, cy, G.font.m, COL.amber)
  cy = cy + 18
  G.setc(D.GROUP_COLORS[s.group])
  lg.rectangle("fill", x + 12, cy + 4, 8, 8)
  text(s.group .. "  ·  " .. s:stateLabel(), x + 26, cy, G.font.m, COL.text)
  cy = cy + 22
  G.bar(x + 12, cy + 2, pw - 90, 7, s.hp / s.maxhp, G.hpColor(s.hp / s.maxhp))
  text(math.ceil(s.hp) .. " / " .. s.maxhp, x + pw - 72, cy - 2, G.font.s, COL.text, 60, "right")
  cy = cy + 16
  local wpn = D.WEAPONS[s.weapon or "fists"]
  text("Weapon: " .. wpn.name, x + 12, cy, G.font.s, COL.dim)
  if s.carry then
    local parts = {}
    for k, n in pairs(s.carry) do parts[#parts + 1] = n .. " " .. k end
    text("Carrying: " .. table.concat(parts, ", "), x + 140, cy, G.font.s, COL.amber, pw - 152)
  end

  cy = cy + 24
  text("CORE TRAITS", x + 12, cy, G.font.s, COL.dim)
  cy = cy + 15
  for _, t in ipairs(s.traits) do
    text(t.name, x + 12, cy, G.font.m, t.good and COL.good or COL.bad)
    text(t.text, x + 12, cy + 16, G.font.s, COL.dim, pw - 24)
    cy = cy + 36
  end

  cy = cy + 4
  text("APTITUDE  /  LEARNED SKILL", x + 12, cy, G.font.s, COL.dim)
  cy = cy + 16
  for _, gname in ipairs(D.GROUPS) do
    text(gname, x + 12, cy, G.font.s, gname == s.group and COL.amber or COL.text)
    text("talent " .. s.apt[gname] .. "/10", x + 100, cy, G.font.s, COL.amber)
    G.bar(x + 175, cy + 5, pw - 225, 5, s.prof[gname] / 10, D.GROUP_COLORS[gname], { 0.2, 0.18, 0.15, 1 })
    text(string.format("%.1f", s.prof[gname]), x + pw - 46, cy, G.font.s, COL.text, 34, "right")
    cy = cy + 16
  end
  cy = cy + 8

  text("COMBAT ATTRIBUTES", x + 12, cy, G.font.s, COL.dim)
  cy = cy + 15
  local half = (pw - 24) / 2
  for i, a in ipairs(D.COMBAT_ATTRS) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local ax, ay = x + 12 + col * half, cy + row * 16
    text(a, ax, ay, G.font.s, COL.dim)
    G.bar(ax + 74, ay + 5, half - 100, 4, s.attr[a] / 10, COL.amber, { 0.2, 0.18, 0.15, 1 })
    text(tostring(s.attr[a]), ax + half - 22, ay, G.font.s, COL.text)
  end
  cy = cy + 54

  text("Reassign to:", x + 12, cy, G.font.s, COL.dim)
  cy = cy + 16
  local bw = (pw - 24 - 8) / 3
  local k = 0
  for _, other in ipairs(D.GROUPS) do
    if other ~= s.group then
      local bx, by = x + 12 + (k % 3) * (bw + 4), cy + math.floor(k / 3) * 26
      k = k + 1
      button(bx, by, bw, 22, other, function()
        s.group = other
        if s:isActive() then
          if game.groups[other].mobilized then s:mobilize(game) else s:returnToWork(game) end
        end
        game:message(s.name .. " now works with " .. other .. ".")
      end, { disabled = not s:isActive(), font = G.font.s })
    end
  end
end

local function alertBanner(game, w, h)
  local d = game.director
  if d.phase ~= "dusk" then return end
  local pulse = 0.6 + 0.4 * math.sin(game.time * 6)
  local names = {}
  for i, e in ipairs(d.edges) do names[i] = e.name:upper() end
  local msg = string.format("NIGHT %d  ·  THE HORDE COMES FROM THE %s  ·  %d", d.wave, table.concat(names, " & "), math.ceil(d.timer))
  local tw = G.font.xl:getWidth(msg)
  lg.setColor(0.2, 0.02, 0.01, 0.7)
  lg.rectangle("fill", (w - tw) / 2 - 18, h * 0.22 - 8, tw + 36, 48, 4)
  lg.setColor(1, 0.3, 0.2, pulse)
  lg.setFont(G.font.xl)
  lg.print(msg, math.floor((w - tw) / 2), math.floor(h * 0.22))
end

local function tooltip(game)
  local mx, my = love.mouse.getPosition()
  for _, p in ipairs(UI.panels) do
    if U.inRect(mx, my, p[1], p[2], p[3], p[4]) then return end
  end
  local lines
  local z = game:zombieAt(mx, my)
  if z then
    lines = { z.def.name, string.format("%d / %d", math.ceil(z.hp), math.ceil(z.maxhp)) }
  else
    local s = game:survivorAt(mx, my)
    local site = not s and game:siteAt(mx, my)
    if s then
      lines = { s.name, s.group .. " · " .. s:stateLabel() }
    elseif site then
      lines = { site.name }
      local info = site.site
      if not info then
        lines[2] = "Nothing worth taking."
      elseif info.searched then
        lines[2] = "Searched."
      elseif not info.known then
        lines[2] = "Not scouted yet. Send someone close to see what's inside."
      else
        local parts = {}
        for k, n in pairs(info.loot) do parts[#parts + 1] = "~" .. n .. " " .. k end
        lines[2] = #parts > 0 and ("Inside: " .. table.concat(parts, ", ")) or "Looks picked clean."
        lines[3] = "Select survivors and right-click to search it. Scavengers are fastest."
        if info.progress > 0 then lines[4] = string.format("Searched %d%%", info.progress / info.work * 100) end
      end
    else
      local st = game:structureAt(mx, my)
      if st and st.name then
        lines = { st.name }
        if st.blocking then lines[2] = string.format("%d / %d", math.ceil(st.hp), st.maxhp) end
        if st.desc then lines[#lines + 1] = st.desc end
      end
    end
  end
  if not lines then return end
  local tw = 0
  for _, l in ipairs(lines) do tw = math.max(tw, G.font.s:getWidth(l)) end
  tw = math.min(tw, 280)
  local bh = 0
  for i, l in ipairs(lines) do
    local _, wrapped = G.font.s:getWrap(l, tw)
    bh = bh + #wrapped * 14
  end
  local x, y = mx + 16, my + 12
  lg.setColor(0.05, 0.045, 0.04, 0.92)
  lg.rectangle("fill", x, y, tw + 14, bh + 10, 3)
  lg.setColor(COL.border)
  lg.rectangle("line", x + 0.5, y + 0.5, tw + 13, bh + 9, 3)
  local ly = y + 5
  for i, l in ipairs(lines) do
    text(l, x + 7, ly, G.font.s, i == 1 and COL.amber or COL.text, tw)
    local _, wrapped = G.font.s:getWrap(l, tw)
    ly = ly + #wrapped * 14
  end
end

----------------------------------------------------------------------------
-- Minimap: the map as a diamond, explored ground only.

local function rebuildMinimap(game)
  local W, H = game.MAP_W, game.MAP_H
  UI.mmData = UI.mmData or love.image.newImageData(W, H)
  local data = UI.mmData
  local map = game.map
  for cy = 1, H do
    for cx = 1, W do
      local i = (cy - 1) * W + cx
      local f = game.fog[i]
      if f == 0 then
        data:setPixel(cx - 1, cy - 1, 0, 0, 0, 0)
      else
        local r, g, b = 0.22, 0.16, 0.11
        local s = map.structAt[i]
        if game.townRoad[i] then r, g, b = 0.33, 0.32, 0.31 end
        if s and s.town and s.blocking then r, g, b = 0.48, 0.40, 0.32
        elseif s and s.town then r, g, b = 0.26, 0.30, 0.18
        elseif s and s.blocking then r, g, b = 0.85, 0.58, 0.26 end
        local k = f == 2 and 1 or 0.55
        data:setPixel(cx - 1, cy - 1, r * k, g * k, b * k, 1)
      end
    end
  end
  if UI.mmImg then UI.mmImg:replacePixels(data) else
    UI.mmImg = lg.newImage(data)
    UI.mmImg:setFilter("nearest", "nearest")
  end
  game.minimapDirty = false
end

local function mmPoint(m, wx, wy)
  return m.cx + (wx - wy) * m.kx, m.y + (wx + wy) * m.ky
end

function UI.minimapJump(x, y)
  local m, game = UI.mm, UI.game
  if not m or not game then return end
  local a, b = (x - m.cx) / m.kx, (y - m.y) / m.ky
  local wx, wy = (a + b) / 2, (b - a) / 2
  local Iso = require("src.iso")
  game.camera.x, game.camera.y = Iso.toScreen(wx, wy)
end

local function minimap(game, w, h)
  if game.minimapDirty or not UI.mmImg then rebuildMinimap(game) end
  local mw, mh = 200, 100
  local x, y = w - mw - 14, h - mh - 6
  panel(x - 4, y - 4, mw + 8, mh + 8)
  local W = game.MAP_W
  local m = { x = x, y = y, w = mw, h = mh, cx = x + mw / 2, kx = mw / 2 / W, ky = mh / 2 / W }
  UI.mm = m

  lg.push()
  lg.translate(m.cx, y)
  lg.scale(m.kx, m.ky)
  lg.rotate(math.pi / 4)
  lg.scale(math.sqrt(2))
  lg.setColor(1, 1, 1)
  lg.draw(UI.mmImg, 0, 0)
  lg.pop()

  for _, z in ipairs(game.zombies) do
    if game:fogAt(z.x, z.y) == 2 then
      local px, py = mmPoint(m, z.x, z.y)
      lg.setColor(0.95, 0.2, 0.15)
      lg.rectangle("fill", px - 1, py - 1, 2, 2)
    end
  end
  for _, s in ipairs(game.survivors) do
    if s.state ~= "dead" then
      local px, py = mmPoint(m, s.x, s.y)
      G.setc(D.GROUP_COLORS[s.group], 1.3)
      lg.rectangle("fill", px - 1.5, py - 1.5, 3, 3)
    end
  end
  local cam = game.camera
  local pts = {}
  for _, c in ipairs({ { 0, 0 }, { w, 0 }, { w, h }, { 0, h } }) do
    local wx, wy = cam:screenToWorld(c[1], c[2])
    local px, py = mmPoint(m, wx, wy)
    pts[#pts + 1] = px
    pts[#pts + 1] = py
  end
  lg.setScissor(x, y, mw, mh)
  lg.setColor(1, 1, 1, 0.7)
  lg.setLineWidth(1)
  lg.polygon("line", pts)
  lg.setScissor()
end

local HELP = {
  { "Left-click / drag", "Select survivors (Shift adds)" },
  { "Right-click ground", "Move selected (they will not shoot while moving)" },
  { "A, then left-click", "Attack-move: fight anything met on the way" },
  { "Right-click a zombie", "Focus fire" },
  { "Right-click a building", "Search it for loot (carry it home to use it)" },
  { "Group panel: Build", "Place a building · R turns it · right-click cancels" },
  { "H / S / F", "Hold position · Stop · Fall back to rally point" },
  { "1 - 9, 0", "Open a group's panel (double-tap selects the group)" },
  { "M", "Mobilize / return the current group" },
  { "Arrows, screen edge, middle-drag", "Pan the camera" },
  { "Mouse wheel", "Zoom" },
  { "Space", "Pause" },
  { "Esc", "Cancel / deselect" },
}

local function helpOverlay(w, h)
  local pw, ph = 620, 444
  local x, y = (w - pw) / 2, (h - ph) / 2
  panel(x, y, pw, ph)
  text("HOW TO SURVIVE", x, y + 14, G.font.xl, COL.amber, pw, "center")
  local cy = y + 62
  for _, row in ipairs(HELP) do
    text(row[1], x + 24, cy, G.font.m, COL.text)
    text(row[2], x + 260, cy, G.font.m, COL.dim)
    cy = cy + 21
  end
  cy = cy + 10
  text("Days are for scouting, scavenging and repairs; the horde comes at night. Get expeditions home by dusk, " ..
    "mobilize when scouts raise the alarm and send everyone back to work at dawn: a mobilized farmer grows no food. Mobilizing survivors physically walk to the armory for gear, " ..
    "so plan for the walk.", x + 24, cy, G.font.s, COL.dim, pw - 48)
  button(x + pw / 2 - 60, y + ph - 40, 120, 28, "Close", function() UI.help = false end)
end

function UI.draw(game)
  local w, h = lg.getDimensions()
  UI.game = game
  UI.beginFrame()
  topBar(game, w)
  messages(game, w)
  alertBanner(game, w, h)
  specBar(game, w, h)
  groupPanel(game, w, h)
  profilePanel(game, w, h)
  minimap(game, w, h)

  if UI.placing then
    local why = game:buildBlocker()
    text(why or ("Placing the " .. S.DEFS[UI.placing.kind].name ..
      ": left-click to build · R to turn it · right-click or Esc to cancel"),
      0, 116, G.font.m, why and COL.bad or COL.amber, w, "center")
  elseif UI.rallyMode then
    text("Click the map to place the " .. UI.rallyMode .. " rally point · right-click to cancel",
      0, 116, G.font.m, COL.amber, w, "center")
  elseif UI.amove then
    text("ATTACK-MOVE: left-click a destination", 0, 116, G.font.m, COL.bad, w, "center")
  end
  if game.paused and not game.over then
    text("PAUSED", 0, h * 0.4, G.font.xl, COL.amber, w, "center")
  end
  if UI.help then helpOverlay(w, h) else tooltip(game) end

  if game.over then
    lg.setColor(0, 0, 0, 0.7)
    lg.rectangle("fill", 0, 0, w, h)
    text("THE SETTLEMENT HAS FALLEN", 0, h * 0.32, G.font.title, COL.bad, w, "center")
    text(game.over.reason, 0, h * 0.32 + 84, G.font.l, COL.text, w, "center")
    text(string.format("Nights survived: %d  ·  Infected killed: %d  ·  Survivors lost: %d",
      game.over.wave, game.stats.kills, game.stats.lost), 0, h * 0.32 + 116, G.font.m, COL.dim, w, "center")
    button(w / 2 - 90, h * 0.32 + 160, 180, 36, "Back to menu", function() UI.onRestart() end, { font = G.font.l })
  end
end

return UI
