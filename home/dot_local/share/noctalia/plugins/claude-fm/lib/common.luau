-- Shared constants and helpers for the Claude FM entries.
local M = {}

M.ID = "shadowe1ite/claude-fm"
M.PANEL_ID = "shadowe1ite/claude-fm:panel"

-- clau.de/radio 302-redirects here; the direct id keeps us off the redirect.
M.STREAM_ID = "tRsQsTMvPNg"
M.STREAM_URL = "https://www.youtube.com/watch?v=" .. M.STREAM_ID
M.SITE_URL = "https://clau.de/radio"

-- Claude's orange accent.
M.CLAUDE = "#D97757"
M.CLAUDE_SOFT = "#D9775740"

function M.socketPath()
  return noctalia.pluginDataDir() .. "/mpv.sock"
end

-- Playback state published by the service, with safe defaults. Every field is
-- type-checked, so a malformed state value cannot break the UI.
function M.playback()
  local p = noctalia.state.get("playback")
  if type(p) ~= "table" then
    p = {}
  end
  return {
    status = type(p.status) == "string" and p.status or "stopped", -- stopped | loading | playing | paused
    title = type(p.title) == "string" and p.title or "",
    volume = type(p.volume) == "number" and p.volume or 70,
  }
end

function M.isActive(status)
  return status == "playing" or status == "paused" or status == "loading"
end

-- UI entries ask the service to do something by publishing a request.
function M.request(action, value)
  noctalia.state.set("request", { action = action, value = value, at = noctalia.nowMs() })
end

-- Equalizer bar heights, derived from the clock so every entry animates in
-- sync. Flat at minH when not playing. No randomness -> fully deterministic.
function M.bars(n, t, playing, minH, maxH)
  local out = {}
  for i = 1, n do
    if not playing then
      out[i] = minH
    else
      local speed = 420 + i * 55
      local phase = i * 1.7
      local s = 0.5 + 0.5 * math.sin(t / speed + phase)
      s = s * 0.75 + (0.5 + 0.5 * math.sin(t / (speed * 0.5) + phase * 2)) * 0.25
      out[i] = minH + (maxH - minH) * s
    end
  end
  return out
end

-- Frame interval in ms for the "fps" setting (0 = no animation). The default is
-- "calm": each frame costs the shell about 0.3 points of one core per frame per
-- second, and the bar equalizer is the only thing that animates.
function M.frameMs(fps)
  if fps == "smooth" then
    return 50
  elseif fps == "off" then
    return 0
  end
  return 100
end

return M
