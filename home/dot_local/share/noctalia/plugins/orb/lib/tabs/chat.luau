--!nonstrict
-- Chat tab: the orb's ongoing conversation with Hermes.
--
--   render(m) with m = { chat, link, width, inputKey, inputSeed, draft,
--                        models, modelPicker, modelSections, modelShowAll, openThinking,
--                        cb = { send, sendDraft, draft, fill, stop, new, approve, cmd,
--                               models, pickModel, toggleProvider, showAllModels,
--                               toggleThinking } }

local common = require("./common.luau")
local commands = require("../hermes/commands.luau")
local views = require("../hermes/views.luau")

local M = {}
local C = common.COLORS
local tr = common.tr

local STATE_TEXT = {
  partial = "hermes.chat.partial",
  failed = "hermes.chat.failed",
  cancelled = "hermes.chat.stopped",
  interrupted = "hermes.chat.interrupted",
}

local CHOICE_TEXT = {
  once = "hermes.approve.once",
  session = "hermes.approve.session",
  always = "hermes.approve.always",
  deny = "hermes.approve.deny",
}

local SUGGESTIONS = { "hermes.suggest.today", "hermes.suggest.chats", "hermes.suggest.cron" }

local KIND_GLYPH = { image = "photo", text = "file-text", file = "file-upload" }

local function toolLine(key, t)
  local glyph = if t.state == "running" then "loader-2" elseif t.state == "error" then "alert-triangle" else "check"
  local text = t.name .. (if t.preview ~= nil and t.preview ~= "" then " · " .. t.preview else "")
  return ui.row({ key = key }, {
    ui.row({ key = key .. "-p", fill = C.soft, radius = 8, paddingH = 8, paddingV = 4, gap = 6, align = "center" }, {
      ui.glyph({ key = key .. "-g", name = glyph, size = 12, color = if t.state == "error" then C.bad else C.muted }),
      common.muted(key .. "-t", text, { maxLines = 1 }),
    }),
  })
end

local function busyText(status)
  if status == "tool" then
    return tr("hermes.chat.working")
  elseif status == "waiting" then
    return tr("hermes.chat.waiting")
  end
  return tr("hermes.chat.thinking")
end

local function fileChip(key, glyph, name, trailing)
  local children = {
    ui.glyph({ key = key .. "-g", name = glyph, size = 13, color = C.muted }),
    common.label(key .. "-t", name, { fontSize = 12, maxLines = 1 }),
  }
  for _, node in trailing or {} do
    table.insert(children, node)
  end
  return ui.row({ key = key, fill = C.soft, radius = 8, paddingH = 8, paddingV = 5, gap = 6, align = "center" }, children)
end

-- A user turn: the bubble, then what was attached.
local function userTurn(key, msg, width)
  local column = { common.userBubble(key, msg.text, width) }
  for j, name in msg.files or {} do
    table.insert(column, ui.row({ key = key .. "-fr-" .. j, justify = "end" }, {
      fileChip(key .. "-f-" .. j, "paperclip", name),
    }))
  end
  if #column == 1 then
    return column[1]
  end
  return ui.column({ key = key .. "-turn", gap = 4 }, column)
end

-- A reply's files: images shown (click opens them), other files with Save, then Open.
local function mediaNodes(key, i, msg, width, cb)
  local nodes = {}
  for j, item in msg.media or {} do
    local k = `{key}-m-{j}`
    local open = function()
      cb.cmd("open-file", { m = i, f = j })
    end
    if item.image and item.file ~= nil then
      table.insert(nodes, ui.image({ key = k, path = item.file, width = math.floor(width * 0.75), height = 200, fit = "cover", radius = 10, onClick = open }))
    elseif item.image then
      table.insert(nodes, ui.row({ key = k .. "-row" }, { fileChip(k, "photo", item.name, { common.muted(k .. "-l", tr("hermes.files.loading")) }) }))
    else
      local action
      if item.saved ~= nil then
        action = common.pill(k .. "-open", "external-link", tr("hermes.files.open"), open, { fill = C.accentSoft, color = C.accent })
      elseif item.saving then
        action = common.pill(k .. "-saving", "loader-2", tr("hermes.files.saving"), nil)
      else
        action = common.pill(k .. "-save", "download", tr(if item.failed then "hermes.files.retry" else "hermes.files.save"), function()
          cb.cmd("save-file", { m = i, f = j })
        end, if item.failed then { color = C.bad } else nil)
      end
      table.insert(nodes, ui.row({ key = k .. "-row" }, { fileChip(k, "file", item.name, { action }) }))
    end
  end
  return nodes
end

-- What fills an empty chat: a hint while offline, else a welcome with a few things to ask.
-- (Without a key the card shows the setup screen instead of tabs.)
local function emptyState(m, cb)
  if m.link == "offline" then
    return common.state("chat-offline", "wifi-off", tr("hermes.offline.title"), tr("hermes.offline.text"), {
      common.pill("offline-retry", "refresh", tr("hermes.retry"), function()
        cb.cmd("refresh")
      end),
    }, C.bad)
  end
  local chips = {}
  for i, key in SUGGESTIONS do
    local text = tr(key)
    table.insert(chips, common.pill("suggest-" .. i, "sparkles", text, function()
      cb.send(text)
    end, { weight = "normal" }))
  end
  return common.state("chat-empty", "message-circle", tr("hermes.chat.empty_title"), tr("hermes.chat.empty"), {
    ui.column({ key = "suggest", gap = 6, align = "center", paddingV = 6 }, chips),
  })
end

local function approvalCard(approval, cb)
  local buttons = {}
  for i, choice in approval.choices or {} do
    local props
    if choice == "deny" then
      props = { color = C.bad }
    elseif i == 1 then
      props = { fill = C.accent, color = C.onAccent }
    end
    table.insert(buttons, common.pill("approve-" .. choice, nil, tr(CHOICE_TEXT[choice] or choice), function()
      cb.approve(choice)
    end, props))
  end
  local command = if approval.command ~= nil and approval.command ~= "" then approval.command else approval.description
  return ui.column({ key = "approval", fill = C.tile, radius = 12, padding = 12, gap = 8, border = "primary/0.5", borderWidth = 1 }, {
    ui.row({ key = "approval-h", gap = 8, align = "center" }, {
      ui.glyph({ key = "approval-g", name = "shield-question", size = 16, color = C.accent }),
      common.label("approval-t", tr("hermes.approve.title"), { fontSize = 13, fontWeight = "semibold" }),
    }),
    ui.column({ key = "approval-c", fill = C.soft, radius = 8, paddingH = 10, paddingV = 8 }, {
      common.label("approval-ct", command or "", { fontSize = 12, maxLines = 5 }),
    }),
    ui.row({ key = "approval-b", gap = 6 }, buttons),
  })
end

-- "Show thinking" / "Hide thinking" above a reply; tapping it shows or hides the model's
-- reasoning in a box under it.
local function thinkingNodes(key, text, open, width, onToggle)
  local nodes = {
    ui.row({ key = key, gap = 6, align = "center", onClick = onToggle }, {
      ui.glyph({ key = key .. "-g", name = "bulb", size = 13, color = C.muted }),
      common.muted(key .. "-t", tr(if open then "hermes.chat.thinking_hide" else "hermes.chat.thinking_show"), { fontSize = 12 }),
      ui.glyph({ key = key .. "-c", name = if open then "chevron-up" else "chevron-down", size = 12, color = C.muted }),
    }),
  }
  if open then
    table.insert(nodes, ui.column({ key = key .. "-box", fill = C.soft, radius = 10, paddingH = 10, paddingV = 8 }, {
      common.muted(key .. "-body", text or tr("hermes.chat.thinking_none"), { fontSize = 12, maxWidth = width - 20 }),
    }))
  end
  return nodes
end

-- A line in the history that is not a turn: a model switch, or a turn that failed.
local function eventLine(key, msg)
  if msg.kind == "model" then
    return ui.row({ key = key, justify = "center", gap = 6, align = "center" }, {
      ui.glyph({ key = key .. "-g", name = "cpu", size = 12, color = C.muted }),
      common.muted(key .. "-t", tr("hermes.chat.switched", { model = msg.text }), { maxLines = 1 }),
    })
  end
  return ui.row({ key = key, fill = C.soft, radius = 10, paddingH = 10, paddingV = 7, gap = 8, align = "center" }, {
    ui.glyph({ key = key .. "-g", name = "alert-triangle", size = 13, color = C.muted }),
    common.muted(key .. "-t", msg.text, { flexGrow = 1, maxLines = 3 }),
  })
end

-- The model in use: this chat's pick, else Hermes' default.
local function modelName(m)
  local pick = (m.chat or {}).model
  if pick ~= nil then
    return views.shortModel(pick.model)
  end
  local default = (m.models or {}).default
  if default ~= nil then
    return views.shortModel(default.model)
  end
  return tr("hermes.model.pick")
end

-- The model list, in place of the messages: Hermes' default, then the providers you set up
-- (the one in use open), the rest behind "Show all". Tapping a model sets it for this chat.
local function modelPicker(m, cb)
  local models = m.models or {}
  local pick = (m.chat or {}).model
  local rows = {}

  local function option(key, title, subtitle, selected, onClick)
    local text = { common.label(key .. "-t", title, {
      fontSize = 12,
      fontWeight = if selected then "semibold" else "normal",
      color = if selected then C.accent else C.ink,
      maxLines = 1,
    }) }
    if subtitle ~= nil then
      table.insert(text, common.muted(key .. "-s", subtitle, { maxLines = 1 }))
    end
    local children = { ui.column({ key = key .. "-c", gap = 1, flexGrow = 1 }, text) }
    if selected then
      table.insert(children, ui.glyph({ key = key .. "-ok", name = "check", size = 14, color = C.accent }))
    end
    return ui.row({
      key = key,
      fill = if selected then C.accentSoft else C.clear,
      radius = 10,
      paddingH = 10,
      paddingV = 7,
      gap = 8,
      align = "center",
      onClick = onClick,
    }, children)
  end

  local default = models.default
  table.insert(rows, option("mp-default", tr("hermes.model.default"),
    if default ~= nil then `{default.provider} · {views.shortModel(default.model)}` else nil,
    pick == nil or pick.default == true, function()
      cb.pickModel(nil)
    end))

  local active = if pick ~= nil then pick.provider elseif default ~= nil then default.provider else nil
  local shown, hidden = table.clone(models.sections or {}), 0
  for _, section in models.more or {} do
    if m.modelShowAll or section.slug == active then
      table.insert(shown, section)
    else
      hidden += 1
    end
  end
  for _, section in shown do
    local slug = section.slug
    local open = (m.modelSections or {})[slug]
    if open == nil then
      open = slug == active
    end
    local key = "mp-" .. slug
    table.insert(rows, ui.row({
      key = key,
      radius = 10,
      paddingH = 10,
      paddingV = 8,
      gap = 8,
      align = "center",
      onClick = function()
        cb.toggleProvider(slug, open)
      end,
    }, {
      ui.glyph({ key = key .. "-g", name = if open then "chevron-down" else "chevron-right", size = 14, color = C.muted }),
      common.label(key .. "-t", slug, { fontSize = 12, fontWeight = "semibold", flexGrow = 1, maxLines = 1 }),
      common.muted(key .. "-n", tostring(#section.models)),
    }))
    if open then
      for j, id in section.models do
        local picked = pick ~= nil and not pick.default and pick.provider == slug and pick.model == id
        table.insert(rows, option(`{key}-{j}`, id, nil, picked, function()
          cb.pickModel({ provider = slug, model = id })
        end))
      end
    end
  end

  if hidden > 0 then
    table.insert(rows, ui.row({ key = "mp-more", paddingH = 10, paddingV = 8, gap = 8, align = "center", onClick = cb.showAllModels }, {
      ui.glyph({ key = "mp-more-g", name = "plus", size = 14, color = C.muted }),
      common.muted("mp-more-t", tr("hermes.model.more", { count = tostring(hidden) }), { fontSize = 12 }),
    }))
  end

  local body
  if models.status == "ready" then
    body = common.scroll("mp-scroll", rows, { gap = 2 })
  elseif models.status == "failed" then
    body = common.state("mp-failed", "alert-triangle", tr("hermes.model.failed"), nil, {
      common.pill("mp-retry", "refresh", tr("hermes.retry"), function()
        cb.cmd("models")
      end),
    }, C.bad)
  else
    body = common.state("mp-loading", "loader-2", tr("hermes.model.loading"), nil, nil)
  end
  return ui.column({ key = "model-picker", fill = C.tile, radius = 14, padding = 6, gap = 4, flexGrow = 1 }, {
    ui.row({ key = "mp-head", paddingH = 8, paddingV = 4, gap = 6, align = "center" }, {
      common.label("mp-title", tr("hermes.model.title"), { fontSize = 13, fontWeight = "semibold", flexGrow = 1 }),
      common.icon("mp-close", "x", cb.models, { size = 26, fill = C.clear, color = C.muted }),
    }),
    body,
  })
end

-- While the input holds "/word": the commands it could be. Tapping one fills it in.
local function suggestions(draft, cb)
  local hits = commands.suggest(draft)
  if #hits == 0 then
    return nil
  end
  local rows = {}
  for _, entry in hits do
    local usage = "/" .. entry.name .. (if entry.args ~= "" then " " .. entry.args else "")
    table.insert(rows, ui.row({
      key = "sg-" .. entry.name,
      radius = 8,
      paddingH = 8,
      paddingV = 5,
      gap = 8,
      align = "center",
      onClick = function()
        cb.fill("/" .. entry.name .. " ")
      end,
    }, {
      common.label("sg-" .. entry.name .. "-u", usage, { fontSize = 12, fontWeight = "semibold", color = C.accent }),
      common.muted("sg-" .. entry.name .. "-d", tr("hermes.cmd." .. entry.name), { maxLines = 1, flexGrow = 1 }),
    }))
  end
  return ui.column({ key = "suggestions", fill = C.tile, radius = 12, padding = 4, gap = 0 }, rows)
end

function M.render(m)
  local chat, width, cb = m.chat or {}, m.width, m.cb
  local busy = chat.status == "sending" or chat.status == "thinking" or chat.status == "tool" or chat.status == "waiting"
  local items = {}
  local column = {}

  if m.modelPicker then
    table.insert(column, modelPicker(m, cb))
  elseif #(chat.messages or {}) == 0 and not busy then
    table.insert(column, emptyState(m, cb))
  else
    for i, msg in chat.messages or {} do
      local key = "msg-" .. i
      if msg.role == "user" then
        table.insert(items, userTurn(key, msg, width))
      elseif msg.role == "event" then
        table.insert(items, eventLine(key, msg))
      elseif msg.role == "note" then
        table.insert(items, ui.column({ key = key, fill = C.soft, radius = 10, paddingH = 12, paddingV = 8 }, {
          ui.markdown({ key = key .. "-md", text = msg.text, width = width - 24 }),
        }))
      else
        if msg.thinking ~= nil then
          for _, node in thinkingNodes(key .. "-think", msg.thinking, (m.openThinking or {})[i] == true, width, function()
            cb.toggleThinking(i)
          end) do
            table.insert(items, node)
          end
        end
        for j, t in msg.tools or {} do
          table.insert(items, toolLine(key .. "-tool-" .. j, t))
        end
        if msg.text ~= nil and msg.text ~= "" then
          table.insert(items, ui.markdown({ key = key, text = msg.text, width = width }))
        end
        for _, node in mediaNodes(key, i, msg, width, cb) do
          table.insert(items, node)
        end
        if STATE_TEXT[msg.state] ~= nil then
          table.insert(items, common.muted(key .. "-state", tr(STATE_TEXT[msg.state])))
        end
      end
    end
    if busy then
      for j, t in chat.tools or {} do
        table.insert(items, toolLine("live-tool-" .. j, t))
      end
      if chat.streaming ~= nil and chat.streaming ~= "" then
        table.insert(items, ui.markdown({ key = "live", text = chat.streaming, width = width }))
      end
      -- the status line opens what Hermes has relayed so far
      local liveOpen = (m.openThinking or {}).live == true
      table.insert(items, ui.row({ key = "live-status", gap = 6, align = "center", onClick = function()
        cb.toggleThinking("live")
      end }, {
        ui.glyph({ key = "live-g", name = "dots", size = 14, color = C.accent }),
        common.muted("live-t", busyText(chat.status)),
        ui.glyph({ key = "live-c", name = if liveOpen then "chevron-up" else "chevron-down", size = 12, color = C.muted }),
      }))
      if liveOpen then
        table.insert(items, ui.column({ key = "live-box", fill = C.soft, radius = 10, paddingH = 10, paddingV = 8 }, {
          common.muted("live-body", chat.preview or tr("hermes.chat.thinking_none"), { fontSize = 12, maxWidth = width - 20 }),
        }))
      end
    end
    table.insert(column, common.scroll("chat-scroll", items, { gap = 10, stickToBottom = true, scrollToBottomRev = #(chat.messages or {}) }))
  end

  if chat.approval ~= nil then
    table.insert(column, approvalCard(chat.approval, cb))
  end

  local notice = chat.notice
  if notice == nil and #(chat.messages or {}) > 0 and m.link == "offline" then
    notice = "offline"
  end
  if notice ~= nil then
    table.insert(column, ui.row({ key = "notice", fill = C.soft, radius = 10, paddingH = 10, paddingV = 8, gap = 8, align = "center" }, {
      ui.glyph({ key = "notice-g", name = "info-circle", size = 14, color = C.muted }),
      common.muted("notice-t", tr("hermes.notice." .. notice), { flexGrow = 1, maxLines = 3 }),
    }))
  end

  local picks = if m.modelPicker then nil else suggestions(m.draft, cb)
  if picks ~= nil then
    table.insert(column, picks)
  end

  -- attachments waiting for the next message
  local pending = chat.pending or {}
  if #pending > 0 then
    local chips = {}
    for i, f in pending do
      table.insert(chips, ui.row({ key = "pend-row-" .. i }, {
        fileChip("pend-" .. i, KIND_GLYPH[f.kind] or "file", f.name, {
          ui.row({ key = "pend-" .. i .. "-x", onClick = function()
            cb.cmd("detach", { i = i })
          end }, { ui.glyph({ key = "pend-" .. i .. "-xg", name = "x", size = 12, color = C.muted }) }),
        }),
      }))
    end
    table.insert(column, ui.column({ key = "pending", gap = 4 }, chips))
  end

  local action = if busy
    then common.icon("stop", "player-stop-filled", cb.stop, { size = 32, fill = C.bad, color = C.onBad })
    else common.icon("send", "arrow-up", cb.sendDraft, { size = 32, fill = C.accent, color = C.onAccent })
  -- the composer: the input on top, then new chat, attach, the model, send
  table.insert(column, ui.column({ key = "composer", fill = C.tile, radius = 18, paddingH = 8, paddingV = 6, gap = 2 }, {
    ui.input({
      key = "hermes-input-" .. m.inputKey,
      value = m.inputSeed,
      placeholder = tr("hermes.chat.placeholder"),
      multiline = true,
      submitOnEnter = true,
      frameVisible = false,
      focus = true,
      width = width - 16,
      height = 36,
      enabled = not busy,
      onChange = cb.draft,
      onSubmit = cb.send,
    }),
    ui.row({ key = "composer-bar", gap = 2, align = "center" }, {
      common.icon("new", "message-plus", cb.new, { size = 30, fill = C.clear, color = C.muted }),
      common.icon("attach", "paperclip", function()
        cb.cmd("attach")
      end, { size = 30, fill = if #pending > 0 then C.accentSoft else C.clear, color = if #pending > 0 then C.accent else C.muted }),
      ui.row({ key = "model-wrap", flexGrow = 1, align = "center" }, {
        ui.row({
          key = "model-chip",
          fill = if m.modelPicker then C.accentSoft else C.soft,
          radius = 9,
          paddingH = 9,
          paddingV = 5,
          gap = 5,
          align = "center",
          onClick = cb.models,
        }, {
          ui.glyph({ key = "model-chip-g", name = "cpu", size = 12, color = if m.modelPicker then C.accent else C.muted }),
          common.label("model-chip-t", modelName(m), { fontSize = 11, color = if m.modelPicker then C.accent else C.ink, maxLines = 1, maxWidth = width - 150 }),
          ui.glyph({ key = "model-chip-c", name = if m.modelPicker then "chevron-up" else "chevron-down", size = 12, color = if m.modelPicker then C.accent else C.muted }),
        }),
      }),
      action,
    }),
  }))

  return common.panel("chat", column)
end

return M
