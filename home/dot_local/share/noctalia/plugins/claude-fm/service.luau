-- Background service: owns the mpv process and reads mpv's REAL state over its
-- IPC socket (so pauses, resumes, buffering and exits that happen outside the
-- plugin are noticed), and publishes `playback` for the UI entries. Light: no
-- audio capture, and it wakes only as often as it needs to.
local common = require("./lib/common.luau")
local mpv = require("./lib/mpv.luau")

local SOCK = common.socketPath()
local DATA = noctalia.pluginDataDir()
local STATE_PATH = DATA .. "/state.json"
-- Claude FM 1.1 ran cava while playing, and the host did not always stop it on a
-- restart: kill any leftover at load (this version never starts one).
local OLD_CAVA_PATTERN = "cava -p " .. DATA .. "/cava.conf"

local PARKED_MS = 60000
local POLL_FIRST_MS = 300
local POLL_LOADING_MS = 500
local POLL_ACTIVE_MS = 2000
local POLL_TIMEOUT_MS = 6000
local VOLUME_HOLD_MS = 1500 -- ignore mpv's volume this long after we set it

local startedAt = noctalia.nowMs()
local status = "stopped" -- stopped | loading | playing | paused
local title = ""
local showTitle = noctalia.getConfig("show_title")
if showTitle == nil then
  showTitle = true
end

-- Volume: the saved value wins only while the setting is unchanged since it
-- was saved; changing the setting in the UI changes the volume.
local cfgVolume = tonumber(noctalia.getConfig("volume")) or 70
local volume = cfgVolume
do
  local raw = noctalia.readFile(STATE_PATH)
  local ok, data = pcall(function()
    return raw and noctalia.json.decode(raw)
  end)
  if ok and type(data) == "table" and type(data.volume) == "number" and data.cfg == cfgVolume then
    volume = data.volume
  end
end
local volumeSetAt = -1e9

local launchedAt = 0
local nextPollAt = 0
local pollInFlight = false
local pollStartedAt = 0

local function publish()
  noctalia.state.set("playback", { status = status, title = title, volume = volume })
end

local function persist()
  noctalia.writeFile(STATE_PATH, noctalia.json.encode({ volume = volume, cfg = cfgVolume }))
end

-- Fire-and-forget JSON command to mpv.
local function sendCmd(json)
  noctalia.runAsync({ "sh", "-c", "printf '%s\\n' '" .. json .. "' | socat - " .. SOCK .. " >/dev/null 2>&1" })
end

-- Wake as often as the state needs: twice a second while loading, every 2 s
-- while playing or paused, not at all (parked) while stopped.
local function schedule()
  if status == "loading" then
    noctalia.setUpdateInterval(POLL_LOADING_MS)
  elseif common.isActive(status) then
    noctalia.setUpdateInterval(POLL_ACTIVE_MS)
  else
    noctalia.setUpdateInterval(PARKED_MS)
  end
end

local function setStatus(new)
  if new == status then
    return
  end
  status = new
  if new == "stopped" then
    title = ""
  end
  schedule()
  publish()
end

-- r: parsed mpv state, or nil when mpv did not answer.
local function applyPoll(r, now)
  local changed = false
  if r ~= nil then
    if showTitle then
      local t = mpv.cleanTitle(r.title, common.STREAM_ID)
      if t ~= nil and t ~= title then
        title = t
        changed = true
      end
    end
    if type(r.volume) == "number" and now - volumeSetAt > VOLUME_HOLD_MS then
      local v = math.floor(r.volume + 0.5)
      if v ~= volume then
        volume = v
        persist()
        changed = true
      end
    end
  end
  local new = mpv.derive(r, { status = status, launchedAt = launchedAt, now = now })
  nextPollAt = now + (new == "loading" and POLL_LOADING_MS or POLL_ACTIVE_MS)
  if new ~= status then
    setStatus(new) -- publishes
  else
    schedule()
    if changed then
      publish()
    end
  end
end

local function onPoll(result)
  pollInFlight = false
  if status == "stopped" then
    return -- stopped while the poll was in flight
  end
  applyPoll(result ~= nil and mpv.parse(result.stdout, noctalia.json.decode) or nil, noctalia.nowMs())
end

local function doPoll()
  pollInFlight = true
  pollStartedAt = noctalia.nowMs()
  noctalia.runAsync({ "sh", "-c", mpv.pollScript(SOCK) }, onPoll)
end

-- commands -----------------------------------------------------------------

local function launch()
  local now = noctalia.nowMs()
  launchedAt = now
  nextPollAt = now + POLL_FIRST_MS
  pollInFlight = false
  title = ""
  setStatus("loading")
  -- runStream keeps a long-lived process alive; `exec` makes the shell become
  -- mpv so stopping the stream stops mpv.
  local cmd = "exec mpv --no-video --vid=no --vo=null --force-window=no --audio-display=no"
    .. " --no-terminal --really-quiet --idle=no --cache=yes"
    .. " --volume=" .. tostring(volume)
    .. " --input-ipc-server=" .. SOCK
    .. " --ytdl-format=bestaudio/best '" .. common.STREAM_URL .. "'"
  noctalia.runStream(cmd, function(_line) end)
  noctalia.setUpdateInterval(POLL_FIRST_MS) -- the first poll comes soon
end

local function play()
  if status == "paused" then
    sendCmd('{"command":["set_property","pause",false]}')
    nextPollAt = noctalia.nowMs() + POLL_LOADING_MS
    setStatus("playing")
  elseif status == "stopped" then
    launch()
  end
end

local function pause()
  if status ~= "playing" and status ~= "loading" then
    return
  end
  sendCmd('{"command":["set_property","pause",true]}')
  setStatus("paused")
end

local function stop()
  sendCmd('{"command":["quit"]}')
  setStatus("stopped")
  noctalia.setUpdateInterval(PARKED_MS)
end

-- Toggle: pause what plays, resume what is paused, cancel a load, start a stopped radio.
local function toggle()
  if status == "playing" then
    pause()
  elseif status == "loading" then
    stop()
  else
    play()
  end
end

local function setVolume(v)
  v = math.floor(tonumber(v) or volume)
  v = math.max(0, math.min(100, v))
  volume = v
  volumeSetAt = noctalia.nowMs()
  if common.isActive(status) then
    sendCmd('{"command":["set_property","volume",' .. tostring(volume) .. "]}")
  end
  publish()
  persist()
end

-- tick ---------------------------------------------------------------------

-- Polls mpv while the radio is active; parked while it is stopped.
function update()
  local now = noctalia.nowMs()
  if common.isActive(status) then
    if pollInFlight and now - pollStartedAt > POLL_TIMEOUT_MS then
      pollInFlight = false
    end
    if not pollInFlight and now >= nextPollAt then
      doPoll()
    end
  end
  schedule()
end

-- UI entries publish { action, value, at }.
noctalia.state.watch("request", function(req)
  if type(req) ~= "table" or type(req.at) ~= "number" or req.at < startedAt then
    return
  end
  local a = req.action
  if a == "play" then
    play()
  elseif a == "pause" then
    pause()
  elseif a == "toggle" then
    toggle()
  elseif a == "stop" then
    stop()
  elseif a == "setVolume" then
    setVolume(req.value)
  elseif a == "volUp" then
    setVolume(volume + 5)
  elseif a == "volDown" then
    setVolume(volume - 5)
  end
end)

-- External control, e.g. a WM hotkey:
--   noctalia msg plugin shadowe1ite/claude-fm:service all toggle
function onIpc(event, _payload)
  if event == "toggle" then
    toggle()
  elseif event == "play" then
    play()
  elseif event == "pause" then
    pause()
  elseif event == "stop" then
    stop()
  elseif event == "volume-up" then
    setVolume(volume + 5)
  elseif event == "volume-down" then
    setVolume(volume - 5)
  end
end

-- A radio that survived a plugin or shell restart is still playing: adopt it
-- instead of showing "stopped" (and letting Play start a second one on top).
-- Autoplay waits for this answer for the same reason.
local function adopt()
  noctalia.runAsync({ "sh", "-c", mpv.pollScript(SOCK) }, function(result)
    if status ~= "stopped" then
      return -- the user already started one
    end
    local now = noctalia.nowMs()
    local r = result ~= nil and mpv.parse(result.stdout, noctalia.json.decode) or nil
    if r == nil or r.idleActive == true then
      if noctalia.getConfig("autoplay") == true then
        play()
      end
      return
    end
    launchedAt = now
    applyPoll(r, now)
  end)
end

publish()
noctalia.setUpdateInterval(PARKED_MS)
noctalia.runAsync({ "pkill", "-f", OLD_CAVA_PATTERN })
adopt()
