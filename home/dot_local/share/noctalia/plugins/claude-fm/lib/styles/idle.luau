-- Idle: breathing, blinks, glances and a rare wink. Ignores the audio and is
-- a pure function of time, so every entry shows the same Clawd. Every window
-- is wider than the 500 ms idle tick, so a tick can never skip one.
local CYCLE_MS = 3100
local BREATH_MS = 1800
local BLINK_MS = 520

return function(P)
  return {
    name = "idle",
    frame = function(t, a, opts)
      local bucket = math.floor(t / CYCLE_MS)
      local r = t - bucket * CYCLE_MS
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
    end,
  }
end
