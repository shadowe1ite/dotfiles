--!nonstrict
-- The orb's line to Hermes. The only Hermes module that touches noctalia.*: the API key from
-- the keyring, the public status poll, the chat stream and API-server calls (bearer key).
-- The pure pieces it drives live beside it: requests, sse, chat, views.
--
--   local c = client.new(cfg, publish)   -- publish(key, value) -> noctalia.state.set
--   c:loadSecrets(done)  c:pollStatus(done)  c:send(text)  c:stop()  c:newChat()  c:history()
--   c:adopt(id)  c:loadChats(done)  c:api(method, path, body, done)  c:tick(nowMs)
--   files: c:pickFiles(done)  c:detach(i)  c:saveFile(m, f)  c:openFile(m, f)
--   commands: c:note(text)  c:resend()  c:rename(title)  c:fork(title)  c:modelOptions(done)

local requests = require("./requests.luau")
local sse = require("./sse.luau")
local chat = require("./chat.luau")
local views = require("./views.luau")
local media = require("./media.luau")

local M = {}

local CHAT_PUBLISH_MS = 100 -- the streamed reply renders at most 10 times a second
local MAX_MESSAGES = 50
local BUSY_RETRY_MS = 5000

local Client = {}
Client.__index = Client

local function decode(body)
  if type(body) ~= "string" or body == "" then
    return nil
  end
  return (noctalia.json.decode(body))
end

function M.new(cfg, publish)
  local self = setmetatable({
    cfg = cfg,
    publish = publish,
    chat = chat.new(nil),
    stream = nil,
    link = "unknown",
    status = nil,
    dataDir = noctalia.pluginDataDir(),
    lastChatPublish = 0,
    chatDirty = false,
    retry = nil, -- { at, text } after a 429
    finishedAt = nil,
    failedAt = nil,
  }, Client)
  self:loadSession()
  return self
end

-- ── link state ───────────────────────────────────────────────────────────────

function Client:setLink(status, detail)
  if self.link ~= status then
    self.link = status
    noctalia.log(`orb-hermes: link {status}{if detail then " (" .. detail .. ")" else ""}`)
  end
  self.publish("orb.hermes.link", { status = status, detail = detail })
end

-- ── secrets ──────────────────────────────────────────────────────────────────

local function lookup(kind, done)
  local accepted = noctalia.runAsync({ "secret-tool", "lookup", "service", "orb-hermes", "kind", kind }, function(r)
    local value = nil
    if r ~= nil and r.exitCode == 0 then
      value = (string.gsub(r.stdout or "", "%s+$", ""))
    end
    done(if value ~= nil and value ~= "" then value else nil)
  end)
  if not accepted then
    done(nil)
  end
end

function Client:loadSecrets(done)
  lookup("api-key", function(key)
    self.cfg.key = key
    if key == nil then
      self:setLink("auth", "no-key")
    elseif self.link == "auth" then
      self:setLink("unknown") -- a key stored since: the next poll decides
    end
    if done then
      done(key ~= nil)
    end
  end)
end

-- ── status ───────────────────────────────────────────────────────────────────

function Client:pollStatus(done)
  local accepted = noctalia.http(requests.public(self.cfg, "/api/status"), function(res)
    if res ~= nil and res.ok and res.status == 200 then
      self.status = views.status(decode(res.body))
      if self.cfg.key == nil then
        self:setLink("auth", "no-key")
      elseif self.link ~= "auth" then
        self:setLink(self.status.link)
      end
    else
      self:setLink("offline")
    end
    if done then
      done(self.status)
    end
  end)
  if not accepted then
    self:setLink("offline")
    if done then
      done(nil)
    end
  end
end

-- ── API server ───────────────────────────────────────────────────────────────

-- done(ok, json, status)
function Client:api(method, path, bodyTable, done)
  local body = if bodyTable ~= nil then noctalia.json.encode(bodyTable) else nil
  local req, why = requests.api(self.cfg, method, path, body)
  if req == nil then
    self:setLink("auth", why)
    if done then
      done(false, nil, 0)
    end
    return
  end
  local accepted = noctalia.http(req, function(res)
    local status = (res and res.status) or 0
    if status == 401 then
      self:setLink("auth", "rejected")
    elseif status ~= 0 and self.link == "auth" and self.cfg.key ~= nil then
      self:setLink((self.status and self.status.link) or "online") -- the key works again
    end
    if done then
      done(res ~= nil and res.ok and status >= 200 and status < 300, decode(res and res.body), status)
    end
  end)
  if not accepted and done then
    done(false, nil, 0)
  end
end

-- ── the orb's chat ───────────────────────────────────────────────────────────

function Client:loadSession()
  if self.dataDir == nil then
    return
  end
  local saved = decode(noctalia.readFile(self.dataDir .. "/hermes.json"))
  self.chat.sessionId = if type(saved) == "table" then saved.session else nil
  self.chat.model = if type(saved) == "table" and type(saved.model) == "table" then saved.model else nil
end

function Client:saveSession()
  if self.dataDir == nil then
    return
  end
  local path = self.dataDir .. "/hermes.json"
  if self.chat.sessionId == nil and self.chat.model == nil then
    noctalia.removeFile(path)
  else
    noctalia.writeFile(path, noctalia.json.encode({ session = self.chat.sessionId, model = self.chat.model }))
  end
end

function Client:publishChat(force)
  local now = noctalia.nowMs()
  if force or now - self.lastChatPublish >= CHAT_PUBLISH_MS then
    self.lastChatPublish = now
    self.chatDirty = false
    self.publish("orb.hermes.chat", self.chat)
  else
    self.chatDirty = true
  end
end

function Client:onEvent(ev)
  local payload = if ev.data ~= "" then decode(ev.data) else nil
  if type(payload) ~= "table" then
    payload = {}
  end
  local now = noctalia.nowMs()
  local before = self.chat.status
  chat.apply(self.chat, ev.event, payload, now)
  chat.trim(self.chat, MAX_MESSAGES)
  local after = self.chat.status
  if after ~= before and not chat.busy(self.chat) then
    local last = self.chat.messages[#self.chat.messages]
    if last ~= nil then
      self:takeMedia(last)
    end
  end
  if after ~= before then
    if after == "done" then
      self.finishedAt = now
      noctalia.log("orb-hermes: run done")
    elseif after == "failed" or after == "cancelled" then
      self.failedAt = now
      noctalia.log(`orb-hermes: run {after}`)
    end
  end
  self:publishChat(not chat.busy(self.chat) or after ~= before)
end

function Client:openStream(id, input)
  local body = { input = input }
  if self.chat.model ~= nil then
    -- Without the lock Hermes pins a session to the model it last saw and pairs it with the
    -- default provider (gpt-6.1-sol sent to a custom router). The lock is saved with the
    -- session and beats everything else; Hermes has no way to lift it, so "Hermes default"
    -- locks the default's provider and model instead.
    body.model, body.provider = self.chat.model.model, self.chat.model.provider
    body.require_model_lock = true
  end
  local req, why = requests.api(self.cfg, "POST", `/api/sessions/{id}/chat/stream`, noctalia.json.encode(body))
  if req == nil then
    self:setLink("auth", why)
    self.chat.notice = "no-key"
    chat.close(self.chat, false)
    self:publishChat(true)
    return
  end
  req.headers[2] = "Accept: text/event-stream"
  local parser = sse.new()
  self.stream = noctalia.httpStream(req, function(line)
    local ev = parser:push(line)
    if ev ~= nil then
      self:onEvent(ev)
    end
  end, function(result)
    local ev = parser:finish()
    if ev ~= nil then
      self:onEvent(ev)
    end
    self.stream = nil
    local status = (result and result.status) or 0
    if status == 429 then
      -- Hermes is busy: the same turn goes again shortly; the bubble stays
      self.chat.notice = "busy"
      self.retry = { at = noctalia.nowMs() + BUSY_RETRY_MS, id = id, input = input }
      self.chat.status = "sending"
      self:publishChat(true)
      return
    elseif status == 401 then
      self:setLink("auth", "rejected")
      self.chat.notice = "auth"
    elseif status == 404 then
      self.chat.sessionId = nil -- the session is gone; the next message starts a new one
      self:saveSession()
      self.chat.notice = "expired"
    elseif status == 0 or (result and result.ok == false) then
      self.chat.notice = "offline"
    end
    chat.close(self.chat, result ~= nil and result.ok)
    if self.chat.status == "interrupted" then
      self.failedAt = noctalia.nowMs()
    end
    self:publishChat(true)
  end)
  if self.stream == nil then
    self.chat.notice = "offline"
    chat.close(self.chat, false)
    self:publishChat(true)
  end
end

-- Sends a message with whatever is attached. opts.display: what the bubble shows instead of
-- text (a command's expansion goes to Hermes, the command stays in the chat).
function Client:send(text, opts)
  text = if type(text) == "string" then text else ""
  if chat.busy(self.chat) or (string.match(text, "%S") == nil and #self.chat.pending == 0) then
    return
  end
  self.retry = nil
  local files = self.chat.pending
  self.chat.pending = {}
  local names = {}
  for _, f in files do
    table.insert(names, f.name)
  end
  chat.addUser(self.chat, (opts and opts.display) or text, names)
  self:publishChat(true)
  self:prepare(text, files, function(input, problem)
    if input == nil then
      self.chat.notice = problem
      chat.close(self.chat, false)
      self:publishChat(true)
      return
    end
    if self.chat.sessionId ~= nil then
      self:openStream(self.chat.sessionId, input)
      return
    end
    self:api("POST", "/api/sessions", {}, function(ok, json)
      local id = ok and type(json) == "table" and type(json.session) == "table" and json.session.id or nil
      if id == nil then
        self.chat.notice = if self.link == "auth" then "auth" else "offline"
        chat.close(self.chat, false)
        self:publishChat(true)
        return
      end
      self.chat.sessionId = id
      self:saveSession()
      self:openStream(id, input)
    end)
  end)
end

-- ── files ────────────────────────────────────────────────────────────────────

local function script(name)
  return noctalia.pluginDir() .. "/scripts/" .. name
end

-- The file chooser (zenity); what you pick waits in chat.pending for the next message.
function Client:pickFiles(done)
  local accepted = noctalia.runAsync(
    { "zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Send to Hermes" },
    function(r)
      if r ~= nil and r.exitCode == 0 then
        for path in string.gmatch(r.stdout or "", "[^\n]+") do
          self:attach(path)
        end
      end
      self:publishChat(true)
      if done then
        done()
      end
    end
  )
  if not accepted and done then
    done()
  end
end

-- Accepts plain paths, ~/ paths and file:// URIs (what file managers copy).
function Client:attach(path)
  path = string.match(path or "", "^%s*(.-)%s*$")
  if string.sub(path, 1, 7) == "file://" then
    path = string.gsub(string.sub(path, 8), "%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end)
  end
  if string.sub(path, 1, 2) == "~/" then
    local home = string.match(noctalia.pluginDir() or "", "^(/[^/]+/[^/]+)/")
    if home == nil then
      return
    end
    path = home .. string.sub(path, 2)
  end
  local info = noctalia.fileInfo(path)
  if info == nil or info.isDir then
    return
  end
  for _, a in self.chat.pending do
    if a.path == path then
      return
    end
  end
  local content = if info.size <= media.TEXT_MAX and not media.isImage(path) then noctalia.readFile(path) else nil
  table.insert(self.chat.pending, { path = path, name = media.basename(path), size = info.size, kind = media.kind(path, info.size, content) })
end

function Client:detach(i)
  table.remove(self.chat.pending, i)
  self:publishChat(true)
end

-- Attachments -> the request's input: images inline, text files pasted in, anything else
-- copied to the server's ~/orb-inbox first. done(input) or done(nil, notice)
function Client:prepare(text, files, done)
  local images, extra, i = {}, {}, 0
  local function step()
    i += 1
    local f = files[i]
    if f == nil then
      local body = text
      for _, part in extra do
        body = if body ~= "" then body .. "\n\n" .. part else part
      end
      done(media.input(body, images))
      return
    end
    if f.kind == "image" then
      local accepted = noctalia.runAsync({ "base64", "-w0", f.path }, function(r)
        if r ~= nil and r.exitCode == 0 and (r.stdout or "") ~= "" then
          table.insert(images, { mime = media.mime(f.path), b64 = (string.gsub(r.stdout, "%s+", "")) })
          step()
        else
          done(nil, "attach-failed")
        end
      end)
      if not accepted then
        done(nil, "attach-failed")
      end
    elseif f.kind == "text" then
      local content = noctalia.readFile(f.path)
      if content == nil then
        done(nil, "attach-failed")
        return
      end
      table.insert(extra, media.textBlock(f.name, content))
      step()
    else
      local name = os.date("%Y%m%d-%H%M%S") .. "-" .. media.safeName(f.name)
      local accepted = noctalia.runAsync({ "sh", script("upload.sh"), self.cfg.ssh or "", f.path, name }, function(r)
        local remote = r ~= nil and r.exitCode == 0 and string.match(r.stdout or "", "([^\n]+)") or nil
        if remote == nil then
          done(nil, "upload-failed")
          return
        end
        table.insert(extra, `(I put the file {f.name} on the server at {remote} for you.)`)
        step()
      end)
      if not accepted then
        done(nil, "upload-failed")
      end
    end
  end
  step()
end

local function ensureDir(dir, done)
  if noctalia.fileExists(dir) then
    done(true)
    return
  end
  local accepted = noctalia.runAsync({ "mkdir", "-p", dir }, function(r)
    done(r ~= nil and r.exitCode == 0)
  end)
  if not accepted then
    done(false)
  end
end

-- Copies a file from the server. done(localPath | nil)
function Client:fetch(remote, dest, done)
  local accepted = noctalia.runAsync({ "sh", script("fetch.sh"), self.cfg.ssh or "", remote, dest }, function(r)
    done(if r ~= nil and r.exitCode == 0 then string.match(r.stdout or "", "([^\n]+)") or dest else nil)
  end)
  if not accepted then
    done(nil)
  end
end

-- A reply's files: images come to disk to be shown (inline ones are decoded, ones named by a
-- MEDIA: path are fetched); other files wait for Save.
function Client:takeMedia(msg)
  if msg.role ~= "assistant" or msg.media ~= nil or type(msg.text) ~= "string" then
    return
  end
  local text, items = media.extract(msg.text)
  msg.text = text
  msg.media = items
  if #items == 0 or self.dataDir == nil then
    return
  end
  local dir = self.dataDir .. "/media"
  ensureDir(dir, function(ok)
    if not ok then
      return
    end
    for _, item in items do
      if item.kind == "image" then
        local b64 = item.b64
        item.b64 = nil
        item.image = true
        local key = media.hash(string.sub(b64, 1, 4096) .. #b64)
        item.name = `image-{key}.{media.extFor(item.mime)}`
        local path = `{dir}/{item.name}`
        if noctalia.fileExists(path) then
          item.file = path
        else
          noctalia.writeFile(path .. ".b64", b64)
          noctalia.runAsync({ "sh", "-c", 'base64 -d -- "$1" > "$2.part" && mv -f "$2.part" "$2"; rm -f -- "$1"', "sh", path .. ".b64", path }, function(r)
            if r ~= nil and r.exitCode == 0 then
              item.file = path
            end
            self:publishChat(true)
          end)
        end
      elseif item.image then
        local path = `{dir}/{media.hash(item.path)}.{media.ext(item.path)}`
        if noctalia.fileExists(path) then
          item.file = path
        else
          self:fetch(item.path, path, function(got)
            item.file = got
            self:publishChat(true)
          end)
        end
      end
    end
    self:publishChat(true)
  end)
end

local function findMedia(self, m, f)
  local msg = self.chat.messages[tonumber(m) or 0]
  return msg and msg.media and msg.media[tonumber(f) or 0]
end

-- Save: copy a file from the server into ~/Downloads (a fresh name if taken), then Open.
function Client:saveFile(m, f)
  local item = findMedia(self, m, f)
  if item == nil or item.saving or item.saved ~= nil then
    return
  end
  item.saving = true
  self:publishChat(true)
  local dest = media.unique("~/Downloads", media.safeName(item.name), function(p)
    return noctalia.fileExists(p)
  end)
  self:fetch(item.path, dest, function(got)
    item.saving = false
    item.saved = got
    item.failed = got == nil
    if got ~= nil then
      noctalia.log("orb-hermes: saved a file to Downloads")
    end
    self:publishChat(true)
  end)
end

function Client:openFile(m, f)
  local item = findMedia(self, m, f)
  local path = item and (item.saved or item.file)
  if path ~= nil then
    noctalia.runAsync({ "xdg-open", path })
  end
end

-- ── commands ─────────────────────────────────────────────────────────────────

function Client:note(text)
  chat.note(self.chat, text)
  self:publishChat(true)
end

-- /retry: the last thing you said, again. (Not "retry": that field is the busy-resend timer.)
function Client:resend()
  for i = #self.chat.messages, 1, -1 do
    local msg = self.chat.messages[i]
    if msg.role == "user" then
      self:send(msg.text)
      return true
    end
  end
  return false
end

-- /title: names this chat on Hermes. done(ok)
function Client:rename(title, done)
  local id = self.chat.sessionId
  if id == nil then
    done(false)
    return
  end
  self:api("PATCH", `/api/sessions/{id}`, { title = title }, function(ok)
    done(ok)
  end)
end

-- /fork: a copy of this chat to explore another way; the orb carries on in the copy.
function Client:fork(title, done)
  local id = self.chat.sessionId
  if id == nil then
    done(nil)
    return
  end
  self:api("POST", `/api/sessions/{id}/fork`, if title ~= "" then { title = title } else {}, function(ok, json)
    local session = ok and type(json) == "table" and (json.session or json) or nil
    local newId = type(session) == "table" and (session.id or session.session_id) or nil
    if newId ~= nil then
      self:adopt(newId)
    end
    done(newId)
  end)
end

-- /model: done(options) for the list; the pick itself is set with setModel.
function Client:modelOptions(done)
  self:api("GET", "/api/model/options", nil, function(ok, json)
    done(if ok and type(json) == "table" then json else nil)
  end)
end

function Client:setModel(pick)
  self.chat.model = pick
  self:saveSession()
  self:publishChat(true)
end

function Client:stop()
  if self.chat.runId ~= nil then
    self:api("POST", `/v1/runs/{self.chat.runId}/stop`, {}, nil) -- the stream then ends with run.cancelled
  elseif self.stream ~= nil then
    self.stream.stop()
    self.stream = nil
    chat.close(self.chat, false)
    self:publishChat(true)
  end
end

function Client:newChat()
  if self.stream ~= nil then
    self.stream.stop()
    self.stream = nil
  end
  self.retry = nil
  local model = self.chat.model -- the pick carries over to the next chat
  self.chat = chat.new(nil)
  self.chat.model = model
  self:saveSession()
  self:publishChat(true)
end

-- Continue an orb chat picked from the Chats tab.
function Client:adopt(id)
  if self.stream ~= nil then
    self.stream.stop()
    self.stream = nil
  end
  local model = self.chat.model
  self.chat = chat.new(id)
  self.chat.model = model
  self:saveSession()
  self:history()
end

function Client:history()
  local id = self.chat.sessionId
  if id == nil or chat.busy(self.chat) then
    self:publishChat(true)
    return
  end
  self:api("GET", `/api/sessions/{id}/messages?inline_images=false&limit={MAX_MESSAGES}`, nil, function(ok, json, status)
    if ok and not chat.busy(self.chat) then
      self.chat.messages = {}
      for _, row in views.messageRows(json) do
        table.insert(self.chat.messages, { role = row.role, text = row.text, tools = {}, state = "done", thinking = row.thinking })
      end
      chat.trim(self.chat, MAX_MESSAGES)
      for _, msg in self.chat.messages do
        self:takeMedia(msg)
      end
    elseif status == 404 then
      self.chat.sessionId = nil
      self:saveSession()
    end
    self:publishChat(true)
  end)
end

function Client:approve(choice)
  local approval, runId = self.chat.approval, self.chat.runId
  if approval == nil or runId == nil then
    return
  end
  self:api("POST", `/v1/runs/{runId}/approval`, {
    request_id = approval.requestId,
    execution_generation = approval.generation,
    choice = choice,
  }, function(ok)
    if not ok then
      self.chat.notice = "approval-failed"
      self:publishChat(true)
    end
  end)
end

-- ── past chats ───────────────────────────────────────────────────────────────

-- The orb's own chats (Hermes lets the API continue only the sessions it created).
function Client:loadChats(done)
  self:api("GET", "/api/sessions?source=api_server&limit=30", nil, function(ok, json)
    done(if ok then views.chatRows(json, os.time()) else nil)
  end)
end

-- Delete a chat for good: Hermes drops the session and its transcript. Deleting the open
-- chat starts a fresh one. done(ok, status): 409 while Hermes is still replying in it.
function Client:deleteChat(id, done)
  self:api("DELETE", `/api/sessions/{id}`, nil, function(ok, json, status)
    ok = ok and not (type(json) == "table" and json.deleted == false)
    if ok and id == self.chat.sessionId then
      self:newChat()
    end
    done(ok, status)
  end)
end

-- ── housekeeping ─────────────────────────────────────────────────────────────

-- Called from the service's update(): flushes a throttled chat publish, retries after a 429.
function Client:tick(now)
  if self.chatDirty and now - self.lastChatPublish >= CHAT_PUBLISH_MS then
    self:publishChat(true)
  end
  if self.retry ~= nil and now >= self.retry.at then
    local retry = self.retry
    self.retry = nil
    self.chat.notice = nil
    self:openStream(retry.id, retry.input)
  end
end

function Client:shutdown()
  if self.stream ~= nil then
    self.stream.stop()
    self.stream = nil
  end
end

return M
