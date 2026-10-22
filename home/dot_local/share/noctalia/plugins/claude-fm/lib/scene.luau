--!nonstrict
-- Scene composer: rasterises a scene (a sprite pose or turn frame, shifted by
-- dx/dy) onto a pixel canvas, then emits it as a merged-run ui tree. A view is a
-- window in sprite-origin sub-pixels (the sprite is x 0..17, y 0..5).
-- Pure module: sprite and ui are passed in.
local scene = {}

scene.PALETTE = {
  body = "#D97757",
  eye = "#141414",
}

local TURN_FRAMES = 13
local LID = "lid" -- half body, half eye colour: toUi splits its row in two
-- Transparent cells get an explicit transparent fill: in Noctalia a box without
-- a fill paints black, and an omitted prop is not reset on a keyed node.
local TRANSPARENT = "#00000000"
local SPRITE_COLORS = { ["#"] = "body", ["o"] = "eye", ["l"] = LID }

local function round(v)
  return math.floor(v + 0.5)
end

local function finite(v)
  return type(v) == "number" and v == v and v > -1e9 and v < 1e9
end

local function newCanvas(view)
  local rows = {}
  for y = 1, view.h do
    local row = {}
    for x = 1, view.w do
      row[x] = false
    end
    rows[y] = row
  end
  return { w = view.w, h = view.h, rows = rows }
end

local function frameFor(sc, sprite)
  if sc.turnPhase ~= nil and finite(sc.turnPhase) then
    local idx = math.floor(sc.turnPhase * TURN_FRAMES) + 1
    idx = math.max(1, math.min(TURN_FRAMES, idx))
    return sprite.turn(sprite.TURN[idx])
  end
  return sprite.pose(sc.pose)
end

function scene.compose(sc, sprite, view)
  local canvas = newCanvas(view)
  local dx = finite(sc.dx) and round(sc.dx) or 0
  local dy = finite(sc.dy) and round(sc.dy) or 0

  for sy, line in ipairs(sprite.grid(frameFor(sc, sprite))) do
    for sx = 1, #line do
      local color = SPRITE_COLORS[line:sub(sx, sx)]
      if color then
        local cx = (sx - 1) + dx - view.x + 1
        local cy = (sy - 1) + dy - view.y + 1
        if cx >= 1 and cx <= canvas.w and cy >= 1 and cy <= canvas.h then
          canvas.rows[cy][cx] = color
        end
      end
    end
  end

  return canvas
end

-- One ui.row of merged runs; transparent runs are boxes with a transparent fill.
-- lidAs is the colour key a "lid" cell takes in this row.
local function emitRow(ui, key, line, p, height, lidAs)
  local function colorAt(x)
    local c = line[x]
    return c == LID and lidAs or c
  end
  local boxes = {}
  local x = 1
  while x <= #line do
    local color = colorAt(x)
    local n = 1
    while x + n <= #line and colorAt(x + n) == color do
      n = n + 1
    end
    boxes[#boxes + 1] = ui.box({
      key = key .. "x" .. (#boxes + 1),
      width = n * p,
      height = height,
      fill = color and scene.PALETTE[color] or TRANSPARENT,
    })
    x = x + n
  end
  return ui.row({ key = key, gap = 0 }, boxes)
end

local function hasLid(line)
  for x = 1, #line do
    if line[x] == LID then
      return true
    end
  end
  return false
end

-- A sub-pixel is p wide and 2p tall. A canvas row holding lid cells becomes two
-- p-tall rows: body on top, the dark eye line underneath.
function scene.toUi(canvas, p, ui)
  local rows = {}
  for y = 1, canvas.h do
    local line = canvas.rows[y]
    if hasLid(line) then
      rows[#rows + 1] = emitRow(ui, "y" .. y, line, p, p, "body")
      rows[#rows + 1] = emitRow(ui, "y" .. y .. "b", line, p, p, "eye")
    else
      rows[#rows + 1] = emitRow(ui, "y" .. y, line, p, 2 * p, nil)
    end
  end
  return ui.column({ gap = 0 }, rows)
end

return scene
