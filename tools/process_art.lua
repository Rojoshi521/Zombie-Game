-- One-off asset tool: cuts the dark studio background out of the building
-- renders and extracts their lit windows and lamps as a separate glow layer.
--
--   love . --process-art "<folder with artN.png files>"
--
-- Writes assets/buildings/<id>.png and <id>_glow.png into the project.
local ffi = require("ffi")

local SOURCES = {
  { file = "art6.png", id = "coop" },
  { file = "art7.png", id = "cathedral" },
  { file = "art8.png", id = "campus" },
  { file = "art9.png", id = "farmhouse" },
  { file = "art10.png", id = "watertower" },
  { file = "art11.png", id = "ferriswheel" },
  { file = "art12.png", id = "casino" },
  { file = "art13.png", id = "broadcast" },
}

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

  -- Second pass: the grey haze around lamps and smoke that touches the
  -- background fades out with its brightness instead of being kept solid.
  local haze = ffi.new("float[?]", n)
  head = 0
  local function tryHaze(i)
    if bg[i] == 0 then
      local o = i * 4
      local r, g, b = px[o], px[o + 1], px[o + 2]
      local mx, mn = math.max(r, g, b), math.min(r, g, b)
      if mx < 110 and mx - mn < 18 then
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

return function(src)
  local outDir = love.filesystem.getSource() .. "/assets/buildings"
  os.execute('mkdir "' .. outDir:gsub("/", "\\") .. '" 2>nul')
  for _, entry in ipairs(SOURCES) do
    processOne(src, outDir, entry)
  end
end
