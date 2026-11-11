--!nonstrict
-- Shared view of the service's published state. Entries never share Lua
-- memory, so every UI entry reads the same plain table through here.
local M = {}

M.PANEL_ID = "shadow/duck:panel"

local function str(value)
  return type(value) == "string" and value or ""
end

local function num(value)
  return type(value) == "number" and value or 0
end

function M.view()
  local raw = noctalia.state.get("duck")
  if type(raw) ~= "table" then
    raw = {}
  end
  local messages = {}
  if type(raw.messages) == "table" then
    for _, item in ipairs(raw.messages) do
      if type(item) == "table" and str(item.uid) ~= "" then
        table.insert(messages, {
          uid = str(item.uid),
          alias = str(item.alias),
          sender = str(item.sender),
          subject = str(item.subject),
          preview = str(item.preview),
          otp = str(item.otp),
          at = num(item.at),
          unread = item.unread == true,
        })
      end
    end
  end
  local status = str(raw.status)
  if status == "" then
    status = "connecting"
  end
  return {
    status = status,
    detail = str(raw.detail),
    address = str(raw.address),
    generating = raw.generating == true,
    unread = num(raw.unread),
    messages = messages,
  }
end

function M.request(action, value)
  noctalia.state.set("request", {
    action = action,
    value = value or "",
    at = noctalia.nowMs(),
  })
end

function M.online(status)
  return status == "connected" or status == "idle"
end

function M.statusLabel(status)
  local keys = {
    connecting = "panel.connecting",
    connected = "panel.connected",
    idle = "panel.connected",
    reconnecting = "panel.reconnecting",
    error = "panel.error",
  }
  return noctalia.tr(keys[status] or "panel.connecting")
end

function M.shorten(text, max)
  if max <= 0 or #text <= max then
    return text
  end
  local localPart, domain = string.match(text, "^(.-)(@.+)$")
  if localPart == nil then
    return string.sub(text, 1, max - 1) .. "…"
  end
  local keep = max - #domain - 1
  if keep < 4 then
    return string.sub(text, 1, max - 1) .. "…"
  end
  return string.sub(localPart, 1, keep) .. "…" .. domain
end

function M.when(at, nowMs)
  if at <= 0 then
    return ""
  end
  local delta = math.floor(nowMs / 1000) - at
  if delta < 60 then
    return noctalia.tr("time.now")
  end
  if delta < 3600 then
    return string.format("%dm", math.floor(delta / 60))
  end
  if delta < 86400 then
    return noctalia.formatTime("{:%H:%M}", at)
  end
  return noctalia.formatTime("{:%b %d}", at)
end

function M.copy(text)
  if text == "" then
    return
  end
  -- wl-copy owns the live selection, so Ctrl+V pastes it immediately.
  -- The shell clipboard records the same text, but picking that history
  -- entry was the only way a paste would see it.
  noctalia.runAsync({ "wl-copy", text })
end

return M
