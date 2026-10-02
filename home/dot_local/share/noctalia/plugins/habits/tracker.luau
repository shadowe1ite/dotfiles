-- Headless tracker: follows niri's focused window through its event stream (no polling)
-- and credits focused time to the first habit whose pattern matches the app id or title.
local common = require("./lib/common.luau")

local TICK_MS = 5000
-- A gap longer than this between credits means suspend or a stalled runtime: drop it.
local MAX_GAP_SECONDS = 30

local habits = common.habits()
local data = common.load()
local windows = {} -- niri window id -> { app, title } (lowercased)
local focusedId = nil
local current = nil -- habit name being credited
local lastCredit = os.time()
local paused = false
local dirty = false
-- Shared state outlives a reload; only act on panel requests made after this runtime started.
local startedAt = noctalia.nowMs()

local function publish()
  noctalia.state.set("data", data)
  noctalia.state.set("current", current or "")
  noctalia.state.set("paused", paused)
end

local function credit()
  local now = os.time()
  local elapsed = now - lastCredit
  lastCredit = now
  if paused or current == nil or elapsed <= 0 or elapsed > MAX_GAP_SECONDS then
    return
  end
  common.add(data, current, elapsed, now)
  dirty = true
end

local function matchHabit()
  local window = focusedId and windows[focusedId]
  if window == nil then
    return nil
  end
  for _, habit in ipairs(habits) do
    for _, pattern in ipairs(habit.patterns) do
      if string.find(window.app, pattern) or string.find(window.title, pattern) then
        return habit.name
      end
    end
  end
  return nil
end

local function refocus()
  local habit = matchHabit()
  if habit ~= current then
    credit()
    current = habit
    publish()
  end
end

local function remember(window)
  if type(window) ~= "table" or type(window.id) ~= "number" then
    return
  end
  windows[window.id] = {
    app = string.lower(type(window.app_id) == "string" and window.app_id or ""),
    title = string.lower(type(window.title) == "string" and window.title or ""),
  }
  if window.is_focused == true then
    focusedId = window.id
  end
end

local function onEvent(line)
  local event = noctalia.json.decode(line)
  if type(event) ~= "table" then
    return
  end
  if event.WindowsChanged then
    windows = {}
    focusedId = nil
    for _, window in ipairs(event.WindowsChanged.windows or {}) do
      remember(window)
    end
  elseif event.WindowOpenedOrChanged then
    -- Also fires on title changes, e.g. a terminal starting gdb.
    remember(event.WindowOpenedOrChanged.window)
  elseif event.WindowClosed then
    local id = event.WindowClosed.id
    windows[id] = nil
    if focusedId == id then
      focusedId = nil
    end
  elseif event.WindowFocusChanged then
    local id = event.WindowFocusChanged.id
    focusedId = type(id) == "number" and id or nil
  end
  refocus()
end

-- grep drops layout/workspace chatter so the script only wakes for window events.
local started = noctalia.runStream(
  [[niri msg --json event-stream | grep --line-buffered -E '^\{"Window(sChanged|OpenedOrChanged|Closed|FocusChanged)"']],
  onEvent
)
if not started then
  noctalia.log("habits: failed to start niri event stream")
end

noctalia.setUpdateInterval(TICK_MS)
publish()

function update()
  credit()
  if dirty then
    common.save(data)
    dirty = false
    publish()
  end
end

function onConfigChanged()
  habits = common.habits()
  refocus()
  publish()
end

-- noctalia msg plugin shadow/habits:tracker all pause|resume|reset
function onIpc(event)
  if event == "pause" then
    credit()
    paused = true
  elseif event == "resume" then
    lastCredit = os.time()
    paused = false
  elseif event == "reset" then
    common.backup(data)
    data = { days = {} }
    dirty = true
  end
  update()
  publish()
end

-- Pause button in the panel.
noctalia.state.watch("pauseRequest", function(request)
  if type(request) == "table" and (request.at or 0) > startedAt and request.paused ~= paused then
    onIpc(request.paused and "pause" or "resume")
  end
end)

-- Reset button in the panel (after its confirm step).
noctalia.state.watch("resetRequest", function(request)
  if type(request) == "number" and request > startedAt then
    onIpc("reset")
  end
end)

function onExit()
  credit()
  common.save(data)
end
