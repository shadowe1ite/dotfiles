-- Shared helpers for the tracker service and the UI entries.
local M = {}

M.PANEL_ID = "shadow/habits:panel"
M.RETENTION_DAYS = 14
-- First habit follows the theme; the rest are fixed hues picked to stay distinct from it and each other.
M.COLORS = { "primary", "#7aa2f7", "#9ece6a", "#bb9af7", "#7dcfff", "#e0af68", "#f7768e", "#73daca" }

-- Translucent variant of a palette role ("primary") or hex ("#rrggbb") color.
function M.tint(color, alpha)
  if string.sub(color, 1, 1) == "#" then
    return color .. string.format("%02x", math.floor(alpha * 255))
  end
  return color .. "/" .. alpha
end

-- Lua pattern matching `word` as a whole word: alphanumeric edges must not touch other
-- alphanumerics, so "gf" matches "gf xss" but not "gfx", and ".pdf" still matches "a.pdf".
local function wordPattern(word)
  local escaped = string.gsub(word, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  if string.find(word, "^%w") then
    escaped = "%f[%w]" .. escaped
  end
  if string.find(word, "%w$") then
    escaped = escaped .. "%f[%W]"
  end
  return escaped
end

-- Configured habits as a stable, name-sorted list of { name, glyph, patterns }.
-- `patterns` are Lua patterns (see wordPattern) for lowercased app ids and titles.
function M.habits()
  local map = noctalia.getConfig("habits") or {}
  local list = {}
  for name, spec in pairs(map) do
    -- Optional leading "icon |" picks the Tabler glyph.
    local glyph, rest = string.match(spec, "^%s*([%w%-]+)%s*|(.*)$")
    if glyph == nil then
      glyph, rest = "target", spec
    end
    local patterns = {}
    for part in string.gmatch(rest, "[^,]+") do
      local pattern = string.lower(noctalia.string.trim(part))
      if pattern ~= "" then
        table.insert(patterns, wordPattern(pattern))
      end
    end
    table.insert(list, { name = name, glyph = glyph, patterns = patterns })
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  for i, habit in ipairs(list) do
    habit.color = M.COLORS[(i - 1) % #M.COLORS + 1]
  end
  return list
end

function M.dayKey(time)
  return os.date("%Y-%m-%d", time)
end

-- Day keys for the last `count` days, oldest first.
function M.lastDays(count)
  local keys = {}
  local now = os.time()
  for offset = count - 1, 0, -1 do
    table.insert(keys, M.dayKey(now - offset * 86400))
  end
  return keys
end

function M.formatDuration(seconds)
  seconds = math.floor(seconds or 0)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  if h > 0 then
    return string.format("%dh %dm", h, m)
  end
  if m > 0 then
    return string.format("%dm", m)
  end
  return string.format("%ds", seconds)
end

-- data = { days = { ["YYYY-MM-DD"] = { [habit] = { 24 hourly seconds } } } }
function M.dataPath()
  return noctalia.pluginDataDir() .. "/habits.json"
end

function M.load()
  local raw = noctalia.readFile(M.dataPath())
  local data = raw and noctalia.json.decode(raw)
  if type(data) ~= "table" or type(data.days) ~= "table" then
    if raw ~= nil and raw ~= "" then
      -- Keep an unreadable file instead of silently overwriting it on the next save.
      noctalia.renameFile(M.dataPath(), M.dataPath() .. ".corrupt")
      noctalia.log("habits: unreadable habits.json moved to habits.json.corrupt")
    end
    data = { days = {} }
  end
  return data
end

-- Write through a temp file so a reader never sees a half-written file.
local function writeAtomic(path, content)
  noctalia.writeFile(path .. ".tmp", content)
  noctalia.renameFile(path .. ".tmp", path)
end

-- Snapshot taken before a reset; restore with: mv habits.json.bak habits.json
function M.backup(data)
  writeAtomic(M.dataPath() .. ".bak", noctalia.json.encode(data))
end

function M.save(data)
  local keep = {}
  for _, key in ipairs(M.lastDays(M.RETENTION_DAYS)) do
    keep[key] = true
  end
  for key in pairs(data.days) do
    if not keep[key] then
      data.days[key] = nil
    end
  end
  writeAtomic(M.dataPath(), noctalia.json.encode(data))
end

function M.add(data, habit, seconds, time)
  local key = M.dayKey(time)
  local day = data.days[key]
  if day == nil then
    day = {}
    data.days[key] = day
  end
  local hours = day[habit]
  if hours == nil then
    hours = table.create(24, 0)
    day[habit] = hours
  end
  local hour = tonumber(os.date("%H", time)) + 1
  hours[hour] = (hours[hour] or 0) + seconds
end

function M.sum(hours)
  local total = 0
  for _, seconds in ipairs(hours or {}) do
    total = total + seconds
  end
  return total
end

return M
