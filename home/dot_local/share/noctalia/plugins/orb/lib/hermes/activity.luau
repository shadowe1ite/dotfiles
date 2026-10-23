--!nonstrict
-- What Hermes is doing -> the pet state Hermes itself uses (pets.md: idle, review, run, wave,
-- failed, waiting); lib/expression turns it into the orb's look. Plus how often to poll. Pure.

local M = {}

local WAVE_MS, FAILED_MS = 1500, 2000

-- input = { chatStatus, busyElsewhere, finishedAt, failedAt, nowMs }
function M.pet(input)
  local s, now = input.chatStatus, input.nowMs or 0
  if s == "waiting" then
    return "waiting"
  elseif input.failedAt ~= nil and now - input.failedAt < FAILED_MS then
    return "failed"
  elseif input.finishedAt ~= nil and now - input.finishedAt < WAVE_MS then
    return "wave"
  elseif s == "tool" then
    return "run"
  elseif s == "thinking" or s == "sending" then
    return "review"
  elseif input.busyElsewhere then
    return "run"
  end
  return "idle"
end

function M.pollDelay(link, cardOpen)
  if link == "offline" or link == "auth" or link == "error" then
    return 60000
  end
  return if cardOpen then 5000 else 20000
end

return M
