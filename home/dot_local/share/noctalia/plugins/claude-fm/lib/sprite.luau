-- Clawd sprite: exact glyph tables from Claude Code 2.1.308
-- (docs/clawd-glyphs.json) decoded from quadrant blocks into an 18x6 pixel grid.
-- Pure module: no host globals, no requires.
local sprite = {}

sprite.W = 18
sprite.H = 6

local CELLS = 9

local ARMS = {
  ["down"] = { r1L = " ▐", r1R = "", r2L = "▝▜", r2R = "█▀" },
  ["up"] = { r1L = "▗▟", r1R = "▄", r2L = " ▜", r2R = "█▘" },
  ["one-up"] = { r1L = " ▐", r1R = "▄", r2L = "▝▜", r2R = "█▘" },
}

-- Eye-row cells, starting at column 2. "▂" is a closed lid: its cell's upper
-- sub-pixels are body and its lower sub-pixels are marked "l" (half body, half
-- dark line; the renderer splits that row).
local EYES = {
  ["open"] = "▛███▛█",
  ["left"] = "▟███▟█",
  ["right"] = "█▟███▟",
  ["closed"] = "▂███▂█",
  ["wink"] = "▛███▂█",
}

local FEET = {
  ["both"] = " ▝▝   ▝▝ ",
  ["left"] = " ▝▝      ",
  ["right"] = "      ▝▝ ",
}

local BODY_ROW = "█████"

-- Whole-sprite turn-around frames; from/to is the column range where an
-- unset quadrant is an eye instead of empty space.
local TURN_FRAMES = {
  ["right-12"] = { { glyphs = " ▐█▜██▛█ ", from = 2, to = 8 }, { glyphs = "▝▜██████▀", from = 2, to = 7 }, { glyphs = " ▝▝   ▝▝ ", from = 0, to = 0 } },
  ["right-30"] = { { glyphs = "  █▛██▛▌ ", from = 2, to = 7 }, { glyphs = " ▝█████▛ ", from = 2, to = 7 }, { glyphs = "  ▘▘  ▘▘ ", from = 0, to = 0 } },
  ["right-55"] = { { glyphs = "  ▐█▛█▜  ", from = 3, to = 7 }, { glyphs = "  ▐████  ", from = 3, to = 7 }, { glyphs = "  ▝▝ ▝▝  ", from = 0, to = 0 } },
  ["right-75"] = { { glyphs = "   ██▛▌  ", from = 3, to = 6 }, { glyphs = "   ███▌  ", from = 3, to = 6 }, { glyphs = "   ▘  ▘  ", from = 0, to = 0 } },
  ["edge"] = { { glyphs = "   ▐██   ", from = 4, to = 6 }, { glyphs = "   ▐██   ", from = 4, to = 6 }, { glyphs = "   ▝ ▝   ", from = 0, to = 0 } },
  ["back-105"] = { { glyphs = "   ███▌  ", from = 3, to = 6 }, { glyphs = "   ███▌  ", from = 3, to = 6 }, { glyphs = "   ▘  ▘  ", from = 0, to = 0 } },
  ["back-125"] = { { glyphs = "  ▐████  ", from = 3, to = 7 }, { glyphs = "  ▐████  ", from = 3, to = 7 }, { glyphs = "  ▝▝ ▝▝  ", from = 0, to = 0 } },
  ["back-150"] = { { glyphs = "  █████▌ ", from = 2, to = 7 }, { glyphs = " ▝█████▛ ", from = 2, to = 7 }, { glyphs = "  ▘▘  ▘▘ ", from = 0, to = 0 } },
  ["back"] = { { glyphs = " ▐██████ ", from = 2, to = 8 }, { glyphs = "▝▜██████▀", from = 2, to = 7 }, { glyphs = " ▝▝   ▝▝ ", from = 0, to = 0 } },
  ["left-75"] = { { glyphs = "   ▛██▌  ", from = 3, to = 6 }, { glyphs = "   ███▌  ", from = 3, to = 6 }, { glyphs = "   ▘  ▘  ", from = 0, to = 0 } },
  ["left-55"] = { { glyphs = "  ▐▜▛██  ", from = 3, to = 7 }, { glyphs = "  ▐████  ", from = 3, to = 7 }, { glyphs = "  ▝▝ ▝▝  ", from = 0, to = 0 } },
  ["left-30"] = { { glyphs = "  ▛██▛█▌ ", from = 2, to = 7 }, { glyphs = " ▝█████▛ ", from = 2, to = 7 }, { glyphs = "  ▘▘  ▘▘ ", from = 0, to = 0 } },
  ["left-12"] = { { glyphs = " ▐▛███▜█ ", from = 2, to = 8 }, { glyphs = "▝▜██████▀", from = 2, to = 7 }, { glyphs = " ▝▝   ▝▝ ", from = 0, to = 0 } },
}

sprite.TURN = {
  "right-12", "right-30", "right-55", "right-75", "edge",
  "back-105", "back-125", "back-150", "back",
  "left-75", "left-55", "left-30", "left-12",
}

-- Quadrant masks in {UL, UR, LL, LR} order.
local QUAD = {
  [" "] = { 0, 0, 0, 0 },
  ["▘"] = { 1, 0, 0, 0 },
  ["▝"] = { 0, 1, 0, 0 },
  ["▖"] = { 0, 0, 1, 0 },
  ["▗"] = { 0, 0, 0, 1 },
  ["▀"] = { 1, 1, 0, 0 },
  ["▄"] = { 0, 0, 1, 1 },
  ["▌"] = { 1, 0, 1, 0 },
  ["▐"] = { 0, 1, 0, 1 },
  ["▛"] = { 1, 1, 1, 0 },
  ["▜"] = { 1, 1, 0, 1 },
  ["▙"] = { 1, 0, 1, 1 },
  ["▟"] = { 0, 1, 1, 1 },
  ["▚"] = { 1, 0, 0, 1 },
  ["▞"] = { 0, 1, 1, 0 },
  ["█"] = { 1, 1, 1, 1 },
}

local LID = "▂"

-- One UTF-8 character per match (the data contains no NUL bytes).
local UTF8_CHAR = "[\1-\127\194-\244][\128-\191]*"

local function cells(str)
  local out = {}
  for ch in str:gmatch(UTF8_CHAR) do
    out[#out + 1] = ch
  end
  return out
end

local function pad(str)
  local n = #cells(str)
  if n > CELLS then
    error("sprite row has " .. n .. " cells, max " .. CELLS)
  end
  return str .. string.rep(" ", CELLS - n)
end

local function lookup(tbl, name, default, what)
  local key = name or default
  local v = tbl[key]
  if v == nil then
    error("unknown " .. what .. ": " .. tostring(key), 3)
  end
  return v
end

function sprite.pose(p)
  p = p or {}
  local arms = lookup(ARMS, p.arms, "down", "arms")
  local eyes = lookup(EYES, p.eyes, "open", "eyes")
  local feet = lookup(FEET, p.feet, "both", "feet")
  return {
    rows = {
      { glyphs = pad(arms.r1L .. eyes .. arms.r1R), from = 2, to = 2 + #cells(eyes) },
      { glyphs = pad(arms.r2L .. BODY_ROW .. arms.r2R), from = 2, to = 2 + #cells(BODY_ROW) },
      { glyphs = pad(feet), from = 0, to = 0 },
    },
  }
end

function sprite.turn(name)
  local rows = lookup(TURN_FRAMES, name, nil, "turn frame")
  return { rows = rows }
end

function sprite.grid(frame)
  local px = {}
  for y = 1, sprite.H do
    px[y] = {}
  end
  for row = 0, 2 do
    local r = frame.rows[row + 1]
    for col, ch in ipairs(cells(r.glyphs)) do
      local q = QUAD[ch]
      if not q and ch ~= LID then
        error("unknown glyph: " .. ch)
      end
      local c = col - 1
      for i = 0, 3 do
        local x = 2 * c + (i % 2)
        local y = 2 * row + math.floor(i / 2)
        local mark
        if ch == LID then
          mark = i < 2 and "#" or "l"
        elseif q[i + 1] == 1 then
          mark = "#"
        elseif c >= r.from and c < r.to then
          mark = "o"
        else
          mark = "."
        end
        px[y + 1][x + 1] = mark
      end
    end
  end
  local out = {}
  for y = 1, sprite.H do
    out[y] = table.concat(px[y])
  end
  return out
end

return sprite
