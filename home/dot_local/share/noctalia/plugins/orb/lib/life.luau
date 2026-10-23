--!nonstrict
-- Idle life for the orb's face: blinks, glances, a breath now and then, and
-- short moods. Pure and time-driven: call step(dtMs), then read lid, lookX,
-- lookY, breath and mood. Every entry that draws the face owns one.

local Life = {}
Life.__index = Life

local BLINK_MS = 150
local BREATH_MS = 1300

function Life.new(rng)
  local self = setmetatable({}, Life)
  self.rng = rng or math.random
  self.t = 0
  self.lid = 1 -- 1 open, 0 shut
  self.lookX, self.lookY = 0, 0 -- -1..1
  self.aimX, self.aimY = 0, 0
  self.aimUntil = 0
  self.breath = 0 -- 0..1, peaks mid-breath
  self.mood = "normal" -- normal | happy | surprised | sleepy
  self.moodUntil = 0
  self.blinkAt = nil
  self.breathAt = nil
  self.nextBlink = 1500 + self.rng() * 3000
  self.nextGlance = 1000 + self.rng() * 2500
  self.nextBreath = 8000 + self.rng() * 10000
  return self
end

function Life:poke(mood, ms)
  self.mood = mood
  self.moodUntil = self.t + ms
end

-- Point the gaze from outside (toward where the orb is flying); idle glances
-- wait until the aim goes stale.
function Life:aim(x, y, holdMs)
  self.aimX = math.clamp(x, -1, 1)
  self.aimY = math.clamp(y, -1, 1)
  self.aimUntil = self.t + (holdMs or 400)
end

function Life:step(dt)
  local t = self.t + dt
  self.t = t
  local rng = self.rng

  if self.blinkAt == nil and t >= self.nextBlink then
    self.blinkAt = t
  end
  if self.blinkAt ~= nil then
    local p = (t - self.blinkAt) / BLINK_MS
    if p >= 1 then
      self.blinkAt = nil
      self.lid = 1
      -- now and then a double blink
      self.nextBlink = t + (if rng() < 0.2 then 180 else 3200 + rng() * 3800)
    else
      self.lid = 1 - math.sin(p * math.pi)
    end
  end

  if t >= self.aimUntil and t >= self.nextGlance then
    if rng() < 0.4 then
      self.aimX, self.aimY = 0, 0
    else
      self.aimX = rng() * 2 - 1
      self.aimY = (rng() * 2 - 1) * 0.6
    end
    self.nextGlance = t + 1200 + rng() * 3800
  end
  local k = 1 - math.exp(-dt / 90)
  self.lookX += (self.aimX - self.lookX) * k
  self.lookY += (self.aimY - self.lookY) * k

  if self.breathAt == nil and t >= self.nextBreath then
    self.breathAt = t
  end
  if self.breathAt ~= nil then
    local p = (t - self.breathAt) / BREATH_MS
    if p >= 1 then
      self.breathAt = nil
      self.breath = 0
      self.nextBreath = t + 12000 + rng() * 12000
    else
      self.breath = math.sin(p * math.pi)
    end
  end

  if self.mood ~= "normal" and t >= self.moodUntil then
    self.mood = "normal"
  end
end

-- True while something on the face is moving, so callers tick fast.
function Life:animating()
  return self.blinkAt ~= nil
    or self.breathAt ~= nil
    or self.mood ~= "normal"
    or math.abs(self.aimX - self.lookX) > 0.02
    or math.abs(self.aimY - self.lookY) > 0.02
end

-- Milliseconds until the next scheduled change, so a slow ticker can wake in time.
function Life:nextEventIn()
  local nextAt = math.min(self.nextBlink, self.nextGlance, self.nextBreath)
  if self.mood ~= "normal" then
    nextAt = math.min(nextAt, self.moodUntil)
  end
  return math.max(0, nextAt - self.t)
end

return Life
