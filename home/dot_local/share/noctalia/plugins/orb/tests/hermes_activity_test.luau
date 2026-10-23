--!nonstrict
-- Unit tests for lib/hermes/activity.luau. Run with tests/run.sh.

local A = require("../lib/hermes/activity")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

check("waiting wins", A.pet({ chatStatus = "waiting", failedAt = 100, nowMs = 100 }) == "waiting")
check("failed for 2 s", A.pet({ chatStatus = "failed", failedAt = 0, nowMs = 1999 }) == "failed")
check("failed fades", A.pet({ chatStatus = "failed", failedAt = 0, nowMs = 2001 }) == "idle")
check("wave for 1.5 s", A.pet({ chatStatus = "done", finishedAt = 0, nowMs = 1000 }) == "wave")
check("wave fades", A.pet({ chatStatus = "done", finishedAt = 0, nowMs = 1600 }) == "idle")
check("tool is run", A.pet({ chatStatus = "tool", nowMs = 0 }) == "run")
check("thinking is review", A.pet({ chatStatus = "thinking", nowMs = 0 }) == "review")
check("busy elsewhere is run", A.pet({ chatStatus = "idle", busyElsewhere = true, nowMs = 0 }) == "run")
check("idle", A.pet({ chatStatus = "idle", nowMs = 0 }) == "idle")
check("offline polls slowly", A.pollDelay("offline", true) == 60000)
check("auth problems poll slowly", A.pollDelay("auth", false) == 60000)
check("open card polls fast", A.pollDelay("online", true) == 5000)
check("closed card polls gently", A.pollDelay("online", false) == 20000)

if failures > 0 then
  error(`{failures} activity test(s) failed`)
end
