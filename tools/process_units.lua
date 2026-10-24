-- Asset tool: cuts survivor and zombie portraits out of their dark studio
-- background (and the patch of dirt the survivors stand on) and shrinks them
-- to sprite size.
--
--   love . --process-units "<folder or PNG>" ["<another>" ...]
--   love . --process-units --sheet <name> "<walk sheet PNG>"
--
-- Every <name><n>.png (combat1.png, zombie7.png, ...) becomes
-- assets/units/<name><n>.png, with each sprite's size, foot anchor and head
-- position written to assets/units/index.lua.
local ffi = require("ffi")

local OUT_H = 168 -- sprite height in pixels; units are drawn at about a quarter of that

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

local function listPngs(dir)
  local files = {}
  local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.png"')
  for line in p:lines() do files[#files + 1] = line end
  p:close()
  return files
end

-- Cuts the figure out of img. Returns the cut-out ImageData, its size, and
-- the foot and head x positions in it.
local function cutFigure(img, hasDirt, footMode)
  local w, h = img:getDimensions()
  local px = ffi.cast("uint8_t*", img:getFFIPointer())
  local n = w * h

  local function maxc(i)
    local o = i * 4
    return math.max(px[o], px[o + 1], px[o + 2]), math.min(px[o], px[o + 1], px[o + 2])
  end
  local function roughness(i)
    local x, y = i % w, math.floor(i / w)
    local o = i * 4
    local best = 0
    for _, j in ipairs({ x < w - 1 and i + 1 or i - 1, y < h - 1 and i + w or i - w,
                         x > 0 and i - 1 or i + 1, y > 0 and i - w or i + w }) do
      local q = j * 4
      local d = math.max(math.abs(px[o] - px[q]), math.abs(px[o + 1] - px[q + 1]), math.abs(px[o + 2] - px[q + 2]))
      if d > best then best = d end
    end
    return best
  end

  -- 1. flood the smooth dark background in from the borders; the black
  -- outline round the figure has hard edges, which stops the fill
  local bg = ffi.new("uint8_t[?]", n)
  local queue = ffi.new("int32_t[?]", n)
  local head, tail = 0, 0
  local function push(i)
    bg[i] = 1
    queue[tail] = i
    tail = tail + 1
  end
  local function isBg(i)
    local mx, mn = maxc(i)
    return mx < 48 and mx - mn < 22 and roughness(i) <= 7
  end
  for x = 0, w - 1 do
    if isBg(x) then push(x) end
    if isBg((h - 1) * w + x) then push((h - 1) * w + x) end
  end
  for y = 0, h - 1 do
    if isBg(y * w) then push(y * w) end
    if isBg(y * w + w - 1) then push(y * w + w - 1) end
  end
  local function flood(test)
    while head < tail do
      local i = queue[head]
      head = head + 1
      local x, y = i % w, math.floor(i / w)
      if x > 0 and bg[i - 1] == 0 and test(i - 1) then push(i - 1) end
      if x < w - 1 and bg[i + 1] == 0 and test(i + 1) then push(i + 1) end
      if y > 0 and bg[i - w] == 0 and test(i - w) then push(i - w) end
      if y < h - 1 and bg[i + w] == 0 and test(i + w) then push(i + w) end
    end
  end
  flood(isBg)

  -- bounding box of the figure so far
  local function bbox()
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        if bg[y * w + x] == 0 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    return x0, y0, x1, y1
  end
  local x0, y0, x1, y1 = bbox()

  -- 2. the dirt under the feet. It is as dark and brown as the boots, so it
  -- is told apart by shape: each leg is followed down from the knees, row by
  -- row, and may only widen slowly (legs splay, boots flare), while the patch
  -- of ground spreads out sideways far faster. Anything outside the tracked
  -- legs below the knees goes.
  local figH = y1 - y0 + 1
  local kneeY = y0 + math.floor(figH * 0.62)
  local function runs(y)
    local segs, start = {}, nil
    for x = 0, w do
      local solid = x < w and bg[y * w + x] == 0
      if solid and not start then start = x end
      if not solid and start then
        segs[#segs + 1] = { start, x - 1 }
        start = nil
      end
    end
    return segs
  end
  if hasDirt then
    local startY = kneeY
    local legs = {}
    for _, s in ipairs(runs(startY)) do
      if s[2] - s[1] > figH * 0.015 then legs[#legs + 1] = { s[1], s[2], s[1] - figH * 0.07, s[2] + figH * 0.07 } end
    end
    local GROW = 0.75 -- pixels per row on each side
    for y = startY + 1, y1 do
      local row = runs(y)
      local nextLegs = {}
      for _, l in ipairs(legs) do
        -- the solid runs in this row that touch the leg, clipped to how far
        -- the leg may have grown since the last row
        local a, b
        for _, s in ipairs(row) do
          if s[2] >= l[1] - 1 and s[1] <= l[2] + 1 then
            a = math.min(a or s[1], s[1])
            b = math.max(b or s[2], s[2])
          end
        end
        if a then
          nextLegs[#nextLegs + 1] = { math.max(a, l[1] - GROW, l[3]), math.min(b, l[2] + GROW, l[4]), l[3], l[4] }
        end
      end
      for x = 0, w - 1 do
        local i = y * w + x
        if bg[i] == 0 then
          local keep = false
          for _, l in ipairs(nextLegs) do
            if x >= l[1] and x <= l[2] then
              keep = true
              break
            end
          end
          if not keep then bg[i] = 1 end
        end
      end
      legs = nextLegs
    end
  end

  -- 3. keep the figure, drop the specks of dirt left behind: the biggest
  -- connected piece, plus anything that reaches above the dirt
  local comp = ffi.new("int32_t[?]", n)
  local sizes, tops = {}, {}
  local nc = 0
  for s = 0, n - 1 do
    if bg[s] == 0 and comp[s] == 0 then
      nc = nc + 1
      comp[s] = nc
      head, tail = 0, 1
      queue[0] = s
      local size, top = 0, h
      while head < tail do
        local i = queue[head]
        head = head + 1
        size = size + 1
        local x, y = i % w, math.floor(i / w)
        if y < top then top = y end
        local function visit(j)
          if bg[j] == 0 and comp[j] == 0 then
            comp[j] = nc
            queue[tail] = j
            tail = tail + 1
          end
        end
        if x > 0 then visit(i - 1) end
        if x < w - 1 then visit(i + 1) end
        if y > 0 then visit(i - w) end
        if y < h - 1 then visit(i + w) end
      end
      sizes[nc], tops[nc] = size, top
    end
  end
  local biggest = 1
  for c = 1, nc do
    if sizes[c] > sizes[biggest] then biggest = c end
  end
  for i = 0, n - 1 do
    local c = comp[i]
    if c > 0 and c ~= biggest and (tops[c] >= kneeY or sizes[c] < 200) then bg[i] = 1 end
  end
  x0, y0, x1, y1 = bbox()

  -- soft alpha edge
  local cw, ch = x1 - x0 + 7, y1 - y0 + 7
  local cut = love.image.newImageData(cw, ch)
  local cp = ffi.cast("uint8_t*", cut:getFFIPointer())
  for y = 0, ch - 1 do
    for x = 0, cw - 1 do
      local sx, sy = x + x0 - 3, y + y0 - 3
      local o = (y * cw + x) * 4
      if sx >= 0 and sy >= 0 and sx < w and sy < h then
        local si = sy * w + sx
        local so = si * 4
        cp[o], cp[o + 1], cp[o + 2] = px[so], px[so + 1], px[so + 2]
        cp[o + 3] = bg[si] == 0 and 255 or 0
      end
    end
  end

  -- foot anchor: the middle of the lowest tenth of the figure; head: the
  -- middle of the top twelfth
  local function band(fy0, fy1)
    local sum, cnt = 0, 0
    for y = math.floor(fy0), math.floor(fy1) do
      for x = 0, cw - 1 do
        if cp[(y * cw + x) * 4 + 3] > 0 then
          sum = sum + x
          cnt = cnt + 1
        end
      end
    end
    return cnt > 0 and sum / cnt or cw / 2
  end
  -- midway between the outermost solid pixels of a band: in a stride the
  -- feet are far apart, and the body sits between them
  local function span(fy0, fy1)
    local a, b
    for y = math.floor(fy0), math.floor(fy1) do
      for x = 0, cw - 1 do
        if cp[(y * cw + x) * 4 + 3] > 0 then
          a = math.min(a or x, x)
          b = math.max(b or x, x)
        end
      end
    end
    return a and (a + b) / 2 or cw / 2
  end
  local footX = footMode == "span" and span(ch * 0.85, ch - 1) or band(ch * 0.9, ch - 1)
  local headX = band(0, ch * 0.08)
  return cut, cw, ch, footX, headX
end

-- Shrinks a cut-out by k and writes it as assets/units/<id>.png. u is the
-- height of a whole standing figure in the output, for frames of a sheet
-- that are drawn at one shared scale.
local function emit(cut, cw, ch, footX, headX, k, id, outDir, u)
  -- downscale on the GPU; "replace" keeps straight (non-premultiplied) alpha
  local image = love.graphics.newImage(cut, { mipmaps = true })
  image:setFilter("linear", "linear")
  image:setMipmapFilter("linear")
  local ow, oh = math.max(1, math.floor(cw * k + 0.5)), math.max(1, math.floor(ch * k + 0.5))
  local canvas = love.graphics.newCanvas(ow, oh)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, 0, 0, 0, ow / cw, oh / ch)
  love.graphics.setBlendMode("alpha")
  love.graphics.setCanvas()

  local outData = canvas:newImageData()
  writeFile(outDir .. "/" .. id .. ".png", outData:encode("png"):getString())
  outData:release()
  canvas:release()
  image:release()
  cut:release()
  collectgarbage()
  print(string.format("%-14s %3dx%-3d  from %dx%d", id, ow, oh, cw, ch))
  return {
    w = ow, h = oh, u = u,
    ax = math.floor(footX * k + 0.5), ay = oh - math.floor(3 * k + 0.5),
    hx = math.floor(headX * k + 0.5), hy = math.floor(ch * 0.06 * k + 0.5),
  }
end

local function processOne(path, file, outDir)
  local hasDirt = not file:lower():match("^zombie") -- the survivors stand on a patch of ground
  local img = love.image.newImageData(love.filesystem.newFileData(readFile(path), file))
  local cut, cw, ch, footX, headX = cutFigure(img, hasDirt)
  img:release()
  local id = file:lower():gsub("%.png$", "")
  return id, emit(cut, cw, ch, footX, headX, OUT_H / ch, id, outDir)
end

-- A walk sheet: 4 columns (front, side, three-quarter front, back) by 2
-- rows (left foot forward, right foot forward) on a plain background, each
-- figure facing screen-right. Cells become <name>_<view><row>.
local SHEET_VIEWS = { "front", "side", "back", "q" }

local function processSheet(path, name, outDir, index)
  local img = love.image.newImageData(love.filesystem.newFileData(readFile(path), "sheet.png"))
  local w, h = img:getDimensions()
  local cw, chh = math.floor(w / 4), math.floor(h / 2)
  local fig = math.floor(chh * 0.86) -- the label under each figure is cropped off
  local cuts, tallest = {}, 0
  for row = 1, 2 do
    for col = 1, 4 do
      local cell = love.image.newImageData(cw, fig)
      cell:paste(img, 0, 0, (col - 1) * cw, (row - 1) * chh, cw, fig)
      local c = { cutFigure(cell, false, "span") }
      cell:release()
      c.id = name .. "_" .. SHEET_VIEWS[col] .. row
      cuts[#cuts + 1] = c
      tallest = math.max(tallest, c[3])
    end
  end
  img:release()
  -- one scale for every frame, so the figure does not grow and shrink as it walks
  local k = OUT_H / tallest
  for _, c in ipairs(cuts) do
    index[c.id] = emit(c[1], c[2], c[3], c[4], c[5], k, c.id, outDir, OUT_H)
  end
end

-- Arguments are folders or single PNGs. LÃ–VE runs out of memory after a few
-- dozen full-size portraits in one go, so a big batch can be fed one file per
-- run: each run merges its sprites into the existing index.
return function(paths)
  io.stdout:setvbuf("no")
  local root = love.filesystem.getSource()
  local outDir = root .. "/assets/units"
  os.execute('mkdir "' .. outDir:gsub("/", "\\") .. '" 2>nul')
  local index = {}
  local ok, old = pcall(dofile, outDir .. "/index.lua")
  if ok and type(old) == "table" then index = old end
  local sheetName
  for _, path in ipairs(paths) do
    local files = {}
    if path == "--sheet" then
      sheetName = true
    elseif sheetName == true then
      sheetName = path
    elseif sheetName then
      processSheet(path, sheetName, outDir, index)
      sheetName = nil
    elseif path:lower():match("%.png$") then
      local dir, file = path:match("^(.*)[/\\]([^/\\]+)$")
      files[1] = { dir, file }
    else
      for _, file in ipairs(listPngs(path)) do files[#files + 1] = { path, file } end
    end
    for _, f in ipairs(files) do
      -- elite concept sheets are reference only
      if not f[2]:lower():match("^elite") then
        local id, info = processOne(f[1] .. "/" .. f[2], f[2], outDir)
        index[id] = info
      end
    end
  end
  local ids = {}
  for id in pairs(index) do ids[#ids + 1] = id end
  table.sort(ids)
  local lines = { "-- generated by tools/process_units.lua: w, h, foot anchor (ax, ay), head (hx, hy)", "return {" }
  for _, id in ipairs(ids) do
    local i = index[id]
    lines[#lines + 1] = string.format("  %s = { w = %d, h = %d, ax = %d, ay = %d, hx = %d, hy = %d%s },",
      id, i.w, i.h, i.ax, i.ay, i.hx, i.hy, i.u and (", u = " .. i.u) or "")
  end
  lines[#lines + 1] = "}"
  writeFile(outDir .. "/index.lua", table.concat(lines, "\n") .. "\n")
end
