--!nonstrict
-- Hermes JSON -> what the card shows. Pure; every function tolerates missing fields.

local M = {}


-- "now", "5m", "3h", "2d" since a unix timestamp.
function M.ago(nowS, ts)
  ts = tonumber(ts)
  if ts == nil then
    return ""
  end
  local d = math.max(0, nowS - ts)
  if d < 60 then
    return "now"
  elseif d < 3600 then
    return `{math.floor(d / 60)}m`
  elseif d < 86400 then
    return `{math.floor(d / 3600)}h`
  end
  return `{math.floor(d / 86400)}d`
end

-- First n characters, cut on a character boundary.
local function cut(s, n)
  if utf8.len(s) == nil or utf8.len(s) <= n then
    return s
  end
  return string.sub(s, 1, utf8.offset(s, n + 1) - 1) .. "…"
end

local function nonEmpty(s)
  return type(s) == "string" and string.match(s, "%S") ~= nil
end

function M.status(json)
  json = json or {}
  return {
    link = if json.overall == "ok" then "online" else "degraded",
    agents = tonumber(json.active_agents) or 0,
    sessions = tonumber(json.active_sessions) or 0,
    busy = json.gateway_busy == true,
    profiles = json.profiles or {},
  }
end

function M.chatRows(json, nowS)
  local rows = {}
  for _, s in (json and json.data) or {} do
    local title = if nonEmpty(s.title) then s.title elseif nonEmpty(s.preview) then cut(s.preview, 60) else "Untitled chat"
    table.insert(rows, {
      id = s.id,
      title = title,
      source = s.source or "",
      ago = M.ago(nowS, s.last_active or s.started_at),
      mine = s.source == "api_server", -- what Hermes calls the API server's own sessions
    })
  end
  return rows
end

local function text(content)
  if type(content) == "string" then
    return content
  end
  if type(content) == "table" then
    local parts = {}
    for _, part in content do
      if type(part) == "table" and type(part.text) == "string" then
        table.insert(parts, part.text)
      end
    end
    return table.concat(parts, "\n")
  end
  return ""
end

-- The last part of a model id: "NVIDIA/nvidia/nemotron-3-super" -> "nemotron-3-super".
function M.shortModel(id)
  if type(id) ~= "string" then
    return ""
  end
  return string.match(id, "([^/]+)$") or id
end

-- Hermes' "[System: The active model for this chat has changed to X via provider Y. …]".
local function switchedTo(t)
  local model = string.match(t, "has changed to (.-) via provider ")
    or string.match(t, "has changed to (.-)%.?%]")
    or string.match(t, "has changed to (%S+)")
  return if model ~= nil then string.gsub(model, "%.$", "") else nil
end

-- Hermes marks rows that are not plain turns with display_kind: hidden scaffolding is
-- skipped, a model switch and a turn that failed become a small event line. A reply carries
-- the model's reasoning as `thinking`, gathered over the turn's calls (tool-call rows have
-- no text of their own).
function M.messageRows(json)
  local rows = {}
  local thinking = {}
  for _, m in (json and json.data) or {} do
    local t = text(m.content)
    local kind = m.display_kind
    if m.role == "user" and kind ~= "hidden" and kind ~= "model_switch" then
      thinking = {} -- a new turn
    elseif m.role == "assistant" and kind ~= "hidden" then
      local r = m.reasoning_content or m.reasoning
      if nonEmpty(r) then
        table.insert(thinking, (string.gsub(r, "^%s+", "")))
      end
    end
    if kind == "hidden" or m.role ~= "user" and m.role ~= "assistant" or not nonEmpty(t) then
      continue
    end
    if kind == "model_switch" then
      local model = switchedTo(t)
      if model ~= nil then
        table.insert(rows, { role = "event", kind = "model", text = M.shortModel(model) })
      end
    elseif kind == "failed_turn" then
      table.insert(rows, { role = "event", kind = "failed", text = t })
      thinking = {}
    elseif m.role == "user" and string.sub(t, 1, 8) == "[System:" then
      continue -- an untyped notice from before Hermes typed them
    elseif m.role == "assistant" then
      table.insert(rows, { role = "assistant", text = t, thinking = if #thinking > 0 then table.concat(thinking, "\n\n") else nil })
      thinking = {}
    else
      table.insert(rows, { role = m.role, text = t })
    end
  end
  return rows
end

-- /api/model/options -> the model picker: Hermes' default, then the providers you set up,
-- the default's provider first. "Set up" is a provider from your Hermes config, one you
-- signed in to through Hermes (source "hermes": Codex, Nous, …), or the one in use; the
-- rest (built-in catalogs Hermes lists because a key happens to be around, like Copilot
-- through a GitHub token) go in `more`. Providers without models are left out.
function M.modelSections(json)
  json = json or {}
  local default = if type(json.model) == "string" and json.model ~= ""
    then { provider = json.provider or "", model = json.model }
    else nil
  local sections, more = {}, {}
  for _, p in json.providers or {} do
    if p.authenticated and type(p.models) == "table" and #p.models > 0 then
      local section = { slug = p.slug, models = p.models }
      if p.is_current then
        table.insert(sections, 1, section)
      elseif p.is_user_defined or p.source == "user-config" or p.source == "hermes" then
        table.insert(sections, section)
      else
        table.insert(more, section)
      end
    end
  end
  return { default = default, sections = sections, more = more }
end

return M
