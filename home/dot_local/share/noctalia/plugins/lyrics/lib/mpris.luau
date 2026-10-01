-- MPRIS straight off the session bus. One `busctl monitor` reports property
-- changes, seeks and players coming and going; short busctl calls fill in the
-- full state when a player shows up or when we want a fresh position.
local M = {}

local PREFIX = "org.mpris.MediaPlayer2."
local OBJECT = "/org/mpris/MediaPlayer2"
local PLAYER = "org.mpris.MediaPlayer2.Player"

local MATCHES = {
  "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/mpris/MediaPlayer2',arg0='org.mpris.MediaPlayer2.Player'",
  "type='signal',interface='org.mpris.MediaPlayer2.Player',member='Seeked',path='/org/mpris/MediaPlayer2'",
  "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0namespace='org.mpris.MediaPlayer2'",
}

local players = {} -- well-known name -> player
local owners = {} -- unique connection name (":1.42") -> well-known name
local notify = function(_player, _why) end

local function busctl(args, callback)
  local argv = { "busctl", "--user", "--json=short" }
  for _, arg in ipairs(args) do
    table.insert(argv, arg)
  end
  noctalia.runAsync(argv, function(result)
    if result.exitCode ~= 0 then
      callback(nil)
      return
    end
    callback(noctalia.json.decode(result.stdout))
  end)
end

-- busctl wraps every variant as { type = "s", data = ... }
local function field(dict, key)
  local v = dict[key]
  if type(v) == "table" then
    return v.data
  end
  return nil
end

local function str(v)
  return type(v) == "string" and v or ""
end

local function setMetadata(player, metadata)
  local artists = field(metadata, "xesam:artist")
  if type(artists) == "string" then
    artists = { artists }
  end
  player.title = str(field(metadata, "xesam:title"))
  player.artists = type(artists) == "table" and artists or {}
  player.album = str(field(metadata, "xesam:album"))
  player.length = (tonumber(field(metadata, "mpris:length")) or 0) / 1e6
  player.url = str(field(metadata, "xesam:url"))
  player.trackId = str(field(metadata, "mpris:trackid"))
  player.art = str(field(metadata, "mpris:artUrl"))
end

function M.trackOf(player)
  return player.title .. "\n" .. table.concat(player.artists, ", ") .. "\n" .. player.album
end

function M.position(player, now)
  local pos = player.pos
  if player.status == "Playing" then
    pos += ((now or noctalia.nowMs()) - player.at) / 1000 * player.rate
  end
  if player.length > 0 and pos > player.length then
    pos = player.length
  end
  return math.max(pos, 0)
end

local function rebase(player, at)
  player.pos = M.position(player, at)
  player.at = at
end

local function apply(player, props, at)
  local status = field(props, "PlaybackStatus")
  local rate = field(props, "Rate")
  local metadata = field(props, "Metadata")
  local position = field(props, "Position")

  if status ~= nil or rate ~= nil then
    rebase(player, at)
  end
  if rate ~= nil then
    player.rate = tonumber(rate) or 1
  end
  if status ~= nil then
    player.status = status
    if status == "Playing" then
      player.playedAt = at
    end
  end
  if metadata ~= nil then
    local before = M.trackOf(player)
    setMetadata(player, metadata)
    if M.trackOf(player) ~= before then
      player.pos = 0
      player.at = at
    end
  end
  if position ~= nil then
    player.pos = (tonumber(position) or 0) / 1e6
    player.at = at
  end
end

function M.refresh(player)
  busctl({ "call", player.bus, OBJECT, "org.freedesktop.DBus.Properties", "GetAll", "s", PLAYER }, function(reply)
    if reply == nil or players[player.bus] ~= player then
      return
    end
    apply(player, reply.data[1] or {}, noctalia.nowMs())
    notify(player, "refresh")
  end)
end

-- MPRIS never signals position changes, only seeks, so drift is fixed by asking.
function M.syncPosition(player)
  busctl({ "get-property", player.bus, OBJECT, PLAYER, "Position" }, function(reply)
    if reply == nil or players[player.bus] ~= player then
      return
    end
    player.pos = (tonumber(reply.data) or 0) / 1e6
    player.at = noctalia.nowMs()
    notify(player, "position")
  end)
end

local function add(bus, owner)
  local player = players[bus]
  if player == nil then
    player = {
      bus = bus,
      name = string.sub(bus, #PREFIX + 1),
      status = "Stopped",
      title = "",
      artists = {},
      album = "",
      length = 0,
      url = "",
      trackId = "",
      art = "",
      pos = 0,
      at = noctalia.nowMs(),
      rate = 1,
      playedAt = 0,
    }
    players[bus] = player
  elseif player.owner ~= nil then
    owners[player.owner] = nil
  end
  player.owner = owner
  owners[owner] = bus
  M.refresh(player)
end

local function remove(bus)
  local player = players[bus]
  if player == nil then
    return
  end
  players[bus] = nil
  owners[player.owner] = nil
  notify(player, "gone")
end

local function onSignal(line)
  local msg = noctalia.json.decode(line)
  if type(msg) ~= "table" or msg.type ~= "signal" or type(msg.payload) ~= "table" then
    return
  end
  local args = msg.payload.data or {}
  -- busctl stamps each message on arrival; closer to the truth than "now"
  local at = tonumber(msg["timestamp-realtime"])
  at = at and at / 1000 or noctalia.nowMs()

  if msg.member == "NameOwnerChanged" then
    if args[3] == "" then
      remove(args[1])
    else
      add(args[1], args[3])
    end
    return
  end

  local player = players[owners[msg.sender] or ""]
  if player == nil then
    return
  end
  if msg.member == "Seeked" then
    player.pos = (tonumber(args[1]) or 0) / 1e6
    player.at = at
    notify(player, "seeked")
  elseif msg.member == "PropertiesChanged" then
    apply(player, args[2] or {}, at)
    -- a few players only invalidate properties instead of sending new values
    if type(args[3]) == "table" and #args[3] > 0 then
      M.refresh(player)
    end
    notify(player, "changed")
  end
end

function M.start(callback)
  notify = callback

  local cmd = "exec busctl --user --json=short monitor"
  for _, match in ipairs(MATCHES) do
    cmd ..= ' --match "' .. match .. '"'
  end
  noctalia.runStream(cmd, onSignal)

  -- players that were already running before we started listening
  busctl({ "list", "--acquired" }, function(names)
    for _, entry in ipairs(names or {}) do
      if string.sub(entry.name, 1, #PREFIX) == PREFIX and players[entry.name] == nil then
        add(entry.name, entry.connection)
      end
    end
  end)
end

function M.players()
  return players
end

-- SetPosition needs the track id; players that don't have one get a relative seek.
-- The "--" keeps busctl from reading a negative offset as an option.
function M.seek(player, seconds)
  local args = { "busctl", "--user", "call", "--", player.bus, OBJECT, PLAYER }
  if player.trackId ~= "" then
    table.insert(args, "SetPosition")
    table.insert(args, "ox")
    table.insert(args, player.trackId)
    table.insert(args, string.format("%d", math.max(seconds, 0) * 1e6))
  else
    table.insert(args, "Seek")
    table.insert(args, "x")
    table.insert(args, string.format("%d", (seconds - M.position(player)) * 1e6))
  end
  noctalia.runAsync(args)
end

return M
