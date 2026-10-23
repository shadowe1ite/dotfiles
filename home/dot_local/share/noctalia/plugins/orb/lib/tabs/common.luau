--!nonstrict
-- Shared pieces for the card's tabs. Tabs sit straight on the card (Card color, a surface
-- role by default) in the theme's text colors: Hermes replies render as markdown, which
-- always uses the theme text color, so the card has to be a surface for them to read.

local M = {}

M.COLORS = {
  tile = "surface", -- rows, the composer
  soft = "on_surface/0.08", -- buttons and chips, on the card or on a tile
  ink = "on_surface",
  muted = "on_surface_variant",
  accent = "primary",
  onAccent = "on_primary",
  accentSoft = "primary/0.14",
  bad = "error",
  onBad = "on_error",
  clear = "#00000000",
}

local C = M.COLORS

function M.tr(key, subst)
  return noctalia.tr(key, subst)
end

function M.panel(key, children)
  return ui.column({ key = key, gap = 10, flexGrow = 1 }, children)
end

function M.scroll(key, children, props)
  local p = { key = key, flexGrow = 1, gap = 8 }
  for k, v in props or {} do
    p[k] = v
  end
  return ui.scroll(p, children)
end

function M.label(key, text, props)
  local p = { key = key, text = text or "", color = C.ink }
  for k, v in props or {} do
    p[k] = v
  end
  return ui.label(p)
end

function M.muted(key, text, props)
  local p = { fontSize = 11, color = C.muted }
  for k, v in props or {} do
    p[k] = v
  end
  return M.label(key, text, p)
end

-- A round icon button.
function M.icon(key, glyph, onClick, props)
  local size = (props and props.size) or 28
  return ui.row({
    key = key,
    width = size,
    height = size,
    radius = size / 2,
    fill = (props and props.fill) or C.soft,
    align = "center",
    justify = "center",
    onClick = onClick,
  }, { ui.glyph({ key = key .. "-g", name = glyph, size = math.floor(size * 0.5), color = (props and props.color) or C.ink }) })
end

-- A small button: glyph and/or text.
function M.pill(key, glyph, text, onClick, props)
  local color = (props and props.color) or C.ink
  local children = {}
  if glyph ~= nil then
    table.insert(children, ui.glyph({ key = key .. "-g", name = glyph, size = 13, color = color }))
  end
  if text ~= nil then
    table.insert(children, ui.label({ key = key .. "-t", text = text, fontSize = 12, color = color, fontWeight = (props and props.weight) or "medium" }))
  end
  return ui.row({
    key = key,
    fill = (props and props.fill) or C.soft,
    radius = 9,
    paddingH = if text ~= nil then 11 else 7,
    paddingV = 6,
    gap = 6,
    align = "center",
    justify = "center",
    flexGrow = props and props.grow,
    onClick = onClick,
  }, children)
end

-- A tab's title with an optional refresh button.
function M.header(key, title, onRefresh)
  local children = { M.label(key .. "-t", title, { fontSize = 13, fontWeight = "semibold", flexGrow = 1 }) }
  if onRefresh ~= nil then
    table.insert(children, M.icon(key .. "-refresh", "refresh", onRefresh, { size = 26 }))
  end
  return ui.row({ key = key, gap = 6, align = "center", height = 28 }, children)
end

-- A glyph in a soft accent circle.
function M.badge(key, glyph, size, color)
  size = size or 30
  return ui.row({
    key = key,
    width = size,
    height = size,
    radius = size / 2,
    fill = if color == C.bad then "error/0.14" else C.accentSoft,
    align = "center",
    justify = "center",
  }, { ui.glyph({ key = key .. "-g", name = glyph, size = math.floor(size * 0.5), color = color or C.accent }) })
end

-- A list row: glyph badge, title + subtitle, then trailing nodes.
function M.row(key, glyph, title, subtitle, trailing, onClick, glyphColor)
  local children = {}
  if glyph ~= nil then
    table.insert(children, M.badge(key .. "-b", glyph, 30, glyphColor))
  end
  local text = { M.label(key .. "-t", title, { fontSize = 13, fontWeight = "medium", maxLines = 1 }) }
  if subtitle ~= nil and subtitle ~= "" then
    table.insert(text, M.muted(key .. "-s", subtitle, { maxLines = 2 }))
  end
  table.insert(children, ui.column({ key = key .. "-c", gap = 2, flexGrow = 1 }, text))
  for _, node in trailing or {} do
    table.insert(children, node)
  end
  return ui.row({
    key = key,
    fill = C.tile,
    radius = 12,
    paddingH = 10,
    paddingV = 9,
    gap = 10,
    align = "center",
    onClick = onClick,
  }, children)
end

-- A centered state: a big badge, a title, a line of text, then any extra nodes.
function M.state(key, glyph, title, text, extra, color)
  local children = {
    M.badge(key .. "-b", glyph, 52, color),
    M.label(key .. "-t", title, { fontSize = 15, fontWeight = "semibold", textAlign = "center" }),
  }
  if text ~= nil and text ~= "" then
    table.insert(children, M.muted(key .. "-x", text, { fontSize = 12, textAlign = "center", maxWidth = 300 }))
  end
  for _, node in extra or {} do
    table.insert(children, node)
  end
  return ui.column({ key = key, flexGrow = 1, align = "center", justify = "center", gap = 8, paddingV = 12 }, children)
end

function M.empty(key, glyph, text)
  return ui.column({ key = key, flexGrow = 1, align = "center", justify = "center", gap = 8, paddingV = 24 }, {
    ui.glyph({ key = key .. "-g", name = glyph, size = 26, color = C.muted }),
    M.muted(key .. "-t", text, { fontSize = 12, textAlign = "center", maxWidth = 300 }),
  })
end

-- A list that could not load (only offline: without a key the card is locked for setup).
function M.problem(key, cmd)
  return M.state(key, "wifi-off", M.tr("hermes.offline.title"), M.tr("hermes.offline.text"), {
    M.pill(key .. "-retry", "refresh", M.tr("hermes.retry"), function()
      cmd("refresh")
    end),
  }, C.bad)
end

function M.userBubble(key, text, width)
  return ui.row({ key = key, justify = "end" }, {
    ui.column({ key = key .. "-b", fill = C.accent, radius = 14, paddingH = 12, paddingV = 8 }, {
      M.label(key .. "-t", text, { fontSize = 13, color = C.onAccent, maxWidth = math.floor(width * 0.78) }),
    }),
  })
end

return M
