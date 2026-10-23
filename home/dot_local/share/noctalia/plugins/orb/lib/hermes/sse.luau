--!nonstrict
-- Server-sent events, one line at a time (Noctalia's httpStream hands us lines). Pure.
--
--   local p = sse.new()
--   local ev = p:push(line)   -- { event, data } when a blank line ends an event, else nil
--   local last = p:finish()   -- whatever was pending when the stream closed

local M = {}

local Parser = {}
Parser.__index = Parser

function M.new()
  return setmetatable({ event = nil, data = nil }, Parser)
end

function Parser:push(line)
  line = string.gsub(line or "", "\r$", "")
  if line == "" then
    if self.event == nil and self.data == nil then
      return nil
    end
    local ev = { event = self.event or "message", data = self.data or "" }
    self.event, self.data = nil, nil
    return ev
  end
  if string.sub(line, 1, 1) == ":" then
    return nil -- comment / keepalive
  end
  local field, value = string.match(line, "^([^:]*):?(.*)$")
  if string.sub(value, 1, 1) == " " then
    value = string.sub(value, 2)
  end
  if field == "event" then
    self.event = value
  elseif field == "data" then
    self.data = if self.data ~= nil then self.data .. "\n" .. value else value
  end
  return nil
end

function Parser:finish()
  if self.event == nil and self.data == nil then
    return nil
  end
  return self:push("")
end

return M
