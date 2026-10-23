--!nonstrict
-- Unit tests for lib/hermes/sse.luau. Run with tests/run.sh.

local sse = require("../lib/hermes/sse")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

local p = sse.new()
check("event line alone emits nothing", p:push("event: assistant.delta") == nil)
check("data line alone emits nothing", p:push('data: {"delta":"Hi: there"}') == nil)
local ev = p:push("")
check("blank line ends the event", ev ~= nil and ev.event == "assistant.delta" and ev.data == '{"delta":"Hi: there"}')
check("keepalive ignored", p:push(": keepalive") == nil and p:push("") == nil)
p:push("data: line one")
p:push("data: line two")
ev = p:push("")
check("multi-line data joins with newline", ev.data == "line one\nline two" and ev.event == "message")
p:push("data:x")
check("no space after colon keeps the value", p:push("").data == "x")
p:push("event: run.completed\r")
p:push('data: {"run_id":"r1"}')
local last = p:finish()
check("finish flushes a pending event", last ~= nil and last.event == "run.completed" and last.data == '{"run_id":"r1"}')
check("finish with nothing pending", p:finish() == nil)

if failures > 0 then
  error(`{failures} sse test(s) failed`)
end
