-- Lyrics cache: one small JSON file per track in the plugin's data dir.
local M = {}

-- Synced and instrumental results are kept for good. Anything else gets
-- looked up again after a day, someone may have uploaded lyrics since.
local RETRY_AFTER = 24 * 3600

local dir = nil
local offsets = nil

local function folder()
  if dir == nil then
    local base = noctalia.pluginDataDir()
    if base == nil then
      return nil
    end
    dir = base .. "/cache"
    noctalia.mkdirAll(dir)
  end
  return dir
end

local function offsetsFile()
  local base = noctalia.pluginDataDir()
  return base and (base .. "/offsets.json")
end

-- FNV-1a. h * 16777619 is split into h * 403 + h << 24 so it stays exact in a double.
local function hash(s)
  local h = 2166136261
  for i = 1, #s do
    h = bit32.bxor(h, string.byte(s, i))
    h = (h * 403 + bit32.lshift(h, 24)) % 4294967296
  end
  return string.format("%08x", h)
end

local function key(track)
  return string.lower(table.concat({
    track.title,
    table.concat(track.artists, ", "),
    track.album,
    tostring(math.floor(track.length + 0.5)),
  }, "\n"))
end

local function path(k)
  local d = folder()
  return d and (d .. "/" .. hash(k) .. ".json")
end

function M.get(track)
  local k = key(track)
  local file = path(k)
  local raw = file and noctalia.readFile(file)
  if raw == nil then
    return nil
  end
  local entry = noctalia.json.decode(raw)
  if type(entry) ~= "table" or entry.key ~= k then
    return nil
  end
  local keep = entry.kind == "synced" or entry.kind == "instrumental"
  if not keep and os.time() - (entry.time or 0) > RETRY_AFTER then
    return nil
  end
  return { kind = entry.kind, lyrics = entry.lyrics, id = entry.id }
end

function M.put(track, result)
  if result.kind == "error" then
    return
  end
  local k = key(track)
  local file = path(k)
  if file == nil then
    return
  end
  noctalia.writeFile(file, noctalia.json.encode({
    key = k,
    kind = result.kind,
    lyrics = result.lyrics,
    id = result.id,
    time = os.time(),
  }))
end

-- Per-track timing corrections, in seconds. Kept apart from the cache so they
-- survive a refetch.
local function loadOffsets()
  if offsets == nil then
    local file = offsetsFile()
    local raw = file and noctalia.readFile(file)
    offsets = raw and noctalia.json.decode(raw) or {}
  end
  return offsets
end

function M.offset(track)
  return tonumber(loadOffsets()[key(track)]) or 0
end

function M.setOffset(track, seconds)
  local all = loadOffsets()
  all[key(track)] = seconds ~= 0 and seconds or nil
  local file = offsetsFile()
  if file ~= nil then
    noctalia.writeFile(file, noctalia.json.encode(all))
  end
end

return M
