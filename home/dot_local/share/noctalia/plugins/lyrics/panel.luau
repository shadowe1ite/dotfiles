-- Panel: just the lyrics, gliding up as the song goes on.
local SLOT = 56 -- every line gets the same height, wrapped or not
local BEFORE = 2
local AFTER = 4 -- the last of these only peeks in at the bottom
local SLIDE_MS = 500

local player = noctalia.state.get("player") or {}
local lyrics = noctalia.state.get("lyrics") or {}
local line = noctalia.state.get("line") or {}
local open = false

local texts = {} -- the lyrics without the empty lines that mark breaks
local times = {}
local places = {} -- line index -> position in `texts` of the last line sung by then
local current = 0
local singing = false -- false during a break, nothing is lit then
local slideAt = nil

local function rebuild()
  texts, times, places = {}, {}, {}
  for i, l in ipairs(lyrics.lines or {}) do
    if l.text ~= "" then
      table.insert(texts, l.text)
      table.insert(times, l.time)
    end
    places[i] = #texts
  end
end

local function follow(animate)
  local i = line.index or 0
  local target = places[i] or 0
  singing = i > 0 and line.text ~= ""
  if animate and open and target == current + 1 then
    slideAt = noctalia.nowMs()
    panel.setNeedsFrameTick(true)
  elseif target ~= current then
    slideAt = nil
  end
  current = target
end

local function progress()
  if slideAt == nil then
    return 1
  end
  local p = (noctalia.nowMs() - slideAt) / SLIDE_MS
  if p >= 1 then
    slideAt = nil
    panel.setNeedsFrameTick(false)
    return 1
  end
  p = math.max(p, 0)
  return 1 - (1 - p) ^ 3
end

-- Sung lines stay readable, upcoming ones sit further back. `d` is the
-- distance from the line being sung, fractional while sliding.
local function brightness(d)
  if d <= 0 then
    return 1 - 0.5 * math.min(-d, 1) - 0.12 * math.max(-d - 1, 0)
  end
  return 1 - 0.62 * math.min(d, 1) - 0.08 * math.max(d - 1, 0)
end

local function slot(k, height, d, fade)
  local text = texts[k]
  if text == nil then
    return ui.column({ key = "s" .. k, height = height }, {})
  end
  local seek = function()
    noctalia.state.set("seek", { time = times[k], at = noctalia.nowMs() })
  end
  return ui.column({ key = "s" .. k, height = height, justify = "center", onClick = seek }, {
    ui.label({
      text = text,
      maxLines = 2,
      fontSize = 18,
      fontWeight = "bold",
      opacity = math.max(brightness(d), 0.08) * fade,
    }),
  })
end

local function synced()
  local p = progress()
  -- during a break the last line sung counts as half a line ago
  local at = current - 1 + p + (singing and 0 or 0.5)
  local rows = {}
  local first, last = current - BEFORE, current + AFTER
  if p < 1 then
    -- the line leaving at the top shrinks out of the way and fades
    table.insert(rows, slot(first - 1, SLOT * (1 - p), first - 1 - at, math.max(1 - p / 0.3, 0)))
  end
  for k = first, last - 1 do
    table.insert(rows, slot(k, SLOT, k - at, 1))
  end
  -- and the newest one grows in at the bottom
  table.insert(rows, slot(last, SLOT * p, last - at, p))
  return ui.column({ flexGrow = 1, justify = "center" }, {
    ui.column({ key = "lines", gap = 0 }, rows),
  })
end

local function plain()
  local rows = {}
  for text in string.gmatch((lyrics.text or "") .. "\n", "(.-)\r?\n") do
    table.insert(rows, ui.label({ text = text, fontSize = 16, fontWeight = "bold", opacity = 0.7 }))
  end
  return ui.scroll({ flexGrow = 1, gap = 8 }, rows)
end

local function message(text)
  return ui.column({ flexGrow = 1, justify = "center", align = "center" }, {
    ui.label({ text = text, color = "on_surface_variant", textAlign = "center" }),
  })
end

local function render()
  if not open then
    return
  end
  local body
  if player.bus == nil or player.title == "" then
    body = message(noctalia.tr("panel.idle"))
  elseif lyrics.state == "synced" then
    body = synced()
  elseif lyrics.state == "plain" then
    body = plain()
  else
    body = message(noctalia.tr("panel." .. (lyrics.state or "none")))
  end
  panel.render(ui.column({ flexGrow = 1 }, { body }))
end

function onOpen()
  open = true
  rebuild()
  follow(false)
  render()
end

function onClose()
  open = false
  slideAt = nil
  panel.setNeedsFrameTick(false)
end

function onFrameTick()
  render()
end

noctalia.state.watch("player", function(value)
  player = value or {}
  render()
end)

noctalia.state.watch("lyrics", function(value)
  lyrics = value or {}
  rebuild()
  follow(false)
  render()
end)

noctalia.state.watch("line", function(value)
  line = value or {}
  follow(true)
  render()
end)
