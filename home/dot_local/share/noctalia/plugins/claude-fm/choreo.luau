-- The header mascot's dance loop: idle, then headbang, then showtime (the spin),
-- then round again. Driven by the clock, not by audio, so it costs nothing to
-- analyse: headbang keeps its own built-in 80 BPM beat. When the radio is not
-- playing the mascot just idles. Pure module.
local choreo = {}

local IDLE_MS = 4000
local HEADBANG_MS = 8000
local SPIN_MS = 1300
local BEAT_MS = 750 -- 80 BPM, lo-fi pace
local BEAT_FADE_MS = 250
local IDLE_TICK_MS = 500 -- the idle windows are wider than this, so no blink is missed
local PARKED_MS = 60000

choreo.CYCLE_MS = IDLE_MS + HEADBANG_MS + SPIN_MS

local ZEROS = {}
for i = 1, 16 do
  ZEROS[i] = 0
end

-- The fields the mascot styles read.
local function snapshot(over)
  local s = {
    levels = ZEROS, bass = 0, energy = 0, beat = 0, beatCount = 0,
    dropAt = nil, silentMs = 0, playing = true, autoStyle = "idle",
  }
  for k, v in pairs(over or {}) do
    s[k] = v
  end
  return s
end

-- t: ms (any clock). Returns the style name and the snapshot to draw it with.
function choreo.frame(t, playing)
  if not playing then
    return "idle", snapshot()
  end
  local c = t % choreo.CYCLE_MS
  if c < IDLE_MS then
    return "idle", snapshot()
  elseif c < IDLE_MS + HEADBANG_MS then
    local k = c - IDLE_MS
    local n = math.floor(k / BEAT_MS)
    local into = k - n * BEAT_MS
    return "headbang", snapshot({
      beat = math.max(0, 1 - into / BEAT_FADE_MS),
      beatCount = n + 1,
      bass = (n % 2 == 0) and 0.9 or 0.3, -- arms up on alternate beats
    })
  end
  -- showtime: the spin style plays its turn frames from dropAt
  local k = c - IDLE_MS - HEADBANG_MS
  return "spin", snapshot({ dropAt = t - k })
end

-- How soon the next frame is due: slow while idling, animMs while dancing,
-- parked when animation is off (animMs <= 0).
function choreo.interval(t, playing, animMs)
  if animMs <= 0 then
    return PARKED_MS
  end
  local name = choreo.frame(t, playing)
  return name == "idle" and IDLE_TICK_MS or animMs
end

return choreo
