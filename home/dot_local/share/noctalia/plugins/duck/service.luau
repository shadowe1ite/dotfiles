--!nonstrict
-- Background watcher. It does not draw anything.
--
-- Alias generation shells out to ~/.local/bin/ddg-email, which already reads
-- the DuckDuckGo token from pass, calls the quack API, and copies the address
-- with wl-copy. This service only publishes what that script prints.
--
-- Mail watching is a separate Python process (scripts/watch.py). It reads Inbox and Spam. It reads the
-- Gmail address and app password from pass itself. Nothing secret is stored
-- in plugin settings or in the inbox file.
local common = require("./lib/common.luau")

local STALE_MS = 180000
local RETRY_MS = 5000

local startedAt = noctalia.nowMs()
local keep = 30
local notifyOn = true
local byUid = {}
local messages = {}
local known = {}
local hidden = {}
local baselines = {}
local address = ""
local status = "connecting"
local detail = ""
local generating = false
local watching = false
local watchStartedAt = 0
local lastBeat = 0
local pidFile = ""

local function readConfig()
  keep = math.max(10, math.min(100, tonumber(noctalia.getConfig("keep")) or 30))
  notifyOn = noctalia.getConfig("notify") ~= false
end

readConfig()

local function dataPath()
  local dir = noctalia.pluginDataDir()
  if type(dir) ~= "string" or dir == "" then
    return nil
  end
  return dir .. "/inbox.json"
end

local function pidPath()
  local dir = noctalia.pluginDataDir()
  if type(dir) ~= "string" or dir == "" then
    return ""
  end
  return dir .. "/watcher.pid"
end

local function unreadCount()
  local count = 0
  for _, row in ipairs(messages) do
    if row.unread then
      count += 1
    end
  end
  return count
end

local function publish()
  noctalia.state.set("duck", {
    status = status,
    detail = detail,
    address = address,
    generating = generating,
    unread = unreadCount(),
    messages = messages,
  })
end

local function sortMessages()
  table.sort(messages, function(a, b)
    if a.at == b.at then
      return (tonumber(a.uid) or 0) > (tonumber(b.uid) or 0)
    end
    return a.at > b.at
  end)
end

local function trim()
  sortMessages()
  while #messages > keep do
    local dropped = table.remove(messages)
    byUid[dropped.uid] = nil
    hidden[dropped.uid] = true
  end
end

local function hiddenList()
  local list = {}
  for uid in pairs(hidden) do
    table.insert(list, uid)
  end
  table.sort(list, function(a, b)
    return (tonumber(a) or 0) < (tonumber(b) or 0)
  end)
  while #list > 400 do
    hidden[table.remove(list, 1)] = nil
  end
  return list
end

local function save()
  local path = dataPath()
  if path == nil then
    return
  end
  local encoded = noctalia.json.encode({
    address = address,
    messages = messages,
    hidden = hiddenList(),
    baseline = baselines,
  })
  if type(encoded) == "string" then
    noctalia.writeFile(path, encoded)
  end
end

local function rowFrom(item, unread)
  return {
    uid = tostring(item.uid),
    alias = type(item.alias) == "string" and item.alias or "",
    sender = type(item.sender) == "string" and item.sender or "",
    subject = type(item.subject) == "string" and item.subject or "",
    preview = type(item.preview) == "string" and item.preview or "",
    otp = type(item.otp) == "string" and item.otp or "",
    at = type(item.at) == "number" and item.at or 0,
    unread = unread,
  }
end

local function store(item)
  local uid = tostring(item.uid or "")
  if uid == "" or hidden[uid] then
    return false
  end
  local prev = byUid[uid]
  local unread = item.unread ~= false
  if prev ~= nil then
    unread = prev.unread == true
  end
  local row = rowFrom(item, unread)
  local isNew = prev == nil
  if prev == nil then
    table.insert(messages, row)
  else
    for index, existing in ipairs(messages) do
      if existing.uid == uid then
        messages[index] = row
        break
      end
    end
  end
  byUid[uid] = row
  known[uid] = true
  return isNew
end

local function notify(row)
  if not notifyOn or not row.unread then
    return
  end
  local body = row.sender
  if row.subject ~= "" then
    body = body == "" and row.subject or body .. " — " .. row.subject
  end
  if row.otp ~= "" then
    body = body .. "\n" .. row.otp
  end
  noctalia.notify(noctalia.tr("notify.title"), body)
end

local function shouldNotify(row, isNew, live)
  if not isNew then
    return false
  end
  if live then
    return true
  end
  -- A cold start should not announce the whole mailbox. Mail that landed
  -- while the watcher was down still falls inside this window.
  return row.at > 0 and row.at >= math.floor(startedAt / 1000) - 15
end

local function ingest(item, live)
  local uid = tostring(item.uid or "")
  if uid == "" or hidden[uid] then
    return
  end
  local isNew = store(item)
  local row = byUid[tostring(item.uid)]
  if row ~= nil and shouldNotify(row, isNew, live) then
    notify(row)
  end
end

local function load()
  local path = dataPath()
  if path == nil then
    return
  end
  local raw = noctalia.readFile(path)
  if type(raw) ~= "string" or raw == "" then
    return
  end
  local data = noctalia.json.decode(raw)
  if type(data) ~= "table" then
    return
  end
  if type(data.address) == "string" then
    address = data.address
  end
  if type(data.hidden) == "table" then
    for _, uid in ipairs(data.hidden) do
      if type(uid) == "string" or type(uid) == "number" then
        hidden[tostring(uid)] = true
      end
    end
  end
  if type(data.baseline) == "table" then
    for box, uid in pairs(data.baseline) do
      if type(box) == "string" and (type(uid) == "string" or type(uid) == "number") then
        baselines[box] = tostring(uid)
      end
    end
  elseif type(data.baseline) == "string" or type(data.baseline) == "number" then
    if tostring(data.baseline) ~= "" then
      baselines["INBOX"] = tostring(data.baseline)
    end
  end
  -- No inbox marker yet: this file is the old backlog, so leave it unloaded.
  if baselines["INBOX"] == nil then
    return
  end
  if type(data.messages) == "table" then
    for _, item in ipairs(data.messages) do
      if type(item) == "table" then
        store(item)
      end
    end
  end
  trim()
end

local function quote(value)
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local function stopRecordedWatcher()
  if pidFile == "" then
    return
  end
  local raw = noctalia.readFile(pidFile)
  local pid = raw and tonumber(noctalia.string.trim(raw))
  if pid == nil or pid <= 1 then
    return
  end
  local cmdline = noctalia.readFile("/proc/" .. tostring(pid) .. "/cmdline") or ""
  if string.find(cmdline, "watch.py", 1, true) then
    noctalia.runAsync({ "kill", tostring(pid) })
  end
end

local function onLine(line)
  lastBeat = noctalia.nowMs()
  if type(line) ~= "string" or line == "" then
    return
  end
  local data = noctalia.json.decode(line)
  if type(data) ~= "table" or type(data.type) ~= "string" then
    return
  end
  if data.type == "heartbeat" then
    return
  end
  if data.type == "status" then
    status = type(data.state) == "string" and data.state or status
    detail = type(data.message) == "string" and data.message or ""
    publish()
    return
  end
  if data.type == "baseline" then
    local box = type(data.box) == "string" and data.box or "INBOX"
    local uid = tostring(data.uid or "")
    if uid ~= "" and baselines[box] ~= uid then
      baselines[box] = uid
      save()
    end
    return
  end
  if data.type == "snapshot" and type(data.messages) == "table" then
    for _, item in ipairs(data.messages) do
      if type(item) == "table" then
        ingest(item, false)
      end
    end
    trim()
    save()
    publish()
    return
  end
  if data.type == "message" and type(data.message) == "table" then
    ingest(data.message, true)
    trim()
    save()
    publish()
  end
end

local function startWatch()
  local script = (noctalia.pluginDir() or "") .. "/scripts/watch.py"
  if script == "/scripts/watch.py" or not noctalia.fileExists(script) then
    status = "error"
    detail = "watcher script is missing"
    publish()
    return
  end
  pidFile = pidPath()
  stopRecordedWatcher()
  local limit = tostring(keep)
  local cmd = "exec python3 -u " .. quote(script) .. " --limit " .. limit
  local marks = {}
  for box, uid in pairs(baselines) do
    if uid ~= "" then
      table.insert(marks, box .. "=" .. uid)
    end
  end
  table.sort(marks)
  if #marks > 0 then
    cmd ..= " --baseline " .. quote(table.concat(marks, ","))
  end
  if pidFile ~= "" then
    cmd ..= " --pid-file " .. quote(pidFile)
  end
  watching = noctalia.runStream(cmd, onLine) == true
  watchStartedAt = noctalia.nowMs()
  lastBeat = watchStartedAt
  if not watching then
    status = "error"
    detail = "could not start the watcher"
    publish()
  end
end

local function generate()
  if generating then
    return
  end
  local bin = noctalia.expandPath("~/.local/bin/ddg-email")
  if not noctalia.fileExists(bin) then
    noctalia.notifyError(noctalia.tr("notify.generate_failed"), bin)
    return
  end
  generating = true
  publish()
  noctalia.runAsync({ bin }, function(result)
    generating = false
    local code = result and result.exitCode or 1
    if code == 0 then
      local created = noctalia.string.trim(result.stdout or "")
      if string.find(created, "@duck.com", 1, true) then
        address = created
        save()
      else
        noctalia.notifyError(noctalia.tr("notify.generate_failed"), noctalia.tr("notify.empty"))
      end
    else
      local err = noctalia.string.trim((result and (result.stderr or result.stdout)) or "")
      if #err > 180 then
        err = string.sub(err, 1, 180)
      end
      noctalia.notifyError(noctalia.tr("notify.generate_failed"), err)
    end
    publish()
  end)
end

local function forget(uid)
  uid = tostring(uid or "")
  if uid == "" then
    return
  end
  hidden[uid] = true
  if byUid[uid] == nil then
    return
  end
  byUid[uid] = nil
  local kept = {}
  for _, row in ipairs(messages) do
    if row.uid ~= uid then
      table.insert(kept, row)
    end
  end
  messages = kept
end

local function clearAll()
  for _, row in ipairs(messages) do
    hidden[row.uid] = true
  end
  messages = {}
  byUid = {}
end

local function markRead(uid)
  if uid == nil or uid == "" then
    for _, row in ipairs(messages) do
      row.unread = false
    end
  else
    local row = byUid[tostring(uid)]
    if row ~= nil then
      row.unread = false
    end
  end
  save()
  publish()
end

local function pokeWatcher()
  local raw = pidFile ~= "" and noctalia.readFile(pidFile) or nil
  local pid = raw and tonumber(noctalia.string.trim(raw))
  if pid == nil or pid <= 1 then
    startWatch()
    return
  end
  local cmdline = noctalia.readFile("/proc/" .. tostring(pid) .. "/cmdline") or ""
  if not string.find(cmdline, "watch.py", 1, true) then
    startWatch()
    return
  end
  noctalia.runAsync({ "kill", "-USR1", tostring(pid) })
end

local function dispatch(action, value)
  if action == "generate" then
    generate()
  elseif action == "read" then
    markRead(type(value) == "string" and value or "")
  elseif action == "delete" then
    forget(value)
    save()
    publish()
  elseif action == "clear" then
    clearAll()
    save()
    publish()
  elseif action == "refresh" then
    pokeWatcher()
  end
end

function update()
  local now = noctalia.nowMs()
  local stale = watching and now - lastBeat > STALE_MS
  if (not watching or stale) and now - watchStartedAt > RETRY_MS then
    if stale then
      status = "reconnecting"
      detail = "watcher went quiet"
      publish()
    end
    startWatch()
  end
  noctalia.setUpdateInterval(RETRY_MS)
end

function onConfigChanged()
  local previous = keep
  readConfig()
  trim()
  save()
  publish()
  if keep ~= previous then
    watching = false
    watchStartedAt = 0
  end
end

function onIpc(event, payload)
  dispatch(event, payload or "")
end

function onExit()
  stopRecordedWatcher()
end

noctalia.state.watch("request", function(req)
  if type(req) ~= "table" or type(req.at) ~= "number" or req.at < startedAt then
    return
  end
  dispatch(req.action, req.value)
end)

load()
publish()
startWatch()
noctalia.setUpdateInterval(RETRY_MS)
