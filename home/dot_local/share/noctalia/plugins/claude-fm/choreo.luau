--!nonstrict
-- The header mascot's dance loop: idle, then headbang, then showtime (the spin),
-- then round again. Driven by the clock, not by audio, so it costs nothing to
-- analyse: headbang keeps its own built-in 80 BPM beat. When the radio is not
-- playing the mascot just idles. Pure module: it returns scenes for lib/scene.
local choreo = {}

local IDLE_MS = 4000
local HEADBANG_MS = 8000
local SPIN_MS = 1300
local BEAT_MS = 750 -- 80 BPM, lo-fi pace
local DIP_MS = 150 -- the body dips this long on each beat
local IDLE_TICK_MS = 500 -- the idle windows are wider than this, so no blink is missed
local PARKED_MS = 60000

-- Idle: breathing, blinks, glances and a rare wink, all pure functions of time.
local BREATH_MS = 1800
local LOOK_CYCLE_MS = 3100
local BLINK_MS = 520

choreo.CYCLE_MS = IDLE_MS + HEADBANG_MS + SPIN_MS

local function idle(t)
  local bucket = math.floor(t / LOOK_CYCLE_MS)
  local r = t - bucket * LOOK_CYCLE_MS
  local eyes = "open"
  if bucket % 13 == 5 and r >= 400 and r < 1000 then
    eyes = "wink"
  elseif (bucket * 7 + 3) % 11 < 5 and r < BLINK_MS then
    eyes = "closed"
  elseif bucket % 4 == 1 and r >= 1000 and r < 1700 then
    eyes = (bucket % 8 == 1) and "left" or "right"
  end
  return {
    pose = { eyes = eyes },
    dy = (math.floor(t / BREATH_MS) % 2 == 0) and 0 or 1,
  }
end

-- t: ms on any clock. "idle" | "headbang" | "spin".
function choreo.stage(t, playing)
  if not playing then
    return "idle"
  end
  local c = t % choreo.CYCLE_MS
  if c < IDLE_MS then
    return "idle"
  elseif c < IDLE_MS + HEADBANG_MS then
    return "headbang"
  end
  return "spin"
end

-- The scene to draw at t: { pose, dy } or, while spinning, { turnPhase } (0..1).
function choreo.scene(t, playing)
  local stage = choreo.stage(t, playing)
  if stage == "idle" then
    return idle(t)
  end
  local k = t % choreo.CYCLE_MS - IDLE_MS
  if stage == "headbang" then
    local beat = math.floor(k / BEAT_MS)
    return {
      pose = { arms = (beat % 2 == 0) and "up" or "down", eyes = "closed" }, -- arms up on alternate beats
      dy = (k - beat * BEAT_MS < DIP_MS) and 1 or 0,
    }
  end
  return { turnPhase = (k - HEADBANG_MS) / SPIN_MS }
end

-- How soon the next frame is due: slow while idling, animMs while dancing,
-- parked when animation is off (animMs <= 0).
function choreo.interval(t, playing, animMs)
  if animMs <= 0 then
    return PARKED_MS
  end
  return choreo.stage(t, playing) == "idle" and IDLE_TICK_MS or animMs
end

return choreo
