-- Background service: follows MPRIS players, picks the one worth showing,
-- looks up lyrics for whatever it is playing and keeps the current line.
local mpris = require("./lib/mpris.luau")
local lrclib = require("./lib/lrclib.luau")
local lrc = require("./lib/lrc.luau")
local cache = require("./lib/cache.luau")

local RETRY_MS = 30000
-- Players only report seeks, so the position is re-read now and then to catch drift.
local RESYNC_MS = 5000
local IDLE_MS = 60000

local offset = (noctalia.getConfig("offset") or 0) / 1000
local only = noctalia.getConfig("players") or {}
local ignored = noctalia.getConfig("ignored_players") or {}

local active = nil
local published = nil

local track = nil -- the track `lyrics` belongs to
local song = nil
local lyrics = { kind = "none" }
local retryAt = 0
local trackOffset = 0

local lines = {}
local index = -1
local lastSync = 0
local wantSync = false

local function matches(player, names)
  local name = string.lower(player.name)
  for _, entry in ipairs(names) do
    entry = string.lower(noctalia.string.trim(entry))
    if entry ~= "" and string.find(name, entry, 1, true) then
      return true
    end
  end
  return false
end

local function wanted(player)
  if #only > 0 and not matches(player, only) then
    return false
  end
  return not matches(player, ignored)
end

local function rank(player)
  if player.status == "Playing" then
    return 2
  elseif player.status == "Paused" then
    return 1
  end
  return 0
end

-- Stick with the current player while it plays; otherwise prefer whatever is
-- playing, then whoever played most recently.
local function pick()
  local players = mpris.players()
  if active ~= nil and players[active.bus] ~= active then
    active = nil
  end
  if active ~= nil and active.status == "Playing" then
    return active
  end
  local best = active
  for _, player in pairs(players) do
    if not wanted(player) then
      continue
    end
    if best == nil or rank(player) > rank(best) or (rank(player) == rank(best) and player.playedAt > best.playedAt) then
      best = player
    end
  end
  return best
end

local function snapshot(player)
  if player == nil then
    return {}
  end
  return {
    bus = player.bus,
    name = player.name,
    status = player.status,
    title = player.title,
    artist = table.concat(player.artists, ", "),
    album = player.album,
    length = player.length,
  }
end

local function changed(a, b)
  if a == nil or b == nil then
    return true
  end
  for k, v in pairs(a) do
    if b[k] ~= v then
      return true
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return true
    end
  end
  return false
end

local function publish()
  local snap = snapshot(active)
  if changed(snap, published) then
    published = snap
    noctalia.state.set("player", snap)
  end
end

local function setLine(i, pos, now)
  if i == index then
    return
  end
  index = i
  local line, upcoming = lines[i], lines[i + 1]
  local rate = active ~= nil and active.rate > 0 and active.rate or 1
  noctalia.state.set("line", {
    index = i,
    text = line and line.text or "",
    next = upcoming and upcoming.text or "",
    -- wall clock, so the widget can pace scrolling to how long the line is sung
    startedAt = line and pos and now - (pos - line.time) * 1000 / rate or nil,
    endsAt = upcoming and pos and now + (upcoming.time - pos) * 1000 / rate or nil,
  })
end

-- Publishes the line for the current position and sleeps until the next one is due.
local function tick()
  if active == nil or lyrics.kind ~= "synced" then
    setLine(0)
    noctalia.setUpdateInterval(IDLE_MS)
    return
  end

  local now = noctalia.nowMs()
  local pos = mpris.position(active, now) + offset + trackOffset
  local i = lrc.find(lines, pos)
  setLine(i, pos, now)

  if active.status ~= "Playing" then
    noctalia.setUpdateInterval(IDLE_MS)
    return
  end
  if now - lastSync >= RESYNC_MS or (wantSync and now - lastSync >= 1000) then
    lastSync = now
    wantSync = false
    mpris.syncPosition(active)
  end

  local wait = RESYNC_MS - (now - lastSync)
  local upcoming = lines[i + 1]
  if upcoming ~= nil and active.rate > 0 then
    wait = math.min(wait, (upcoming.time - pos) * 1000 / active.rate)
  end
  noctalia.setUpdateInterval(math.max(wait, 16))
end

local function publishLyrics()
  -- the panel shows the whole thing, the widget only cares about the state
  noctalia.state.set("lyrics", {
    state = lyrics.kind,
    lines = lines,
    text = lyrics.kind == "plain" and lyrics.lyrics or nil,
  })
end

local function setLyrics(result)
  lyrics = result
  lines = result.kind == "synced" and lrc.parse(result.lyrics) or {}
  index = -1
  publishLyrics()
  tick()
end

-- "song.lrc" sitting next to "song.flac" beats any lookup. Only works for
-- players that put a file:// url in their metadata.
local function sidecar(player)
  if string.sub(player.url, 1, 7) ~= "file://" then
    return nil
  end
  local file = noctalia.string.urlDecode(string.sub(player.url, 8))
  local text = noctalia.readFile((string.gsub(file, "%.[^./]*$", "")) .. ".lrc")
  if text == nil then
    return nil
  end
  if #lrc.parse(text) == 0 then
    return { kind = "plain", lyrics = text }
  end
  return { kind = "synced", lyrics = text }
end

local function fetchLyrics(force)
  if active == nil or active.title == "" then
    if track ~= nil then
      track = nil
      setLyrics({ kind = "none" })
    end
    return
  end

  local key = mpris.trackOf(active)
  if key == track and not force and not (lyrics.kind == "error" and noctalia.nowMs() >= retryAt) then
    return
  end
  track = key
  song = {
    title = active.title,
    artists = active.artists,
    album = active.album,
    length = active.length,
  }
  trackOffset = cache.offset(song)

  local found = sidecar(active)
  if found ~= nil then
    setLyrics(found)
    return
  end

  local cached = not force and cache.get(song)
  if cached then
    setLyrics(cached)
    return
  end

  local target = song
  setLyrics({ kind = "loading" })
  lrclib.find(target, function(result)
    -- keep it even if the track changed meanwhile, it'll come up again
    cache.put(target, result)
    if key ~= track then
      return
    end
    if result.kind == "error" then
      retryAt = noctalia.nowMs() + RETRY_MS
    end
    setLyrics(result)
  end)
end

-- Positive values show lines earlier, same as the offset setting.
local function nudge(seconds)
  if song == nil or lyrics.kind ~= "synced" then
    return
  end
  trackOffset = math.floor((trackOffset + seconds) * 1000 + 0.5) / 1000
  cache.setOffset(song, trackOffset)
  publishLyrics()
  tick()
end

local function handle(action, value)
  if action == "refetch" then
    fetchLyrics(true)
  elseif action == "nudge" then
    nudge(tonumber(value) or 0)
  end
end

function update()
  tick()
end

-- noctalia msg plugin shadow/lyrics:service all refetch
-- noctalia msg plugin shadow/lyrics:service all nudge -0.5
function onIpc(event, payload)
  handle(event, payload)
end

-- Clicking a line in the panel jumps there. Shared state outlives a reload,
-- so a request older than this runtime has been handled already.
local startedAt = noctalia.nowMs()
noctalia.state.watch("seek", function(req)
  if type(req) == "table" and (req.at or 0) >= startedAt and active ~= nil then
    -- a hair past the line's start so it's the one that shows
    mpris.seek(active, req.time - offset - trackOffset + 0.05)
  end
end)

mpris.start(function(_player, why)
  active = pick()
  publish()
  fetchLyrics()
  if why ~= "position" and why ~= "seeked" then
    wantSync = true
  end
  if why ~= "position" then
    -- seeks and pauses shift the line's timing even when the line stays the same
    index = -1
  end
  tick()
end)

publish()
setLyrics(lyrics)
