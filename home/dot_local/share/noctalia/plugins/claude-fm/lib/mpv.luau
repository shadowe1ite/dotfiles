--!nonstrict
-- Reading mpv's real state over its IPC socket and turning it into the radio's
-- status (stopped | loading | playing | paused). Asking mpv, instead of timing
-- it, is what notices a pause or resume that comes from outside (media keys,
-- playerctl) and a stream that is still buffering. Pure module: the host passes
-- in the JSON decoder and the clock.
local mpv = {}

local GRACE_MS = 8000 -- mpv may take this long to create its socket and start

-- Property -> request id; replies are matched by request_id.
local PROPS = {
  { "idle-active", "idleActive" },
  { "core-idle", "coreIdle" },
  { "pause", "paused" },
  { "paused-for-cache", "cache" },
  { "volume", "volume" },
}

-- One shell invocation, one socket connection, five replies. Prints NOSOCK when
-- mpv's socket does not exist (not started yet, or gone).
function mpv.pollScript(sock)
  local cmds = {}
  for id, p in ipairs(PROPS) do
    cmds[#cmds + 1] = string.format("'{\"command\":[\"get_property\",\"%s\"],\"request_id\":%d}'", p[1], id)
  end
  return "S='" .. sock .. "'; if [ -S \"$S\" ]; then printf '%s\\n' " .. table.concat(cmds, " ")
    .. " | timeout 2 socat -t 0.3 - \"UNIX-CONNECT:$S\"; else echo NOSOCK; fi"
end

-- Poll output -> { idleActive, coreIdle, paused, cache, volume } (fields
-- are nil when mpv says the property is unavailable), or nil when mpv did not
-- answer at all.
function mpv.parse(stdout, decode)
  if type(stdout) ~= "string" then
    return nil
  end
  local r, answered = {}, false
  for line in stdout:gmatch("[^\r\n]+") do
    if line:sub(1, 1) == "{" then
      local ok, obj = pcall(decode, line)
      local prop = ok and type(obj) == "table" and PROPS[obj.request_id]
      if prop then
        answered = true
        if obj.error == "success" and obj.data ~= nil then
          r[prop[2]] = obj.data
        end
      end
    end
  end
  return answered and r or nil
end

-- ctx = { status = current status, launchedAt = ms, now = ms }
function mpv.derive(r, ctx)
  local starting = ctx.status == "loading" and ctx.now - ctx.launchedAt < GRACE_MS
  if r == nil then
    return starting and "loading" or "stopped"
  end
  if r.idleActive == true then
    return starting and "loading" or "stopped"
  end
  if r.paused == true then
    return "paused"
  end
  if r.coreIdle == true or r.cache == true then
    return "loading"
  end
  return "playing"
end

return mpv
