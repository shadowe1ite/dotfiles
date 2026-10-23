--!nonstrict
-- Unit tests for lib/expression.luau. Run with tests/run.sh.

local E = require("../lib/expression")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

check("no key sleeps", E.pick({ link = "auth" }) == "sleep")
check("offline sleeps", E.pick({ link = "offline", pet = "idle" }) == "sleep")
check("sleep beats activity", E.pick({ link = "offline", pet = "run" }) == "sleep")
check("connected is awake", E.pick({ link = "online", pet = "idle" }) == "awake")
check("still checking is awake", E.pick({ link = "unknown" }) == "awake")
check("shaky link is drowsy", E.pick({ link = "degraded", pet = "idle" }) == "drowsy")
check("activity beats a shaky link", E.pick({ link = "degraded", pet = "review" }) == "think")
check("thinking", E.pick({ link = "online", pet = "review" }) == "think")
check("working", E.pick({ link = "online", pet = "run" }) == "work")
check("approval needs attention", E.pick({ link = "online", pet = "idle", nudge = "approval" }) == "attention")
check("waiting needs attention", E.pick({ link = "online", pet = "waiting" }) == "attention")
check("attention beats work", E.pick({ link = "online", pet = "run", nudge = "approval" }) == "attention")
check("failed", E.pick({ link = "online", pet = "failed" }) == "failed")
check("finished is happy", E.pick({ link = "online", pet = "wave" }) == "happy")
check("a waiting reply", E.pick({ link = "online", pet = "idle", nudge = "unread" }) == "unread")
check("work beats a waiting reply", E.pick({ link = "online", pet = "run", nudge = "unread" }) == "work")

local names = { "sleep", "drowsy", "awake", "think", "work", "attention", "unread", "happy", "failed" }
local sane = true
for _, n in names do
  for t = 0, 8000, 37 do
    local p = E.pose(n, t)
    if p.sx < 0.85 or p.sx > 1.15 or p.sy < 0.85 or p.sy > 1.15 or p.dy > 0 or p.dy < -0.25 or p.nextIn < 0 then
      sane = false
      print(n, t, p.sx, p.sy, p.dy, p.nextIn)
    end
  end
end
check("every pose stays in bounds", sane)

local sleep = E.pose("sleep", 1200)
check("sleep: eyes shut, a z drifting", sleep.mood == "sleepy" and sleep.z ~= nil and sleep.z > 0 and sleep.z < 1)
check("awake has no z", E.pose("awake", 1200).z == nil)
check("awake rests between hops", E.pose("awake", 1000).dy == 0 and E.pose("awake", 1000).nextIn == 2500)
check("awake hops", E.pose("awake", 210).dy < -0.07)
check("attention hops", E.pose("attention", 130).dy < -0.1)
check("work squints", E.pose("work", 0).lid == 0.7)
check("work holds still (no shivering)", E.pose("work", 0).sx == 1 and E.pose("work", 333).sy == 1)
check("failed holds still", E.pose("failed", 120).sx == 1 and E.pose("failed", 120).lookX == nil)

local life = { lid = 1, lookX = 0.2, lookY = 0, mood = "normal", breath = 0 }
local f = E.apply(life, E.pose("think", 650))
check("pose gaze wins over glances", f.lookY == -0.6 and math.abs(f.lookX - 0.5) < 0.01, f.lookX)
check("pose mood shows", E.apply(life, sleep).mood == "sleepy")
life.mood = "surprised"
check("a poke peeks through", E.apply(life, sleep).mood == "surprised")
life.lid = 0.3
check("a blink still closes squinting eyes", E.apply(life, E.pose("work", 0)).lid == 0.3)

if failures > 0 then
  error(`{failures} expression test(s) failed`)
end
