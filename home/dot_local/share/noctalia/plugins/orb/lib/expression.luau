--!nonstrict
-- How the orb looks while Hermes is in some state, instead of a status dot: asleep while
-- Hermes is out of reach, awake and lively once it is connected, and its own look for
-- thinking, working, needing you, a reply waiting, a finished run and a failed one.
-- Pure and time-driven, like Life: pick() names the expression, pose(name, t) says what
-- the face does at time t (ms), layered over Life's blinks and glances.
--
-- A pose: { lid?, lookX?, lookY?, mood?, sx, sy, dy, z?, nextIn }
--   lid           cap on how open the eyes are (0..1); nil leaves Life's
--   lookX, lookY  gaze (-1..1); nil leaves Life's glances
--   mood          face mood ("happy", "surprised", "sleepy"); nil leaves Life's
--   sx, sy        squash and stretch, multiplied into the orb's own
--   dy            hop, in ball sizes (negative is up)
--   z             0..1 while a sleeping "z" drifts up and fades; nil without one
--   nextIn        ms until the pose changes again (0: it is moving now)

local M = {}

local TAU = 2 * math.pi

-- input = { link, pet, nudge }: link from the service ("online", "degraded", "offline",
-- "auth", "error", "unknown"), pet from activity.pet, nudge "approval" | "unread" | nil.
function M.pick(input)
  local link, pet, nudge = input.link, input.pet, input.nudge
  if link == "auth" or link == "offline" or link == "error" then
    return "sleep"
  elseif nudge == "approval" or pet == "waiting" then
    return "attention"
  elseif pet == "failed" then
    return "failed"
  elseif pet == "wave" then
    return "happy"
  elseif pet == "run" then
    return "work"
  elseif pet == "review" then
    return "think"
  elseif nudge == "unread" then
    return "unread"
  elseif link == "degraded" then
    return "drowsy"
  end
  return "awake"
end

-- A hop of `ms` every `every` ms: height (0..1) now, and ms until the next one starts.
local function hop(t, every, ms)
  local p = t % every
  if p < ms then
    return math.sin(p / ms * math.pi), 0
  end
  return 0, every - p
end

local function still(o)
  o.sx = o.sx or 1
  o.sy = o.sy or 1
  o.dy = o.dy or 0
  return o
end

function M.pose(name, t)
  if name == "sleep" then
    -- slow breaths, settling a little wider on each; a "z" every 2.4 s
    local b = (1 - math.cos(t / 4000 * TAU)) / 2
    return still({ mood = "sleepy", lookX = 0, lookY = 0.3, sx = 1 + 0.05 * b, sy = 1 - 0.04 * b, z = (t % 2400) / 2400, nextIn = 0 })
  elseif name == "drowsy" then
    local b = (1 - math.cos(t / 3000 * TAU)) / 2
    return still({ lid = 0.45, lookY = 0.2, sx = 1 + 0.02 * b, sy = 1 - 0.02 * b, nextIn = 0 })
  elseif name == "think" then
    -- eyes up, drifting from side to side
    return still({ lookX = 0.5 * math.sin(t / 2600 * TAU), lookY = -0.6, nextIn = 0 })
  elseif name == "work" then
    -- squinting down at the work, holding still
    return still({ lid = 0.7, lookY = 0.25, nextIn = math.huge })
  elseif name == "attention" then
    -- round eyes and a double hop every 1.6 s: it needs you
    local h, wait = hop(t, 1600, 520)
    local h2 = if h > 0 then math.abs(math.sin((t % 1600) / 520 * TAU)) else 0
    return still({ mood = "surprised", lookY = -0.2, dy = -0.16 * h2, sx = 1 - 0.04 * h2, sy = 1 + 0.06 * h2, nextIn = wait })
  elseif name == "unread" then
    -- happy eyes and a soft pulse: a reply is waiting
    local p = math.sin(t / 1200 * TAU / 2) ^ 2
    return still({ mood = "happy", sx = 1 + 0.05 * p, sy = 1 + 0.05 * p, nextIn = 0 })
  elseif name == "happy" then
    local h, wait = hop(t, 1500, 450)
    return still({ mood = "happy", dy = -0.14 * h, sx = 1 - 0.04 * h, sy = 1 + 0.05 * h, nextIn = wait })
  elseif name == "failed" then
    -- startled
    return still({ mood = "surprised", nextIn = math.huge })
  end
  -- awake: Life's blinks and glances, and a little hop every 3.5 s
  local h, wait = hop(t, 3500, 420)
  return still({ dy = -0.08 * h, sx = 1 - 0.03 * h, sy = 1 + 0.04 * h, nextIn = wait })
end

-- The face inputs once a pose is layered over Life. A mood Life was poked into (a hover,
-- a landing) shows over the pose's for its moment: a sleeping orb peeks when touched.
function M.apply(life, pose)
  return {
    lid = math.min(life.lid, pose.lid or 1),
    lookX = pose.lookX or life.lookX,
    lookY = pose.lookY or life.lookY,
    mood = if life.mood ~= "normal" then life.mood else (pose.mood or "normal"),
    breath = life.breath,
  }
end

return M
