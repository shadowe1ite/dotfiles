--!nonstrict
-- Unit tests for lib/motion.luau. Run with tests/run.sh (needs the `luau` CLI).

local motion = require("../lib/motion")

local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

-- Park-Miller: deterministic and exact in doubles.
local function rng(seed)
  local s = seed
  return function()
    s = (s * 16807) % 2147483647
    return s / 2147483647
  end
end

-- nearestAnchor: screen thirds map to the nine panel positions
check("anchor top_left", motion.nearestAnchor(10, 10, 1920, 1080) == "top_left")
check("anchor center", motion.nearestAnchor(960, 540, 1920, 1080) == "center")
check("anchor bottom_right", motion.nearestAnchor(1900, 1070, 1920, 1080) == "bottom_right")
check("anchor bottom_center", motion.nearestAnchor(960, 1000, 1920, 1080) == "bottom_center")
check("anchor center_left", motion.nearestAnchor(100, 540, 1920, 1080) == "center_left")
check("anchor top_right", motion.nearestAnchor(1800, 60, 1920, 1080) == "top_right")

-- steer: arrives, and never runs faster than its max speed
do
  local x, y, vx, vy = 100, 100, 0, 0
  local maxSeen = 0
  local arrived = false
  for _ = 1, 60 * 30 do
    x, y, vx, vy = motion.steer(x, y, vx, vy, 1500, 800, 1 / 60, 230, 4)
    maxSeen = math.max(maxSeen, math.sqrt(vx * vx + vy * vy))
    if motion.arrived(x, y, vx, vy, 1500, 800) then
      arrived = true
      break
    end
  end
  check("steer arrives", arrived, `ended at {x},{y}`)
  check("steer speed capped", maxSeen <= 230 * 1.05, `max {maxSeen}`)
end

do
  local x, y, vx, vy = 500, 500, 0, 0
  x, y, vx, vy = motion.steer(x, y, vx, vy, 500, 500, 1 / 60, 230, 4)
  check("steer at target stays put", x == 500 and y == 500 and vx == 0 and vy == 0)
end

-- pickTarget: inside bounds, and far enough from the current point
do
  local bounds = { left = 48, top = 88, right = 1872, bottom = 1032 }
  local r = rng(42)
  local inside, farEnough = true, true
  for _ = 1, 200 do
    local tx, ty = motion.pickTarget(r, bounds, 960, 540, 220)
    if tx < bounds.left or tx > bounds.right or ty < bounds.top or ty > bounds.bottom then
      inside = false
    end
    local d = math.sqrt((tx - 960) ^ 2 + (ty - 540) ^ 2)
    if d < 220 then
      farEnough = false
    end
  end
  check("pickTarget inside bounds", inside)
  check("pickTarget keeps min distance", farEnough)
end

-- homeAlong: rough spot of the widget along the bar
check("homeAlong center middle", motion.homeAlong("center", 3, 5, 1920) == 960)
check("homeAlong start first", motion.homeAlong("start", 1, 3, 1920) < 1920 * 0.1)
check("homeAlong end last", motion.homeAlong("end", 3, 3, 1920) > 1920 * 0.9)
check("homeAlong unknown section", motion.homeAlong(nil, 1, 1, 1920) == 960)

-- homePoint / outward / roamBounds per bar edge
do
  local x, y = motion.homePoint("top", 40, 700, 1920, 1080)
  check("homePoint top", x == 700 and y == 40, `{x},{y}`)
  x, y = motion.homePoint("bottom", 40, 700, 1920, 1080)
  check("homePoint bottom", x == 700 and y == 1040, `{x},{y}`)
  x, y = motion.homePoint("left", 40, 300, 1920, 1080)
  check("homePoint left", x == 40 and y == 300, `{x},{y}`)

  local ox, oy = motion.outward("top")
  check("outward top points down", ox == 0 and oy == 1)
  ox, oy = motion.outward("right")
  check("outward right points left", ox == -1 and oy == 0)

  local b = motion.roamBounds("top", 40, 1920, 1080, 48)
  check("roamBounds top clears the bar", b.top == 88 and b.bottom == 1032 and b.left == 48 and b.right == 1872)
  b = motion.roamBounds("bottom", 40, 1920, 1080, 48)
  check("roamBounds bottom clears the bar", b.top == 48 and b.bottom == 992)
end

-- cardLayout: the card grows right/down from the ball, flipping near screen edges
do
  local lay = motion.cardLayout(200, 100, 360, 270, 24, 14, 1920, 1080)
  check("card grows right/down", not lay.flipX and not lay.flipY)
  check("card surface size", lay.sw == 408 and lay.sh == 318)
  check("card surface placed around the ball", lay.left == 162 and lay.top == 62, `{lay.left},{lay.top}`)
  check("ball stays put when the card fits", lay.ballX == 200 and lay.ballY == 100)
  check("ball sits at the card corner", lay.bx == 38 and lay.by == 38)

  lay = motion.cardLayout(1850, 100, 360, 270, 24, 14, 1920, 1080)
  check("card flips left near the right edge", lay.flipX and not lay.flipY)
  check("flipped card keeps the ball in place", lay.ballX == 1850 and lay.left + lay.sw <= 1920)

  lay = motion.cardLayout(200, 1000, 360, 270, 24, 14, 1920, 1080)
  check("card flips up near the bottom", lay.flipY and not lay.flipX)
  check("flipped-up card fits", lay.top >= 0 and lay.top + lay.sh <= 1080)

  lay = motion.cardLayout(10, 10, 360, 270, 24, 14, 1920, 1080)
  check("ball makes room when the card cannot fit", lay.left == 0 and lay.top == 0 and lay.ballX == 38 and lay.ballY == 38)
end

-- cardLayout preferences: a chosen side wins even where auto would flip
do
  local lay = motion.cardLayout(800, 300, 360, 270, 24, 14, 1920, 1080, "left", "up")
  check("card opens left and up when asked", lay.flipX and lay.flipY)
  lay = motion.cardLayout(1850, 1000, 360, 270, 24, 14, 1920, 1080, "auto", "auto")
  check("auto still flips near the edges", lay.flipX and lay.flipY)
  lay = motion.cardLayout(30, 300, 360, 270, 24, 14, 1920, 1080, "left", nil)
  check("a side with no room makes the ball move over", lay.flipX and lay.left == 0 and lay.ballX > 30)
end

-- cardRect: hidden under the ball at 0, full size at 1
do
  local lay = motion.cardLayout(200, 100, 360, 270, 24, 14, 1920, 1080)
  local x, y, w, h = motion.cardRect(lay, 360, 270, 24, 14, 0)
  check("card starts as a dot under the ball", x == 24 and y == 24 and w == 28 and h == 28)
  x, y, w, h = motion.cardRect(lay, 360, 270, 24, 14, 1)
  check("card ends full size", x == 24 and y == 24 and w == 360 and h == 270)
  lay = motion.cardLayout(1850, 1000, 360, 270, 24, 14, 1920, 1080)
  x, y, w, h = motion.cardRect(lay, 360, 270, 24, 14, 0.5)
  check("flipped card grows from the ball's corner", x + w == lay.sw - 24 and y + h == lay.sh - 24)
end

-- jiggle: a few damped bounces that settle to nothing
check("jiggle starts squashed", motion.jiggle(0) < -0.07)
check("jiggle settles", math.abs(motion.jiggle(500)) < 0.005)

-- clampPoint keeps the carried orb inside bounds
do
  local b = { left = 30, top = 70, right = 1890, bottom = 1050 }
  local x, y = motion.clampPoint(-50, 20, b)
  check("clampPoint pulls it back on screen", x == 30 and y == 70)
  x, y = motion.clampPoint(500, 600, b)
  check("clampPoint leaves inside points alone", x == 500 and y == 600)
end

-- restorePoint: a saved spot comes back only on the same screen size
do
  local b = { left = 34, top = 74, right = 1886, bottom = 1046 }
  local x, y = motion.restorePoint({ x = 500, y = 600, w = 1920, h = 1080 }, 1920, 1080, b)
  check("saved spot comes back", x == 500 and y == 600)
  x, y = motion.restorePoint({ x = 5, y = 2000, w = 1920, h = 1080 }, 1920, 1080, b)
  check("saved spot is kept on screen", x == 34 and y == 1046)
  x = motion.restorePoint({ x = 500, y = 600, w = 2560, h = 1440 }, 1920, 1080, b)
  check("another screen size forgets the spot", x == nil)
  x = motion.restorePoint(nil, 1920, 1080, b)
  check("nothing saved, nothing restored", x == nil)
end

-- easing endpoints
check("easeOutBack ends", math.abs(motion.easeOutBack(0)) < 1e-9 and math.abs(motion.easeOutBack(1) - 1) < 1e-9)
check("easeOutBack overshoots", motion.easeOutBack(0.7) > 1)
check("easeInCubic ends", motion.easeInCubic(0) == 0 and motion.easeInCubic(1) == 1)

if failures > 0 then
  error(`{failures} motion test(s) failed`)
end
