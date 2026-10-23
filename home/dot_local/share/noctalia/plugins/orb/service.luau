--!nonstrict
-- The orb's brain. Owns where the orb is (orb.state) and shows / hides the
-- roamer layer. The orb never wanders off by itself: it leaves the bar when
-- asked and stays where it is put.
--
--   home -> away       right-click in the bar, a click (card), or IPC "out" / "card"
--   away -> returning  click on the puddle, the card's "Call home", or IPC "home"
--   returning -> home  the roamer reports it dove back in (orb.landed)
--
-- Other entries talk to it through noctalia.state:
--   orb.cmd     "<out|card|home|toggle>:<ms>"  from the widget and the roamer
--   orb.landed  ms                              from the roamer
--   orb.output  connector                       from the widget: which bar it lives on
-- and it publishes orb.state, orb.geo (screen, home point, intent) and orb.open
-- (bring the card out of an orb that is already out).
--
-- It also holds the line to Hermes (lib/hermes/client.luau) and publishes what the
-- card and the bar show: orb.hermes.link, .activity, .chat, .lists, .nudge.
-- The card sends orb.hermes.cmd = "<verb>:<ms>:<json args>".
--
--   noctalia msg plugin shadow/orb:service all out|card|home|toggle|reset
--   noctalia msg plugin shadow/orb:service all hermes-status|hermes-send <text>|hermes-attach <path>|hermes-approve <choice>|hermes-stop|hermes-new

local motion = require("./lib/motion.luau")
local reset = require("./lib/reset.luau")
local client = require("./lib/hermes/client.luau")
local activity = require("./lib/hermes/activity.luau")
local commands = require("./lib/hermes/commands.luau")
local views = require("./lib/hermes/views.luau")

local WIDGET_TYPE = "shadow/orb:orb"
local RETURN_TIMEOUT_MS = 10000

local state = "home"
local returningSince = 0

local function now()
  return noctalia.nowMs()
end

local function setState(s)
  state = s
  noctalia.state.set("orb.state", s)
end

-- ── where home is ────────────────────────────────────────────────────────────

-- Which bar holds the widget, and where in it. Falls back to the first bar.
local function findHome()
  local order = noctalia.getSetting("bar.order") or { "default" }
  local widgets = noctalia.getSetting("widget") or {}
  local function isOrb(name)
    if name == WIDGET_TYPE then
      return true
    end
    local w = widgets[name]
    return type(w) == "table" and w.type == WIDGET_TYPE
  end
  for _, bar in order do
    for _, section in { "start", "center", "end" } do
      local names = noctalia.getSetting(`bar.{bar}.{section}`)
      if type(names) == "table" then
        for i, name in names do
          if isOrb(name) then
            return bar, section, i, #names
          end
        end
      end
    end
  end
  return order[1], nil, 1, 1
end

local function computeGeo()
  local outputs = noctalia.outputs()
  local wanted = noctalia.state.get("orb.output") or noctalia.focusedOutputName()
  local out = outputs[1]
  for _, o in outputs do
    if o.name == wanted then
      out = o
    end
  end
  if out == nil then
    return nil
  end

  local bar, section, index, count = findHome()
  local edge = noctalia.getSetting(`bar.{bar}.position`) or "top"
  local thickness = noctalia.getSetting(`bar.{bar}.thickness`) or 40
  local vertical = edge == "left" or edge == "right"
  local length = if vertical then out.height else out.width
  local along = motion.homeAlong(section, index, count, length)
  local pct = noctalia.getConfig("home_position") or 0
  if pct > 0 then
    along = length * pct / 100
  end
  local hx, hy = motion.homePoint(edge, thickness, along, out.width, out.height)
  return {
    output = out.name,
    w = out.width,
    h = out.height,
    edge = edge,
    thickness = thickness,
    homeX = hx,
    homeY = hy,
  }
end

-- ── moves ────────────────────────────────────────────────────────────────────

-- intent: "out" to come out and stay, "card" to come out just to show its card.
local function goOut(intent)
  if state ~= "home" then
    return
  end
  local geo = computeGeo()
  if geo == nil then
    noctalia.log("orb: no output to come out on")
    return
  end
  geo.intent = intent
  noctalia.state.set("orb.geo", geo)
  noctalia.state.set("orb.spot", "") -- a fresh trip starts at the bar
  -- Place the surface at the home point before it maps, so it never flashes at 0,0.
  -- Out for the card, it maps taking keys on demand: niri hands a newly mapped on-demand
  -- layer the keyboard, so you can type as soon as the card is up.
  noctalia.layer.configure("roamer", {
    output = geo.output,
    margins = { top = math.max(0, math.floor(geo.homeY - 32)), left = math.max(0, math.floor(geo.homeX - 32)) },
    keyboard = if intent == "card" then "on_demand" else "none",
  })
  setState("away")
  noctalia.layer.show("roamer")
end

local function goHome()
  if state ~= "away" then
    return
  end
  returningSince = now()
  setState("returning")
  -- In case a reload left no roamer: a fresh one sees "returning" and heads home.
  noctalia.layer.show("roamer")
end

local function landed()
  if state == "home" then
    return
  end
  noctalia.layer.hide("roamer")
  noctalia.state.set("orb.spot", "")
  setState("home")
end

local function command(c)
  if c == "out" then
    goOut("out")
  elseif c == "card" then
    if state == "home" then
      goOut("card")
    elseif state == "away" then
      noctalia.state.set("orb.open", now())
    end
  elseif c == "home" then
    goHome()
  elseif c == "toggle" then
    if state == "home" then
      goOut("out")
    else
      goHome()
    end
  end
end

noctalia.state.watch("orb.cmd", function(value)
  if type(value) == "string" then
    command(string.match(value, "^(%a+)"))
  end
end)

noctalia.state.watch("orb.landed", function()
  landed()
end)

-- ── Hermes ───────────────────────────────────────────────────────────────────

local LIST_REFRESH_MS = 60000 -- the Chats list, while it shows
local SECRETS_MS = 5000

local function hermesCfg()
  return {
    url = noctalia.getConfig("hermes_url") or "http://server.tailf72995.ts.net",
    apiPort = noctalia.getConfig("hermes_api_port") or 8642,
    dashPort = noctalia.getConfig("hermes_dashboard_port") or 9119, -- the public /api/status
    ssh = noctalia.getConfig("hermes_ssh") or "", -- user@host for files that are not images
  }
end

local hermes = client.new(hermesCfg(), function(key, value)
  noctalia.state.set(key, value)
end)

local savedTab = noctalia.state.get("orb.hermes.tab")
local h = {
  tab = if savedTab == "chats" then "chats" else "chat",
  cardOpen = false,
  nextStatusAt = 0,
  chatsAt = 0, -- last refresh of the Chats list
  modelsAt = nil, -- last fetch of the model picker's list
  picker = nil, -- that list (views.modelSections)
  secretsAt = 0, -- next keyring look while the card waits for a key
  lists = { problem = {} },
  unread = false,
  finishedSeen = nil,
  published = { pet = nil, agents = nil, sessions = nil, nudge = "unset" },
}

local function publishLists()
  h.lists.at = now()
  noctalia.state.set("orb.hermes.lists", h.lists)
end

local function refreshTab(tab)
  if tab == "chats" then
    h.chatsAt = now()
    hermes:loadChats(function(rows)
      h.lists.chats = rows
      h.lists.deleteFailed = nil
      h.lists.problem.chats = if rows == nil then hermes.link else nil
      publishLists()
    end)
  else
    hermes:history()
  end
end

-- The model picker's list (orb.hermes.models): fetched when the card opens, at most every
-- few minutes; a failed fetch is retried on the next open.
local MODELS_MS = 5 * 60 * 1000

local function loadModels(force)
  if not force and h.modelsAt ~= nil and now() - h.modelsAt < MODELS_MS then
    return
  end
  h.modelsAt = now()
  hermes:modelOptions(function(options)
    if options == nil then
      h.modelsAt = nil
      noctalia.state.set("orb.hermes.models", { status = "failed" })
      return
    end
    local picker = views.modelSections(options)
    picker.status = "ready"
    h.picker = picker
    noctalia.state.set("orb.hermes.models", picker)
  end)
end

-- The file chooser is a normal window, under the card (a top layer): the card steps aside
-- while it is open (orb.hermes.picker) and comes back after.
local function pickFiles()
  noctalia.state.set("orb.hermes.picker", { open = true, at = now() })
  hermes:pickFiles(function()
    noctalia.state.set("orb.hermes.picker", { open = false, at = now() })
  end)
end

local function helpText()
  local lines = { noctalia.tr("hermes.cmd.heading") }
  for _, entry in commands.LIST do
    local usage = "/" .. entry.name .. (if entry.args ~= "" then " " .. entry.args else "")
    table.insert(lines, `- \`{usage}\` {noctalia.tr("hermes.cmd." .. entry.name)}`)
  end
  table.insert(lines, noctalia.tr("hermes.cmd.footer"))
  return table.concat(lines, "\n")
end

-- A /command typed in the chat. Hermes' API has no slash commands, so they run here.
local function runCommand(cmd, text)
  if cmd.unknown ~= nil then
    hermes:note(noctalia.tr("hermes.cmd.unknown", { name = cmd.unknown }))
    return
  end
  local name, args = cmd.name, cmd.args
  if name == "help" then
    hermes:note(helpText())
  elseif name == "new" then
    hermes:newChat()
  elseif name == "chats" then
    h.tab = "chats"
    noctalia.state.set("orb.hermes.tab", "chats")
    refreshTab("chats")
  elseif name == "attach" then
    pickFiles()
  elseif name == "stop" then
    hermes:stop()
  elseif name == "retry" then
    if not hermes:resend() then
      hermes:note(noctalia.tr("hermes.cmd.nothing_to_retry"))
    end
  elseif name == "approve" or name == "deny" then
    if hermes.chat.approval == nil then
      hermes:note(noctalia.tr("hermes.cmd.no_approval"))
    else
      hermes:approve(if name == "deny" then "deny" elseif args ~= "" then args else "once")
    end
  elseif name == "title" then
    if args == "" then
      hermes:note(noctalia.tr("hermes.cmd.title_usage"))
      return
    end
    hermes:rename(args, function(ok)
      hermes:note(noctalia.tr(if ok then "hermes.cmd.renamed" else "hermes.cmd.no_chat", { title = args }))
    end)
  elseif name == "fork" then
    hermes:fork(args, function(id)
      hermes:note(noctalia.tr(if id ~= nil then "hermes.cmd.forked" else "hermes.cmd.no_chat"))
    end)
  elseif name == "skill" then
    local prompt = commands.skillPrompt(args)
    if prompt == nil then
      hermes:note(noctalia.tr("hermes.cmd.skill_usage"))
    else
      hermes:send(prompt, { display = text })
    end
  elseif name == "model" then
    local q = string.lower(args)
    if q == "default" or q == "reset" then
      hermes:modelOptions(function(options)
        local default = views.modelSections(options).default
        if default == nil then
          hermes:note(noctalia.tr("hermes.cmd.model_failed"))
        else
          hermes:setModel({ provider = default.provider, model = default.model, default = true })
          hermes:note(noctalia.tr("hermes.cmd.model_default"))
        end
      end)
      return
    end
    if args == "" then
      -- the picker in the card
      loadModels(true)
      noctalia.state.set("orb.hermes.pickmodel", now())
      return
    end
    hermes:modelOptions(function(options)
      if options == nil then
        hermes:note(noctalia.tr("hermes.cmd.model_failed"))
      else
        local pick = commands.resolveModel(options, args)
        if pick == nil then
          hermes:note(noctalia.tr("hermes.cmd.model_unknown", { model = args }))
        else
          hermes:setModel(pick)
          hermes:note(noctalia.tr("hermes.cmd.model_set", { model = `{pick.provider} · {pick.model}` }))
        end
      end
    end)
  end
end

-- What you type: a /command runs here, anything else goes to Hermes.
local function sendOrRun(text)
  local cmd = commands.parse(text)
  if cmd ~= nil then
    runCommand(cmd, text)
  else
    hermes:send(commands.unescape(text))
  end
end

local function hermesCommand(value)
  if type(value) ~= "string" then
    return
  end
  local verb, rest = string.match(value, "^([%a%-]+):%d+:?(.*)$")
  if verb == nil then
    return
  end
  local args = if rest ~= "" then noctalia.json.decode(rest) else nil
  if type(args) ~= "table" then
    args = {}
  end
  if verb == "send" then
    sendOrRun(args.text)
  elseif verb == "attach" then
    pickFiles()
  elseif verb == "detach" then
    hermes:detach(tonumber(args.i) or 0)
  elseif verb == "save-file" then
    hermes:saveFile(args.m, args.f)
  elseif verb == "open-file" then
    hermes:openFile(args.m, args.f)
  elseif verb == "stop" then
    hermes:stop()
  elseif verb == "new" then
    hermes:newChat()
  elseif verb == "approve" then
    hermes:approve(args.choice)
  elseif verb == "open" then
    h.cardOpen = args.open == true
    h.nextStatusAt = 0
    if h.cardOpen and (hermes.cfg.key == nil or hermes.link == "auth") then
      -- a key stored with secret-tool since the last look counts from the next open
      hermes:loadSecrets(function()
        h.nextStatusAt = 0
        refreshTab(h.tab)
      end)
    end
    if h.cardOpen then
      if h.tab == "chat" then
        h.unread = false
      end
      refreshTab(h.tab)
      if hermes.cfg.key ~= nil then
        loadModels(false)
      end
    end
  elseif verb == "tab" then
    h.tab = if args.id == "chats" then "chats" else "chat"
    noctalia.state.set("orb.hermes.tab", h.tab)
    if h.tab == "chat" then
      h.unread = false
    end
    refreshTab(h.tab)
  elseif verb == "models" then
    loadModels(true)
  elseif verb == "set-model" then
    -- a provider and a model from the picker; default = true for "Hermes default"
    if type(args.provider) == "string" and type(args.model) == "string" then
      hermes:setModel({ provider = args.provider, model = args.model, default = args.default == true or nil })
    end
  elseif verb == "refresh" then
    h.nextStatusAt = 0 -- a retry also asks whether Hermes is back
    refreshTab(args.id or h.tab)
  elseif verb == "delete-chat" then
    local id = args.id
    if type(id) ~= "string" or h.lists.deleting ~= nil then
      return
    end
    h.lists.deleting, h.lists.deleteFailed = id, nil
    publishLists()
    hermes:deleteChat(id, function(ok, status)
      h.lists.deleting = nil
      if ok then
        for i, row in h.lists.chats or {} do
          if row.id == id then
            table.remove(h.lists.chats, i)
            break
          end
        end
      else
        h.lists.deleteFailed = if status == 409 then "busy" else "failed"
      end
      publishLists()
    end)
  elseif verb == "adopt" then
    hermes:adopt(args.id)
    h.tab = "chat"
    h.unread = false
    noctalia.state.set("orb.hermes.tab", "chat")
  end
end

noctalia.state.watch("orb.hermes.cmd", hermesCommand)

local function publishActivity(t)
  local st = hermes.status
  local busyElsewhere = st ~= nil and (st.busy or st.agents > 0)
  local pet = activity.pet({
    chatStatus = hermes.chat.status,
    busyElsewhere = busyElsewhere,
    finishedAt = hermes.finishedAt,
    failedAt = hermes.failedAt,
    nowMs = t,
  })
  local agents, sessions = (st and st.agents) or 0, (st and st.sessions) or 0
  local p = h.published
  if pet ~= p.pet or agents ~= p.agents or sessions ~= p.sessions then
    p.pet, p.agents, p.sessions = pet, agents, sessions
    noctalia.state.set("orb.hermes.activity", { pet = pet, agents = agents, sessions = sessions })
  end

  -- a reply that finished while you were not looking at the chat
  if hermes.finishedAt ~= h.finishedSeen then
    h.finishedSeen = hermes.finishedAt
    if hermes.finishedAt ~= nil and not (h.cardOpen and h.tab == "chat") then
      h.unread = true
    end
  end
  local nudge = if hermes.chat.status == "waiting" then "approval" elseif h.unread then "unread" else nil
  if nudge ~= p.nudge then
    p.nudge = nudge
    noctalia.state.set("orb.hermes.nudge", { kind = nudge })
  end
end

local function hermesTick(t)
  -- The card is locked to "Connect Hermes first": look in the keyring every few seconds, so
  -- it unlocks on its own once the key is stored.
  if h.cardOpen and hermes.cfg.key == nil and t >= h.secretsAt then
    h.secretsAt = t + SECRETS_MS
    hermes:loadSecrets(function(found)
      if found then
        h.nextStatusAt = 0
        refreshTab(h.tab)
      end
    end)
  end
  if t >= h.nextStatusAt then
    h.nextStatusAt = t + activity.pollDelay(hermes.link, h.cardOpen)
    hermes:pollStatus()
  end
  if h.cardOpen and h.tab == "chats" and t - h.chatsAt >= LIST_REFRESH_MS then
    refreshTab("chats")
  end
  hermes:tick(t)
  publishActivity(t)
end

function update()
  local t = now()
  if state == "returning" and t - returningSince > RETURN_TIMEOUT_MS then
    noctalia.log("orb: roamer never reported landing; bringing it home")
    landed()
  end
  hermesTick(t)
  noctalia.setUpdateInterval(if hermes.chatDirty or hermes.stream ~= nil then 100 else 250)
end

-- ── settings reset ──────────────────────────────────────────────────────────
-- The "Reset everything to defaults" switch. Plugins cannot write their
-- settings, so this drops the plugin's table from Noctalia's settings.toml
-- (which also turns the switch back off) and reloads the plugin, since an
-- enabled plugin keeps the values it was loaded with.

local function resetSettings()
  local dataDir = noctalia.pluginDataDir()
  if dataDir == nil then
    noctalia.log("orb: no state directory; cannot reset settings")
    return
  end
  -- The data dir is <state>/plugins/data/<id>; settings.toml lives in <state>.
  local path = (string.gsub(dataDir, "/plugins/data/.*$", "")) .. "/settings.toml"
  local text = noctalia.readFile(path)
  if text == nil then
    noctalia.log(`orb: cannot read {path}; nothing reset`)
    return
  end
  local cleaned, removed = reset.dropPluginSettings(text, "shadow/orb")
  if removed then
    local tmp = path .. ".orb-reset"
    if not (noctalia.writeFile(tmp, cleaned) and noctalia.renameFile(tmp, path)) then
      noctalia.log(`orb: could not write {path}; nothing reset`)
      return
    end
  end
  noctalia.log("orb: settings reset to defaults; reloading")
  -- Detached, so it outlives this service when the plugin is disabled.
  noctalia.runAsync(
    "noctalia msg config-reload >/dev/null; sleep 0.5; "
      .. "noctalia msg plugins disable shadow/orb >/dev/null; sleep 1; "
      .. "noctalia msg plugins enable shadow/orb >/dev/null"
  )
end

function onIpc(event, payload)
  if event == "reset" then
    resetSettings()
  elseif event == "hermes-status" then
    h.nextStatusAt = 0
    noctalia.log(`orb-hermes: link {hermes.link}, key {if hermes.cfg.key then "set" else "missing"}`)
  elseif event == "hermes-send" then
    sendOrRun(payload)
  elseif event == "hermes-attach" then
    -- attach a file from a terminal: hermes-attach ~/report.pdf (sent with the next message)
    hermes:attach(payload or "")
    hermes:publishChat(true)
  elseif event == "hermes-approve" then
    hermes:approve(payload or "deny")
  elseif event == "hermes-stop" then
    hermes:stop()
  elseif event == "hermes-new" then
    hermes:newChat()
  elseif event == "hermes-dev" then
    -- Point the orb at a test server, in memory only (a plugin reload undoes it):
    -- hermes-dev '{"url":"http://127.0.0.1","apiPort":18642,"dashPort":18642,"key":"k"}'
    local dev = noctalia.json.decode(payload or "")
    if type(dev) == "table" then
      hermes.cfg = { url = dev.url, apiPort = dev.apiPort, dashPort = dev.dashPort, key = dev.key, ssh = dev.ssh or hermes.cfg.ssh }
      hermes.link = "unknown"
      h.nextStatusAt = 0
      noctalia.log("orb-hermes: dev target " .. tostring(dev.url))
    end
  else
    command(event)
  end
end

function onConfigChanged()
  -- home_position is read when the orb comes out; the reset switch and the Hermes
  -- connection act here
  if noctalia.getConfig("reset") == true then
    resetSettings()
    return
  end
  local cfg = hermesCfg()
  cfg.key = hermes.cfg.key
  hermes.cfg = cfg
  h.nextStatusAt = 0
end

function onExit(_signal, _reason)
  hermes:shutdown()
end

noctalia.layer.hide("roamer")
setState("home")
hermes:publishChat(true)
publishLists()
hermes:loadSecrets(function()
  h.nextStatusAt = 0
end)
noctalia.setUpdateInterval(250)
