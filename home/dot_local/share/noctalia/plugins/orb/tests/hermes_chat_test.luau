--!nonstrict
-- Unit tests for lib/hermes/chat.luau. Run with tests/run.sh.

local chat = require("../lib/hermes/chat")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

local c = chat.new("s1")
chat.addUser(c, "list files")
check("sending after addUser", c.status == "sending" and #c.messages == 1)
chat.apply(c, "run.started", { run_id = "r1" }, 1)
check("thinking after run.started", c.status == "thinking" and c.runId == "r1")
chat.apply(c, "assistant.delta", { delta = "Here ", run_id = "r1" }, 2)
chat.apply(c, "tool.started", { tool = "terminal", preview = "ls", run_id = "r1" }, 3)
check("tool status while a tool runs", c.status == "tool" and #c.tools == 1)
chat.apply(c, "tool.completed", { tool = "terminal", run_id = "r1" }, 4)
check("back to thinking after the tool", c.status == "thinking" and c.tools[1].state == "done")
chat.apply(c, "assistant.delta", { delta = "you go", run_id = "r1" }, 5)
chat.apply(c, "run.completed", { run_id = "r1" }, 6)
local reply = c.messages[2]
check("reply assembled from deltas", reply.role == "assistant" and reply.text == "Here you go" and reply.state == "done", reply.text)
check("reply keeps its tools", #reply.tools == 1 and reply.tools[1].name == "terminal")
check("done clears the run", c.status == "done" and c.runId == nil and c.streaming == nil)

local a = chat.addUser(chat.new("s2"), "delete tmp")
chat.apply(a, "approval.request", { run_id = "r2", request_id = "q7", command = "rm -rf /tmp/x", choices = { "once", "deny" } }, 1)
check("approval waits", a.status == "waiting" and a.approval.requestId == "q7" and a.runId == "r2")
chat.apply(a, "tool.failed", { tool = "terminal", run_id = "r2" }, 2)
check("approval cleared once the run moves on", a.approval == nil)

local d = chat.addUser(chat.new("s3"), "long task")
chat.apply(d, "assistant.delta", { delta = "partial text" }, 1)
chat.close(d, false)
check("dropped stream is interrupted", d.status == "interrupted" and d.messages[2].state == "interrupted" and d.messages[2].text == "partial text")

local f = chat.addUser(chat.new("s4"), "x")
chat.apply(f, "run.failed", { error = "provider down" }, 1)
check("failure without deltas uses the error", f.messages[2].text == "provider down" and f.status == "failed")
local g = chat.addUser(chat.new("s5"), "x")
chat.apply(g, "assistant.delta", { delta = "half" }, 1)
chat.apply(g, "run.failed", { partial = true }, 2)
check("partial failure keeps the text", g.messages[2].state == "partial" and g.messages[2].text == "half")
local k = chat.addUser(chat.new("s6"), "x")
chat.apply(k, "run.cancelled", {}, 1)
check("cancelled", k.status == "cancelled" and k.messages[2].state == "cancelled")
check("close after done changes nothing", #chat.close(c, true).messages == 2 and c.status == "done")

local t = chat.new("s7")
for i = 1, 60 do
  table.insert(t.messages, { role = "user", text = tostring(i), tools = {}, state = "done" })
end
chat.trim(t, 50)
check("trim keeps the newest 50", #t.messages == 50 and t.messages[1].text == "11" and t.messages[50].text == "60")
check("busy while thinking", chat.busy({ status = "thinking" }) and not chat.busy({ status = "done" }))

local fc = chat.new("s7")
chat.addUser(fc, "draw it", { "sketch.png" })
check("user files kept", fc.messages[1].files[1] == "sketch.png")
chat.apply(fc, "assistant.delta", { delta = "Here MEDIA:/tmp/a.png" }, 1)
chat.apply(fc, "assistant.completed", { content = "Here ![image](data:image/png;base64,QQ==)" }, 2)
chat.apply(fc, "run.completed", {}, 3)
check("completed content beats deltas", fc.messages[2].text == "Here ![image](data:image/png;base64,QQ==)", fc.messages[2].text)
chat.note(fc, "renamed")
check("note", fc.messages[3].role == "note" and fc.messages[3].text == "renamed")

local tc = chat.new("s")
chat.apply(tc, "run.started", {}, 1)
chat.apply(tc, "tool.progress", { tool_name = "_thinking", delta = "looking at files" }, 2)
check("live thinking preview", tc.preview == "looking at files")
chat.apply(tc, "assistant.delta", { delta = "hi" }, 3)
chat.apply(tc, "run.completed", { messages = {
  { role = "user", content = "q" },
  { role = "assistant", content = "", reasoning = "step one" },
  { role = "assistant", content = "hi", reasoning_content = "step two" },
} }, 4)
check("finished reply keeps the turn's thinking", tc.messages[#tc.messages].thinking == "step one\n\nstep two", tc.messages[#tc.messages].thinking)
check("preview cleared after the run", tc.preview == nil)

if failures > 0 then
  error(`{failures} chat test(s) failed`)
end
