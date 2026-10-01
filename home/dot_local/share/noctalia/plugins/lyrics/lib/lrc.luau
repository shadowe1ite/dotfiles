-- LRC parsing. Handles lines with several timestamps ("[00:12.00][01:40.00]la la"),
-- the [offset:] tag, and drops enhanced-LRC word timings ("<00:12.34>").
local M = {}

local function trim(s)
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function seconds(min, sec, frac)
  local t = tonumber(min) * 60 + tonumber(sec)
  if frac ~= "" then
    t += tonumber(frac) / 10 ^ #frac
  end
  return t
end

-- Returns a list of { time = seconds, text = string } sorted by time.
-- Empty text is kept on purpose: it marks a break between lines.
function M.parse(text)
  local lines = {}
  local offset = 0

  text = string.gsub(text, "^\239\187\191", "")
  for raw in string.gmatch(text .. "\n", "(.-)\r?\n") do
    local rest = raw
    local times = {}
    while true do
      local min, sec, frac, after = string.match(rest, "^%s*%[(%d+):(%d%d?)[%.:]?(%d*)%](.*)$")
      if min == nil then
        break
      end
      table.insert(times, seconds(min, sec, frac))
      rest = after
    end

    if #times > 0 then
      rest = trim(string.gsub(rest, "<%d+:%d+[%.:]?%d*>", ""))
      for _, t in ipairs(times) do
        table.insert(lines, { time = t, text = rest, order = #lines })
      end
    else
      local ms = string.match(raw, "^%s*%[offset:%s*([+-]?%d+)%s*%]")
      if ms ~= nil then
        offset = tonumber(ms) / 1000
      end
    end
  end

  -- a positive offset means the lyrics should show up earlier
  table.sort(lines, function(a, b)
    if a.time == b.time then
      return a.order < b.order
    end
    return a.time < b.time
  end)
  for _, line in ipairs(lines) do
    line.time = math.max(line.time - offset, 0)
    line.order = nil
  end
  return lines
end

-- Index of the line that is active at `pos` seconds, 0 before the first one.
function M.find(lines, pos)
  local lo, hi = 1, #lines
  local found = 0
  while lo <= hi do
    local mid = (lo + hi) // 2
    if lines[mid].time <= pos then
      found = mid
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return found
end

return M
