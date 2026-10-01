-- Bar widget: the current lyric line, or the track when there's nothing to sing.
local mode = noctalia.getConfig("mode")
local trackFormat = noctalia.getConfig("track_format")
local maxLength = noctalia.getConfig("max_length")
local glyph = noctalia.getConfig("glyph")
local showGlyph = noctalia.getConfig("show_glyph")
local whenPaused = noctalia.getConfig("when_paused")
local hideWhenIdle = noctalia.getConfig("hide_when_idle")
local scroll = noctalia.getConfig("scroll")

local SPEED = 45 -- units per second when looping
local MAX_SPEED = 160
local HOLD_MS = 1500
local FADE_MS = 300
local IDLE_MS = 60000
local GAP = "     "

local function fontScale()
  for _, def in pairs(noctalia.getSetting("widget") or {}) do
    if type(def) == "table" and def.type == "shadow/lyrics:lyrics" then
      return tonumber(def.font_scale) or 1
    end
  end
  return 1
end

-- Plugins can't clip or measure text, so scrolling is put together from a few
-- labels and spacers, and that needs character widths up front. Bar labels
-- are 14 units and 0.6em is the advance of pretty much every monospace font.
-- Wide characters come from a fallback font and take a whole em.
local EM = 14 * fontScale()
local CHAR = 0.6 * EM
local WINDOW = maxLength * CHAR

local player = noctalia.state.get("player") or {}
local lyrics = noctalia.state.get("lyrics") or {}
local line = noctalia.state.get("line") or {}

local hovered = false
local strip = nil -- the text being scrolled, split into characters
local startedAt = 0

local function trackText()
  local text = string.gsub(trackFormat, "{(%a+)}", function(name)
    local value = name == "player" and player.name or player[name]
    return type(value) == "string" and value or ""
  end)
  -- "{title} - {artist}" with no artist shouldn't leave "Title -"
  text = string.gsub(text, "^[%s%-|:/]+", "")
  text = string.gsub(text, "[%s%-|:/]+$", "")
  return text
end

-- nil before the first line and during instrumental breaks, the track shows then
local function lyricText()
  if lyrics.state ~= "synced" or (line.index or 0) < 1 or line.text == "" then
    return nil
  end
  return line.text
end

local function shorten(text)
  local length = utf8.len(text) or #text
  if maxLength <= 0 or length <= maxLength then
    return text
  end
  local cut = utf8.offset(text, maxLength) or (maxLength + 1)
  return noctalia.string.trim(string.sub(text, 1, cut - 1)) .. "…"
end

local function wide(cp)
  return (cp >= 0x1100 and cp <= 0x115F)
    or (cp >= 0x2E80 and cp <= 0xA4CF)
    or (cp >= 0xAC00 and cp <= 0xD7A3)
    or (cp >= 0xF900 and cp <= 0xFAFF)
    or (cp >= 0xFE30 and cp <= 0xFE4F)
    or (cp >= 0xFF00 and cp <= 0xFF60)
    or (cp >= 0xFFE0 and cp <= 0xFFE6)
    or (cp >= 0x1F300 and cp <= 0x1FAFF)
    or (cp >= 0x20000 and cp <= 0x3FFFD)
end

-- combining marks and variation selectors stay with the character before them
local function joins(cp)
  return (cp >= 0x0300 and cp <= 0x036F) or (cp >= 0x200B and cp <= 0x200F) or (cp >= 0xFE00 and cp <= 0xFE0F)
end

local function split(text, into)
  for _, cp in utf8.codes(text) do
    local s = utf8.char(cp)
    if joins(cp) and #into > 0 then
      into[#into].s ..= s
    else
      table.insert(into, { s = s, w = wide(cp) and EM or CHAR })
    end
  end
  return into
end

local function prepare(text, loop)
  local ok, chars = pcall(split, text, {})
  if not ok then
    return nil
  end
  local width = 0
  for _, c in ipairs(chars) do
    width += c.w
  end
  local period = width
  if loop then
    -- "text     text" covers the window wherever the loop is
    split(GAP .. text, chars)
    period += #GAP * CHAR
  end
  return { text = text, loop = loop, chars = chars, width = width, period = period }
end

-- How far into the text we are, the opacity of the first character (it fades
-- out before the text starts moving) and how long until something changes.
local function phase(now)
  if strip.loop then
    local travel = strip.period / SPEED * 1000
    local cycle = HOLD_MS + travel
    local t = (now - startedAt) % cycle
    if t >= HOLD_MS then
      return (t - HOLD_MS) / 1000 * SPEED, nil, 16
    end
    local alpha = math.clamp((HOLD_MS - t) / FADE_MS, 0, 1)
    if now - startedAt >= cycle then
      alpha = math.min(alpha, t / FADE_MS)
    end
    if alpha < 1 then
      return 0, alpha, 16
    end
    return 0, 1, HOLD_MS - FADE_MS - t
  end

  -- a lyric line: hold, scroll so the end shows up while it's still sung, hold
  local finish = strip.width - WINDOW + CHAR
  local total = line.endsAt and line.startedAt and (line.endsAt - line.startedAt)
  local hold, travel = HOLD_MS, finish / SPEED * 1000
  if total then
    hold = math.clamp(total * 0.15, 300, HOLD_MS)
    travel = math.max(total - 2 * hold, finish / MAX_SPEED * 1000)
  end
  local t = now - (line.startedAt or startedAt)
  if t < hold then
    local alpha = math.clamp((hold - t) / FADE_MS, 0, 1)
    return 0, alpha, alpha < 1 and 16 or (hold - FADE_MS - t)
  elseif t < hold + travel then
    local p = (t - hold) / travel
    return finish * p * p * (3 - 2 * p), nil, 16
  end
  return finish, nil, IDLE_MS
end

-- The characters that fit the window at `offset`, as
-- [space][first][middle][last][space]. The first and last ones fade, which
-- stands in for clipping at the edges.
local function window(offset, alpha)
  local chars = strip.chars
  local x, i = 0, 1
  while i <= #chars and x < offset - 0.001 do
    x += chars[i].w
    i += 1
  end
  local first, left = i, math.max(x - offset, 0)
  local last, used = i - 1, left
  while last < #chars and used + chars[last + 1].w <= WINDOW + 0.001 do
    last += 1
    used += chars[last].w
  end
  if last < first then
    return { ui.row({ key = "l", width = WINDOW }, {}) }
  end

  local middle = {}
  for k = first + 1, last - 1 do
    table.insert(middle, chars[k].s)
  end
  local right = math.max(WINDOW - used, 0)
  return {
    ui.row({ key = "l", width = left }, {}),
    ui.label({ key = "a", text = chars[first].s, opacity = alpha or math.clamp(left / CHAR, 0, 1) }),
    ui.label({ key = "m", text = table.concat(middle) }),
    ui.label({ key = "b", text = last > first and chars[last].s or "", opacity = math.clamp(right / CHAR, 0, 1) }),
    ui.row({ key = "r", width = right }, {}),
  }
end

local function render()
  if player.bus == nil or player.status == "Stopped" or player.title == "" then
    strip = nil
    barWidget.setVisible(not hideWhenIdle)
    barWidget.render(ui.row({}, { ui.glyph({ key = "g", name = "music-off" }) }))
    noctalia.setUpdateInterval(IDLE_MS)
    return
  end
  if player.status == "Paused" and whenPaused == "hide" then
    strip = nil
    barWidget.setVisible(false)
    noctalia.setUpdateInterval(IDLE_MS)
    return
  end

  local playing = player.status == "Playing"
  local lyric = nil
  if mode ~= "track" and (playing or whenPaused == "lyric") then
    lyric = lyricText()
  end
  local text = lyric
  if text == nil and (mode ~= "lyrics" or (not playing and whenPaused == "track")) then
    text = trackText()
  end
  if text == nil or text == "" then
    -- nothing to sing right now, and the track is already in the media widget
    strip = nil
    barWidget.setVisible(false)
    noctalia.setUpdateInterval(IDLE_MS)
    return
  end

  local items = {}
  if showGlyph then
    table.insert(items, ui.glyph({ key = "g", name = playing and glyph or "player-pause" }))
  end

  local wait = IDLE_MS
  local moving = playing
    and not barWidget.isVertical()
    and maxLength > 0
    and (scroll == "always" or (scroll == "on_hover" and hovered))
  if moving then
    -- a hover scroll loops whatever is shown, lyrics scroll once per line
    local loop = lyric == nil or scroll == "on_hover"
    if strip == nil or strip.text ~= text or strip.loop ~= loop then
      strip = prepare(text, loop)
      startedAt = noctalia.nowMs()
    end
    moving = strip ~= nil and strip.width > WINDOW + 0.01
  end
  if not moving then
    strip = nil
  end

  if barWidget.isVertical() then
    -- glyph only
  elseif moving then
    local offset, alpha
    offset, alpha, wait = phase(noctalia.nowMs())
    table.insert(items, ui.row({ key = "s", gap = 0, align = "center" }, window(offset, alpha)))
  else
    table.insert(items, ui.label({ key = "t", text = shorten(text) }))
  end

  barWidget.setVisible(true)
  barWidget.render(ui.row({ gap = 4, align = "center" }, items))
  noctalia.setUpdateInterval(math.max(wait, 16))
end

function update()
  render()
end

function onHover(entered)
  hovered = entered
  if scroll == "on_hover" then
    strip = nil
    render()
  end
end

function onClick()
  noctalia.togglePanel("shadow/lyrics:panel")
end

-- Talks to our player directly; `media toggle` would hit whatever the shell
-- considers active, which isn't necessarily the one we're showing.
function onRightClick()
  if player.bus ~= nil then
    noctalia.runAsync({ "busctl", "--user", "call", player.bus, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "PlayPause" })
  end
end

noctalia.state.watch("player", function(value)
  player = value or {}
  render()
end)

noctalia.state.watch("lyrics", function(value)
  lyrics = value or {}
  render()
end)

noctalia.state.watch("line", function(value)
  line = value or {}
  render()
end)

render()
