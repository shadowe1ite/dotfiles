--!nonstrict
-- The orb's conversation with Hermes as a plain table, advanced by the session stream's
-- events (POST /api/sessions/{id}/chat/stream). Pure.
--
--   chat = {
--     sessionId, messages = { { role, text, tools, state } }, streaming, tools,
--     runId, status, approval = { requestId, command, description, choices }, notice,
--   }
--   status: idle | sending | thinking | tool | waiting | done | failed | cancelled | interrupted

local M = {}

local TERMINAL = { done = true, failed = true, cancelled = true, interrupted = true, idle = true }

function M.new(sessionId)
  return {
    sessionId = sessionId,
    messages = {},
    streaming = nil,
    tools = {},
    runId = nil,
    status = "idle",
    approval = nil,
    notice = nil,
    lastEventAt = nil,
    pending = {}, -- attachments waiting for the next message: { path, name, size, kind }
    model = nil, -- { provider, model, default? }: the orb's pick, locked into the chats it sends to
    preview = nil, -- the latest text Hermes relayed while it works (tool.progress "_thinking")
  }
end

-- files: names of what was attached, shown under the bubble
function M.addUser(c, text, files)
  table.insert(c.messages, { role = "user", text = text, files = files or {}, tools = {}, state = "done" })
  c.status = "sending"
  c.streaming, c.approval, c.notice = nil, nil, nil
  c.tools = {}
  return c
end

local function anyRunning(c)
  for _, t in c.tools do
    if t.state == "running" then
      return true
    end
  end
  return false
end

-- The model's reasoning in a turn's transcript rows (run.completed's `messages`): every
-- assistant row's, in order, since a turn with tools makes several calls. nil without any.
function M.turnThinking(rows)
  local parts = {}
  for _, row in rows or {} do
    if type(row) == "table" and row.role == "assistant" then
      local r = row.reasoning_content or row.reasoning
      if type(r) == "string" and string.match(r, "%S") then
        table.insert(parts, (string.gsub(r, "^%s+", "")))
      end
    end
  end
  return if #parts > 0 then table.concat(parts, "\n\n") else nil
end

local function finish(c, state, text, status, thinking)
  -- assistant.completed's content wins over the streamed deltas: Hermes resolves images into
  -- it (MEDIA: tags become data URLs) only there
  table.insert(c.messages, { role = "assistant", text = c.final or text or "", tools = c.tools, state = state, thinking = thinking })
  c.streaming, c.approval, c.runId, c.final, c.preview = nil, nil, nil, nil, nil
  c.tools = {}
  c.status = status
end

function M.apply(c, event, p, nowMs)
  p = p or {}
  if p.run_id ~= nil then
    c.runId = p.run_id
  end
  c.lastEventAt = nowMs
  if event ~= "approval.request" and c.approval ~= nil and event ~= "message.started" then
    c.approval = nil -- answered: the run moved on
  end

  if event == "run.started" then
    c.status = "thinking"
  elseif event == "assistant.delta" then
    c.streaming = (c.streaming or "") .. (p.delta or "")
    if not anyRunning(c) then
      c.status = "thinking"
    end
  elseif event == "tool.progress" then
    if p.tool_name == "_thinking" then
      if type(p.delta) == "string" and string.match(p.delta, "%S") then
        c.preview = p.delta
      end
      if not anyRunning(c) then
        c.status = "thinking"
      end
    end
  elseif event == "tool.started" then
    table.insert(c.tools, { name = p.tool or p.tool_name or "tool", preview = p.preview or "", state = "running" })
    c.status = "tool"
  elseif event == "tool.completed" or event == "tool.failed" then
    local name = p.tool or p.tool_name
    for i = #c.tools, 1, -1 do
      local t = c.tools[i]
      if t.state == "running" and (name == nil or t.name == name) then
        t.state = if event == "tool.failed" or p.error == true then "error" else "done"
        break
      end
    end
    c.status = if anyRunning(c) then "tool" else "thinking"
  elseif event == "assistant.completed" then
    if type(p.content) == "string" and p.content ~= "" then
      c.final = p.content
    end
  elseif event == "approval.request" then
    c.approval = {
      requestId = p.request_id or p.prompt_id or p.id,
      command = p.command or "",
      description = p.description or "",
      choices = p.choices or { "once", "deny" },
      generation = p.execution_generation,
    }
    c.status = "waiting"
  elseif event == "run.completed" then
    finish(c, if p.partial then "partial" else "done", c.streaming or p.output, "done", M.turnThinking(p.messages))
  elseif event == "run.failed" then
    finish(c, if p.partial then "partial" else "failed", c.streaming or p.output or p.error, "failed", M.turnThinking(p.messages))
  elseif event == "run.cancelled" then
    finish(c, "cancelled", c.streaming, "cancelled")
  end
  return c
end

-- A line from the orb itself (command output, help), not part of the Hermes transcript.
function M.note(c, text)
  table.insert(c.messages, { role = "note", text = text, tools = {}, state = "done" })
end

-- The stream closed. A turn without a terminal event is kept as interrupted.
function M.close(c, _ok)
  if not TERMINAL[c.status] then
    finish(c, "interrupted", c.streaming, "interrupted")
  end
  return c
end

function M.trim(c, max)
  local extra = #c.messages - max
  if extra > 0 then
    local kept = {}
    for i = extra + 1, #c.messages do
      table.insert(kept, c.messages[i])
    end
    c.messages = kept
  end
  return c
end

function M.busy(c)
  return not TERMINAL[c.status]
end

return M
