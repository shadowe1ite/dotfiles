--!nonstrict
-- Inbox. The list is only sender, subject, and time. A click opens the
-- message, which is where the alias, the preview, and the code live.
local common = require("./lib/common.luau")

local open = false
local selected = nil
local confirmingClear = false
local letterEpoch = 0
local view = common.view()
local render

local function initial(text)
  local ch = string.match(text, "([%a%d])")
  if ch == nil then
    return "@"
  end
  return string.upper(ch)
end

local function findMessage(uid)
  if uid == nil then
    return nil
  end
  for _, item in ipairs(view.messages) do
    if item.uid == uid then
      return item
    end
  end
  return nil
end

local function tile(glyph, fill, color, box)
  return ui.column({
    width = box,
    height = box,
    radius = math.floor(box / 3),
    fill = fill,
    align = "center",
    justify = "center",
  }, {
    ui.glyph({ name = glyph, size = math.floor(box * 0.5), color = color }),
  })
end

local function avatar(text, unread, box)
  return ui.column({
    width = box,
    height = box,
    radius = math.floor(box / 2),
    fill = unread and "primary/0.28" or "surface_variant/0.7",
    align = "center",
    justify = "center",
  }, {
    ui.label({
      text = initial(text),
      fontSize = box >= 44 and 18 or 14,
      fontWeight = "bold",
      color = unread and "primary" or "on_surface_variant",
    }),
  })
end

local function aliasCard()
  local v = view
  local address = v.address
  local text
  if address == "" then
    text = ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = noctalia.tr("panel.alias_kicker"), fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
      ui.label({ text = noctalia.tr("panel.alias_hint"), fontSize = 13, maxLines = 2 }),
    })
  else
    text = ui.column({ gap = 1, flexGrow = 1 }, {
      ui.label({ text = noctalia.tr("panel.alias_kicker"), fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
      ui.label({ key = "addr", text = address, fontSize = 15, fontWeight = "bold", maxLines = 2 }),
    })
  end
  return ui.column({
    gap = 8,
    padding = 12,
    radius = 16,
    fill = "surface_variant/0.45",
  }, {
    ui.row({ gap = 10, align = "center" }, {
      tile("at", "primary/0.22", "primary", 32),
      text,
      ui.button({
        glyph = "copy",
        variant = "ghost",
        controlSize = "sm",
        enabled = address ~= "",
        tooltip = noctalia.tr("panel.copy_alias"),
        onClick = function()
          common.copy(address)
        end,
      }),
    }),
    ui.button({
      text = v.generating and noctalia.tr("panel.generating") or noctalia.tr("panel.new_short"),
      glyph = v.generating and "loader" or "plus",
      variant = "primary",
      controlSize = "sm",
      enabled = not v.generating,
      onClick = function()
        common.request("generate")
      end,
    }),
  })
end

local function problem()
  if view.detail == "" or common.online(view.status) then
    return nil
  end
  return ui.row({ gap = 8, padding = 12, radius = 12, align = "center", fill = "error/0.12" }, {
    ui.glyph({ name = "alert-circle", size = 16, color = "error" }),
    ui.label({ text = view.detail, fontSize = 12, color = "error", flexGrow = 1, maxLines = 2 }),
  })
end

local function messageRow(item)
  local who = item.sender ~= "" and item.sender or item.alias
  local subject = item.subject ~= "" and item.subject or noctalia.tr("panel.no_subject")
  local title = {
    ui.label({
      key = "who",
      text = who,
        fontSize = 14,
        fontWeight = item.unread and "bold" or "medium",
      flexGrow = 1,
      maxLines = 1,
    }),
  }
  if item.otp ~= "" then
    table.insert(title, ui.column({
      key = "otp",
      paddingH = 6,
      paddingV = 2,
      radius = 6,
      fill = "primary/0.2",
    }, {
      ui.label({ text = item.otp, fontSize = 11, fontWeight = "bold", color = "primary" }),
    }))
  end
  table.insert(title, ui.label({
    key = "when",
    text = common.when(item.at, noctalia.nowMs()),
    fontSize = 11,
    color = "on_surface_variant",
  }))
  return ui.row({
    key = "m" .. item.uid,
    gap = 10,
    paddingV = 8,
    paddingH = 4,
    radius = 12,
    align = "center",
    fill = item.unread and "primary/0.1" or "transparent",
    onClick = function()
      selected = item.uid
      if item.unread then
        common.request("read", item.uid)
      end
      render()
    end,
  }, {
    ui.box({
      key = "bar",
      width = 3,
      height = 28,
      radius = 2,
      fill = item.unread and "primary" or "transparent",
    }),
    avatar(who, item.unread, 34),
    ui.column({ key = "text", gap = 2, flexGrow = 1 }, {
      ui.row({ key = "top", gap = 8, align = "center" }, title),
      ui.label({ text = subject, fontSize = 13, color = "on_surface", maxLines = 2 }),
    }),
  })
end

local function inboxList()
  local v = view
  if #v.messages == 0 then
    return ui.column({ flexGrow = 1, gap = 8, align = "center", justify = "center" }, {
      tile("inbox", "surface_variant/0.45", "on_surface_variant", 36),
      ui.label({ text = noctalia.tr("panel.empty"), fontSize = 15, fontWeight = "bold", textAlign = "center" }),
      ui.label({
        text = noctalia.tr("panel.empty_hint"),
        fontSize = 12,
        color = "on_surface_variant",
        textAlign = "center",
        maxLines = 3,
      }),
    })
  end

  local rows = {}
  for _, item in ipairs(v.messages) do
    table.insert(rows, messageRow(item))
  end
  return ui.scroll({ flexGrow = 1, gap = 2 }, rows)
end

local function clearConfirm()
  return ui.row({ gap = 8, padding = 12, radius = 12, align = "center", fill = "error/0.12" }, {
    ui.glyph({ name = "trash", size = 16, color = "error" }),
    ui.label({ text = noctalia.tr("panel.clear_confirm"), fontSize = 13, flexGrow = 1, maxLines = 2 }),
    ui.button({
      text = noctalia.tr("panel.clear"),
      variant = "destructive",
      controlSize = "sm",
      onClick = function()
        confirmingClear = false
        selected = nil
        common.request("clear")
      end,
    }),
    ui.button({
      text = noctalia.tr("panel.cancel"),
      variant = "ghost",
      controlSize = "sm",
      onClick = function()
        confirmingClear = false
        render()
      end,
    }),
  })
end

local function inboxHeader()
  local count = view.unread
  local side = {
    ui.button({
      key = "refresh",
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("panel.refresh"),
      onClick = function()
        common.request("refresh")
      end,
    }),
  }
  if count > 0 then
    table.insert(side, ui.label({
      text = noctalia.tr("panel.new_count", { count = tostring(count) }),
      fontSize = 12,
      fontWeight = "bold",
      color = "primary",
    }))
    table.insert(side, ui.button({
      text = noctalia.tr("panel.mark_read"),
      variant = "ghost",
      controlSize = "sm",
      onClick = function()
        common.request("read", "")
      end,
    }))
  end
  if #view.messages > 0 then
    table.insert(side, ui.button({
      text = noctalia.tr("panel.clear"),
      glyph = "trash",
      variant = "ghost",
      controlSize = "sm",
      onClick = function()
        confirmingClear = true
        render()
      end,
    }))
  end
  return ui.row({ align = "center", gap = 8 }, {
    ui.label({
      text = noctalia.tr("panel.inbox"),
      fontSize = 11,
      fontWeight = "bold",
      color = "on_surface_variant",
      flexGrow = 1,
    }),
    ui.row({ gap = 4, align = "center" }, side),
  })
end

local function listScreen()
  local children = { aliasCard() }
  local banner = problem()
  if banner ~= nil then
    table.insert(children, banner)
  end
  table.insert(children, inboxHeader())
  if confirmingClear then
    table.insert(children, clearConfirm())
  end
  table.insert(children, inboxList())
  return ui.column({ padding = 10, gap = 8, flexGrow = 1 }, children)
end

local function codeCard(item)
  return ui.row({
    gap = 12,
    paddingH = 14,
    paddingV = 10,
    radius = 14,
    align = "center",
    fill = "primary/0.14",
  }, {
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = noctalia.tr("panel.otp_label"), fontSize = 11, color = "on_surface_variant" }),
      ui.label({ text = item.otp, fontSize = 26, fontWeight = "bold", color = "primary" }),
    }),
    ui.button({
      text = noctalia.tr("panel.copy_code"),
      glyph = "copy",
      variant = "primary",
      controlSize = "sm",
      onClick = function()
        common.copy(item.otp)
      end,
    }),
  })
end

local function joinWrappedUrls(text)
  -- Mail often wraps a tracking link inside <https://...> across many lines.
  -- Pull those back into one address before anything tries to draw them.
  text = string.gsub(text, "<(https?://[^>]+)>", function(url)
    return string.gsub(url, "%s+", "")
  end)
  local guard = 0
  while guard < 30 do
    guard += 1
    local nextText, count = string.gsub(text, "(https?://%S+)\n(%S+)", "%1%2")
    if count == 0 then
      break
    end
    text = nextText
  end
  return text
end

local function messageScreen(item)
  local who = item.sender ~= "" and item.sender or item.alias
  local subject = item.subject ~= "" and item.subject or noctalia.tr("panel.no_subject")
  local preview = item.preview ~= "" and item.preview or ""
  local children = {
    ui.row({ gap = 8, align = "center" }, {
      ui.button({
        glyph = "arrow-left",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.back"),
        onClick = function()
          selected = nil
          render()
        end,
      }),
      ui.column({ gap = 1, flexGrow = 1 }, {
        ui.label({ text = who, fontSize = 14, fontWeight = "bold", maxLines = 1 }),
        ui.label({ text = common.when(item.at, noctalia.nowMs()), fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
      }),
      ui.button({
        glyph = "trash",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.delete"),
        onClick = function()
          local uid = item.uid
          selected = nil
          common.request("delete", uid)
          render()
        end,
      }),
    }),
    ui.label({ text = subject, fontSize = 15, fontWeight = "bold", maxLines = 3 }),
  }
  if item.alias ~= "" then
    table.insert(children, ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = item.alias, fontSize = 12, color = "primary", flexGrow = 1, maxLines = 1 }),
      ui.button({
        glyph = "copy",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.copy_alias"),
        onClick = function()
          common.copy(item.alias)
        end,
      }),
    }))
  end
  if item.otp ~= "" then
    table.insert(children, codeCard(item))
  end
  -- The field fills the visible letter, so dragging a selection to its edge
  -- pans the text, and a two-finger swipe pans that same text. Typing rebuilds
  -- the original letter, so edits never stick.
  local letter = joinWrappedUrls(preview)
  table.insert(children, ui.input({
    key = "letter-" .. item.uid .. "-" .. tostring(letterEpoch),
    value = letter,
    multiline = true,
    frameVisible = false,
    fontSize = 13,
    flexGrow = 1,
    placeholder = noctalia.tr("panel.no_preview"),
    onChange = function(value)
      if value ~= letter then
        letterEpoch += 1
        render()
      end
    end,
  }))
  return ui.column({ padding = 12, gap = 8, flexGrow = 1 }, children)
end

render = function()
  if not open then
    return
  end
  local item = findMessage(selected)
  if item == nil then
    selected = nil
    panel.render(listScreen())
  else
    panel.render(messageScreen(item))
  end
end

function onOpen()
  open = true
  selected = nil
  confirmingClear = false
  view = common.view()
  render()
end

function onClose()
  open = false
  selected = nil
  confirmingClear = false
end

noctalia.state.watch("duck", function()
  view = common.view()
  render()
end)
