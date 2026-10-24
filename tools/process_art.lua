-- Asset tool: cuts the dark studio background out of building and prop
-- renders and extracts their lit windows and lamps as a separate glow layer.
--
--   love . --process-art "<folder of renders>"
--
-- Every PNG in the folder becomes assets/buildings/<id>.png and <id>_glow.png,
-- where <id> is the file name in lower case with spaces as underscores.
-- terrain.png is the prop sheet and is cut into assets/props/. The other
-- terrain sheets are skipped for now.
local ffi = require("ffi")

-- The first batch of renders had numbered names.
local ART_IDS = {
  ["art6.png"] = "coop",
  ["art7.png"] = "cathedral",
  ["art8.png"] = "campus",
  ["art9.png"] = "farmhouse",
  ["art10.png"] = "watertower",
  ["art11.png"] = "ferriswheel",
  ["art12.png"] = "casino",
  ["art13.png"] = "broadcast",
}

-- Regions of the prop sheet (terrain.png, 1536x1024), excluding the labels.
local PROPS = {
  { id = "fence", rect = { 0, 80, 545, 420 } },
  { id = "gate", rect = { 540, 110, 585, 375 } },
  { id = "watchtower", rect = { 1130, 15, 395, 478 } },
  { id = "crates", rect = { 0, 600, 650, 352 } },
  { id = "lamp", rect = { 670, 535, 340, 415 } },
  { id = "firebarrel", rect = { 1060, 560, 460, 395 } },
}

-- Rotation sheets: one building from several sides, in quarter-turn views
-- named <id>_r<turn>. Each is a 2x2 grid with a label under each view; the
-- rects leave the labels out. Turn 2 is drawn as turn 3 mirrored (see
-- the building's views in src/structures.lua).
local ROTATION_SHEETS = {
  ["box_truck_armory_views.png"] = {
    { id = "box_truck_armory_r0", rect = { 0, 30, 838, 432 } }, -- LEFT
    { id = "box_truck_armory_r1", rect = { 0, 515, 812, 440 } }, -- RIGHT
    { id = "box_truck_armory_r3", rect = { 818, 515, 630, 440 } }, -- BACK
  },
}

-- Renders whose ground runs off the edge of the image get a soft oval fade.
local EDGE_FADE = { salvage_garden = true }

local OUT_SCALE = 0.55 -- the renders are far larger than they appear in game

local function readFile(path)
  local f = assert(io.open(path, "rb"), "cannot open " .. path)
  local data = f:read("*a")
  f:close()
  return data
end

local function writeFile(path, data)
  local f = assert(io.open(path, "wb"), "cannot write " .. path)
  f:write(data)
  f:close()
end

local function isBackground(r, g, b)
  local mx = math.max(r, g, b)
  local mn = math.min(r, g, b)
  return mx < 40 and mx - mn < 12
end

-- Separable box blur of a float mask, in place.
local function boxBlur(mask, tmp, w, h, radius)
  local span = radius * 2 + 1
  for y = 0, h - 1 do
    local row = y * w
    local acc = 0
    for x = -radius, radius do acc = acc + mask[row + math.max(0, math.min(w - 1, x))] end
    for x = 0, w - 1 do
      tmp[row + x] = acc / span
      local add = math.min(w - 1, x + radius + 1)
      local sub = math.max(0, x - radius)
      acc = acc + mask[row + add] - mask[row + sub]
    end
  end
  for x = 0, w - 1 do
    local acc = 0
    for y = -radius, radius do acc = acc + tmp[math.max(0, math.min(h - 1, y)) * w + x] end
    for y = 0, h - 1 do
      mask[y * w + x] = acc / span
      local add = math.min(h - 1, y + radius + 1)
      local sub = math.max(0, y - radius)
      acc = acc + tmp[add * w + x] - tmp[sub * w + x]
    end
  end
end

local function processOne(src, outDir, entry)
  local fd = love.filesystem.newFileData(readFile(src .. "/" .. entry.file), entry.file)
  local img = love.image.newImageData(fd)
  if entry.rect then
    local r = entry.rect
    local part = love.image.newImageData(r[3], r[4])
    part:paste(img, 0, 0, r[1], r[2], r[3], r[4])
    img = part
  end
  local w, h = img:getDimensions()
  local px = ffi.cast("uint8_t*", img:getFFIPointer())
  local n = w * h

  -- flood-fill the background inward from the borders
  local bg = ffi.new("uint8_t[?]", n)
  local queue = ffi.new("int32_t[?]", n)
  local head, tail = 0, 0
  local function try(i)
    if bg[i] == 0 then
      local o = i * 4
      if isBackground(px[o], px[o + 1], px[o + 2]) then
        bg[i] = 1
        queue[tail] = i
        tail = tail + 1
      end
    end
  end
  for x = 0, w - 1 do
    try(x)
    try((h - 1) * w + x)
  end
  for y = 0, h - 1 do
    try(y * w)
    try(y * w + w - 1)
  end
  while head < tail do
    local i = queue[head]
    head = head + 1
    local x, y = i % w, math.floor(i / w)
    if x > 0 then try(i - 1) end
    if x < w - 1 then try(i + 1) end
    if y > 0 then try(i - w) end
    if y < h - 1 then try(i + w) end
  end

  -- Second pass: the haze around lamps and smoke that touches the background
  -- fades out with its brightness instead of being kept solid. Haze is a
  -- smooth gradient; real objects (a dark crate, a dark wall) have texture
  -- and edges, which stops the fill.
  local function roughness(i)
    local x, y = i % w, math.floor(i / w)
    local o = i * 4
    local best = 0
    for _, j in ipairs({ x < w - 1 and i + 1 or i - 1, y < h - 1 and i + w or i - w }) do
      local q = j * 4
      local d = math.max(math.abs(px[o] - px[q]), math.abs(px[o + 1] - px[q + 1]), math.abs(px[o + 2] - px[q + 2]))
      if d > best then best = d end
    end
    return best
  end
  local haze = ffi.new("float[?]", n)
  head = 0
  local function tryHaze(i)
    if bg[i] == 0 then
      local o = i * 4
      local r, g, b = px[o], px[o + 1], px[o + 2]
      local mx, mn = math.max(r, g, b), math.min(r, g, b)
      if mx < 110 and (mx - mn < 18 or mx < 60) and roughness(i) <= 4 then
        bg[i] = 2
        local t = math.max(0, math.min(1, (mx - 30) / 80))
        haze[i] = t * t
        queue[tail] = i
        tail = tail + 1
      end
    end
  end
  while head < tail do
    local i = queue[head]
    head = head + 1
    local x, y = i % w, math.floor(i / w)
    if x > 0 then tryHaze(i - 1) end
    if x < w - 1 then tryHaze(i + 1) end
    if y > 0 then tryHaze(i - w) end
    if y < h - 1 then tryHaze(i + w) end
  end

  -- soft alpha edge
  local alpha = ffi.new("float[?]", n)
  local tmp = ffi.new("float[?]", n)
  for i = 0, n - 1 do
    if bg[i] == 1 then alpha[i] = 0 elseif bg[i] == 2 then alpha[i] = haze[i] else alpha[i] = 1 end
  end
  boxBlur(alpha, tmp, w, h, 2)
  for i = 0, n - 1 do
    if bg[i] == 1 then alpha[i] = alpha[i] * 0.6 end
  end
  if EDGE_FADE[entry.id] then
    for i = 0, n - 1 do
      local dx = (i % w - w / 2) / (w / 2)
      local dy = (math.floor(i / w) - h / 2) / (h / 2)
      local d = math.sqrt(dx * dx + dy * dy)
      alpha[i] = alpha[i] * math.max(0, math.min(1, (1 - d) / 0.3))
    end
  end

  -- bounding box of what is left
  local x0, y0, x1, y1 = w, h, 0, 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if alpha[y * w + x] > 0.05 then
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        if y > y1 then y1 = y end
      end
    end
  end
  x0, y0 = math.max(0, x0 - 4), math.max(0, y0 - 4)
  x1, y1 = math.min(w - 1, x1 + 4), math.min(h - 1, y1 + 4)
  local cw, ch = x1 - x0 + 1, y1 - y0 + 1

  local cut = love.image.newImageData(cw, ch)
  local glow = love.image.newImageData(cw, ch)
  local cp = ffi.cast("uint8_t*", cut:getFFIPointer())
  local gp = ffi.cast("uint8_t*", glow:getFFIPointer())
  for y = 0, ch - 1 do
    for x = 0, cw - 1 do
      local si = (y + y0) * w + (x + x0)
      local so = si * 4
      local o = (y * cw + x) * 4
      local r, g, b = px[so], px[so + 1], px[so + 2]
      cp[o], cp[o + 1], cp[o + 2] = r, g, b
      cp[o + 3] = math.floor(alpha[si] * 255 + 0.5)
      -- warm, bright pixels are lamps, windows and neon: they emit light
      local lum = (r * 0.3 + g * 0.55 + b * 0.15) / 255
      local warm = r >= g and g >= b * 0.9 and r > 150
      local neon = math.max(r, g, b) > 200 and (b > 170 or (r > 200 and g < 110))
      local e = 0
      if warm then e = math.max(0, math.min(1, (lum - 0.5) / 0.3)) end
      if neon then e = math.max(e, 0.8) end
      gp[o], gp[o + 1], gp[o + 2] = r, g, b
      gp[o + 3] = math.floor(e * alpha[si] * 255 + 0.5)
    end
  end

  -- downscale on the GPU; "replace" keeps straight (non-premultiplied) alpha
  local function shrink(data)
    local image = love.graphics.newImage(data, { mipmaps = true })
    image:setFilter("linear", "linear")
    image:setMipmapFilter("linear")
    local ow, oh = math.floor(cw * OUT_SCALE + 0.5), math.floor(ch * OUT_SCALE + 0.5)
    local canvas = love.graphics.newCanvas(ow, oh)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("replace")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0, 0, ow / cw, oh / ch)
    love.graphics.setBlendMode("alpha")
    love.graphics.setCanvas()
    return canvas:newImageData(), ow, oh
  end
  local small, ow, oh = shrink(cut)
  local smallGlow = shrink(glow)
  writeFile(outDir .. "/" .. entry.id .. ".png", small:encode("png"):getString())
  writeFile(outDir .. "/" .. entry.id .. "_glow.png", smallGlow:encode("png"):getString())
  print(string.format("%-12s %4dx%-4d  (cropped from %dx%d at %d,%d)", entry.id, ow, oh, w, h, x0, y0))
end

----------------------------------------------------------------------------
-- Town sheets: two columns of panels, four rows, each panel one object in
-- four views (front, left, back, right) on a diamond ground plate, over navy.

local VIEWS = { "front", "left", "back", "right" }

local SHEETS = {
  { file = "terrain1.png", rows = { 5, 240, 503, 730, 1024 },
    names = { "broken_car", "broken_truck", "car_on_fire", "truck_on_fire",
      "poor_road", "telephone_poles", "traffic_lights", "factory" } },
  { file = "terrain2.png", rows = { 0, 264, 529, 789, 1086 },
    names = { "blue_bungalow", "brick_townhouse", "ranch_house", "green_cottage",
      "split_level", "white_farmhouse", "brown_duplex", "aframe_cabin" } },
  { file = "terrain3.png", rows = { 0, 266, 541, 807, 1086 },
    names = { "diner", "grade_school", "police_station", "vet_clinic",
      "game_store", "grocery_store", "scrapyard", "corner_store" } },
  { file = "terrain4.png", rows = { 0, 251, 501, 749, 1024 },
    names = { "office_building", "high_rise", "doctors_office", "zoo",
      "hair_salon", "barber_shop", "jail", "soccer_field" },
    -- the jail is drawn twice as wide, in two views
    wide = { jail = { "front", "back" } } },
  { file = "terrain5.png", rows = { 0, 236, 473, 713, 1024 },
    names = { "grassy_field", "parking_lot", "dump", "hill", "river", "pond", "overpass", "traffic_jam" } },
}

local function isNavy(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  return mx < 38 and b + 4 >= r and mx - mn < 24
end

-- Cut one view out of a sheet. Keeps the biggest connected object (plus
-- pieces overlapping it) and drops titles, labels and slivers of the
-- neighbouring views. Returns the cut and glow images and the anchor.
local function sliceView(sheet, rect)
  local w, h = rect[3], rect[4]
  local img = love.image.newImageData(w, h)
  img:paste(sheet, 0, 0, rect[1], rect[2], w, h)
  local px = ffi.cast("uint8_t*", img:getFFIPointer())
  local n = w * h

  local bg = ffi.new("uint8_t[?]", n)
  local queue = ffi.new("int32_t[?]", n)
  local head, tail = 0, 0
  local function try(i)
    if bg[i] == 0 then
      local o = i * 4
      if isNavy(px[o], px[o + 1], px[o + 2]) then
        bg[i] = 1
        queue[tail] = i
        tail = tail + 1
      end
    end
  end
  for x = 0, w - 1 do try(x); try((h - 1) * w + x) end
  for y = 0, h - 1 do try(y * w); try(y * w + w - 1) end
  while head < tail do
    local i = queue[head]
    head = head + 1
    local x, y = i % w, math.floor(i / w)
    if x > 0 then try(i - 1) end
    if x < w - 1 then try(i + 1) end
    if y > 0 then try(i - w) end
    if y < h - 1 then try(i + w) end
  end

  -- Morphological opening: anything only a pixel or two thick (the panels'
  -- frame lines) disappears, so it can't glue the object to the labels.
  local function morph(from, to, erode)
    for i = 0, n - 1 do
      local x, y = i % w, math.floor(i / w)
      local v = erode and 1 or 0
      for dy = -1, 1 do
        for dx = -1, 1 do
          local nx, ny = x + dx, y + dy
          local inside = nx >= 0 and ny >= 0 and nx < w and ny < h
          local s = inside and from[ny * w + nx] or 0
          if erode and s == 0 then v = 0 end
          if not erode and s == 1 then v = 1 end
        end
      end
      to[i] = v
    end
  end
  local solid = ffi.new("uint8_t[?]", n)
  local eroded = ffi.new("uint8_t[?]", n)
  for i = 0, n - 1 do solid[i] = bg[i] == 0 and 1 or 0 end
  morph(solid, eroded, true)
  local opened = ffi.new("uint8_t[?]", n)
  morph(eroded, opened, false)

  -- connected components of what is left
  local label = ffi.new("int32_t[?]", n)
  local comps = {}
  for start = 0, n - 1 do
    if opened[start] == 1 and label[start] == 0 then
      local id = #comps + 1
      local c = { count = 0, x0 = w, y0 = h, x1 = 0, y1 = 0, bright = 0, sat = 0 }
      comps[id] = c
      head, tail = 0, 1
      queue[0] = start
      label[start] = id
      while head < tail do
        local i = queue[head]
        head = head + 1
        local x, y = i % w, math.floor(i / w)
        local o = i * 4
        local mx = math.max(px[o], px[o + 1], px[o + 2])
        c.count = c.count + 1
        c.bright = c.bright + mx
        c.sat = c.sat + mx - math.min(px[o], px[o + 1], px[o + 2])
        if x < c.x0 then c.x0 = x end
        if x > c.x1 then c.x1 = x end
        if y < c.y0 then c.y0 = y end
        if y > c.y1 then c.y1 = y end
        for _, j in ipairs({ x > 0 and i - 1 or -1, x < w - 1 and i + 1 or -1, y > 0 and i - w or -1, y < h - 1 and i + w or -1 }) do
          if j >= 0 and opened[j] == 1 and label[j] == 0 then
            label[j] = id
            queue[tail] = j
            tail = tail + 1
          end
        end
      end
    end
  end
  local main
  for id, c in ipairs(comps) do
    if not main or c.count > comps[main].count then main = id end
  end
  if not main then return nil end
  local m = comps[main]
  local keep = {}
  for id, c in ipairs(comps) do
    local text = c.bright / c.count > 110 and c.sat / c.count < 40
    -- must genuinely overlap the object, not just sit next to it like a title
    local overlaps = c.x1 > m.x0 + 2 and c.x0 < m.x1 - 2 and c.y1 > m.y0 + 4 and c.y0 < m.y1 - 2
    keep[id] = id == main or (overlaps and c.count >= 30 and not text)
  end

  -- kept objects, grown back by two pixels over the original detail
  local kept = ffi.new("uint8_t[?]", n)
  for i = 0, n - 1 do
    local id = label[i]
    kept[i] = (id > 0 and keep[id]) and 1 or 0
  end
  local grown = ffi.new("uint8_t[?]", n)
  morph(kept, grown, false)
  morph(grown, kept, false)
  local alpha = ffi.new("float[?]", n)
  local tmp = ffi.new("float[?]", n)
  for i = 0, n - 1 do
    alpha[i] = (kept[i] == 1 and solid[i] == 1) and 1 or 0
  end
  boxBlur(alpha, tmp, w, h, 1)

  local x0, y0, x1, y1 = w, h, 0, 0
  for i = 0, n - 1 do
    if alpha[i] > 0.5 then
      local x, y = i % w, math.floor(i / w)
      if x < x0 then x0 = x end
      if x > x1 then x1 = x end
      if y < y0 then y0 = y end
      if y > y1 then y1 = y end
    end
  end
  x0, y0 = math.max(0, x0 - 2), math.max(0, y0 - 2)
  x1, y1 = math.min(w - 1, x1 + 2), math.min(h - 1, y1 + 2)
  local cw, ch = x1 - x0 + 1, y1 - y0 + 1

  local cut = love.image.newImageData(cw, ch)
  local glow = love.image.newImageData(cw, ch)
  local cp = ffi.cast("uint8_t*", cut:getFFIPointer())
  local gp = ffi.cast("uint8_t*", glow:getFFIPointer())
  local bottom, left, right = 0, cw, 0
  for y = 0, ch - 1 do
    for x = 0, cw - 1 do
      local si = (y + y0) * w + (x + x0)
      local so, o = si * 4, (y * cw + x) * 4
      local r, g, b = px[so], px[so + 1], px[so + 2]
      local a = alpha[si]
      cp[o], cp[o + 1], cp[o + 2], cp[o + 3] = r, g, b, math.floor(a * 255 + 0.5)
      local lum = (r * 0.3 + g * 0.55 + b * 0.15) / 255
      local e = 0
      if r >= g and g >= b * 0.9 and r > 170 then e = math.max(0, math.min(1, (lum - 0.55) / 0.3)) end
      gp[o], gp[o + 1], gp[o + 2], gp[o + 3] = r, g, b, math.floor(e * a * 255 + 0.5)
      if a > 0.5 then
        if x < left then left = x end
        if x > right then right = x end
        -- the plate's front corner is the lowest point near the middle
        if x > cw * 0.35 and x < cw * 0.65 and y > bottom then bottom = y end
      end
    end
  end
  local plate = right - left + 1
  return cut, glow, {
    w = cw, h = ch, ax = (left + right) / 2, ay = bottom - plate / 4, plate = plate,
  }
end

local function processSheets(src, outDir)
  local lines = { "-- Generated by tools/process_art.lua: town sprite anchors.", "return {" }
  for _, sheetDef in ipairs(SHEETS) do
    local path = src .. "/" .. sheetDef.file
    local f = io.open(path, "rb")
    if f then
      f:close()
      local fd = love.filesystem.newFileData(readFile(path), sheetDef.file)
      local sheet = love.image.newImageData(fd)
      local sw = sheet:getWidth()
      for p, name in ipairs(sheetDef.names) do
        local col, row = (p - 1) % 2, math.floor((p - 1) / 2)
        local px0, pw = col * sw / 2, sw / 2
        local py0 = sheetDef.rows[row + 1]
        local ph = sheetDef.rows[row + 2] - py0
        local views = sheetDef.wide and sheetDef.wide[name] or VIEWS
        local slot = pw / #views
        for v, view in ipairs(views) do
          local rect = { math.floor(px0 + (v - 1) * slot), py0, math.floor(slot), ph }
          local cut, glow, meta = sliceView(sheet, rect)
          if cut then
            local id = name .. "_" .. view
            writeFile(outDir .. "/" .. id .. ".png", cut:encode("png"):getString())
            writeFile(outDir .. "/" .. id .. "_glow.png", glow:encode("png"):getString())
            lines[#lines + 1] = string.format("  %s = { w = %d, h = %d, ax = %.1f, ay = %.1f, plate = %d },",
              id, meta.w, meta.h, meta.ax, meta.ay, meta.plate)
            print(string.format("%-28s %3dx%-3d plate %d", id, meta.w, meta.h, meta.plate))
          end
        end
      end
    end
  end
  lines[#lines + 1] = "}"
  writeFile(outDir .. "/index.lua", table.concat(lines, "\n") .. "\n")
end

local function listPngs(dir)
  local files = {}
  local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.png"')
  for line in p:lines() do files[#files + 1] = line end
  p:close()
  return files
end

local function ensureDir(dir)
  os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
end

return function(src)
  local root = love.filesystem.getSource()
  local buildings, props, town = root .. "/assets/buildings", root .. "/assets/props", root .. "/assets/town"
  ensureDir(buildings)
  ensureDir(props)
  local hasSheets = false
  for _, file in ipairs(listPngs(src)) do
    for _, s in ipairs(SHEETS) do
      if file:lower() == s.file then hasSheets = true end
    end
  end
  if hasSheets then
    ensureDir(town)
    processSheets(src, town)
  end
  for _, file in ipairs(listPngs(src)) do
    local lower = file:lower()
    if lower == "terrain.png" then
      for _, p in ipairs(PROPS) do
        processOne(src, props, { file = file, id = p.id, rect = p.rect })
      end
    elseif ROTATION_SHEETS[lower] then
      for _, v in ipairs(ROTATION_SHEETS[lower]) do
        processOne(src, buildings, { file = file, id = v.id, rect = v.rect })
      end
    elseif not lower:match("^terrain") then
      local id = ART_IDS[lower] or lower:gsub("%.png$", ""):gsub("[%s%-]+", "_")
      processOne(src, buildings, { file = file, id = id })
    end
  end
end
