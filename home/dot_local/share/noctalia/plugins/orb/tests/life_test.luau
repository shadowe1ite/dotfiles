--!nonstrict
-- Unit tests for lib/life.luau. Run with tests/run.sh (needs the `luau` CLI).

local Life = require("../lib/life")

local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

local function rng(seed)
  local s = seed
  return function()
    s = (s * 16807) % 2147483647
    return s / 2147483647
  end
end

-- blinks within a few seconds, and opens its eyes again afterwards
do
  local life = Life.new(rng(7))
  local minLid = 1
  for _ = 1, 8000 // 16 do
    life:step(16)
    minLid = math.min(minLid, life.lid)
  end
  check("blinks within 8 s", minLid < 0.2, `min lid {minLid}`)
  while life.blinkAt ~= nil do
    life:step(16)
  end
  check("eyes reopen after a blink", life.lid == 1)
end

-- a poked mood lasts its time, then fades back to normal
do
  local life = Life.new(rng(3))
  life:poke("happy", 500)
  life:step(200)
  check("mood holds", life.mood == "happy")
  life:step(400)
  check("mood expires", life.mood == "normal")
end

-- gaze stays in range over a long idle stretch
do
  local life = Life.new(rng(11))
  local inRange = true
  for _ = 1, 60000 // 16 do
    life:step(16)
    if math.abs(life.lookX) > 1 or math.abs(life.lookY) > 1 then
      inRange = false
    end
  end
  check("gaze stays within -1..1", inRange)
end

-- aim steers the gaze and holds it
do
  local life = Life.new(rng(5))
  life:aim(1, 0, 1000)
  for _ = 1, 500 // 16 do
    life:step(16)
  end
  check("aim moves the gaze", life.lookX > 0.9, `lookX {life.lookX}`)
end

-- the next scheduled event is never in the past
do
  local life = Life.new(rng(9))
  local ok = true
  for _ = 1, 20000 // 16 do
    life:step(16)
    if life:nextEventIn() < 0 then
      ok = false
    end
  end
  check("nextEventIn is never negative", ok)
end

if failures > 0 then
  error(`{failures} life test(s) failed`)
end
