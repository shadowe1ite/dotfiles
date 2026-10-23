--!nonstrict
-- The orb's card, Marea-style: not a panel beside the ball but the ball's own
-- body stretched out. The ball sits in the card's corner, drawn on top, in the
-- same color, so the two read as one silhouette. Its outline runs around that
-- one silhouette: outline-colored copies of card and ball, 1 px larger, go
-- underneath both, so only the outer edge shows and nothing is drawn where the
-- ball meets the card.
--
-- Flex layout cannot overlap, so layers are stacked with negative gaps. Input
-- goes to the topmost node under the pointer even when that node is a plain
-- container, so the only thing stacked above the card is a row exactly as tall
-- as the ball, on the ball's side: the card's controls stay clickable.

local face = require("./face.luau")

local M = {}

local function spacer(key, w, h)
  return ui.box({ key = key, width = math.max(w, 0), height = math.max(h, 0), fill = face.CLEAR, visible = w > 0.5 and h > 0.5 })
end

-- Place `node` at (x, y) inside a w x h layer.
local function at(key, w, h, x, y, node)
  return ui.column({ key = key, width = w, height = h, align = "start" }, {
    spacer(key .. "-t", 1, y),
    ui.row({ key = key .. "-r", align = "start" }, { spacer(key .. "-l", x, 1), node }),
  })
end

--   lay                  motion.cardLayout(...)
--   x, y, w, h           motion.cardRect(...) - the card inside the surface
--   radius, fill         card shape
--   rim                  the outline around card + ball (nil: none)
--   shadow               0..1, shadow strength (shown while the card is out)
--   ball, bw, bh         the face node and its current size
--   content              node or nil (nil while the card is still growing)
function M.scene(o)
  local lay = o.lay
  local sw, sh = lay.sw, lay.sh

  local shadow = ui.box({
    key = "shadow",
    width = o.w,
    height = o.h,
    radius = o.radius,
    fill = face.withAlpha("#05070a", 0.45 * o.shadow),
    softness = 14,
  })
  local cardNode = ui.column({
    key = "card",
    width = o.w,
    height = o.h,
    radius = o.radius,
    fill = o.fill,
    padding = 18,
    gap = 12,
  }, if o.content ~= nil then { o.content } else {})

  local layers = { at("shadowL", sw, sh, o.x, o.y + 4, shadow) }
  if o.rim ~= nil then
    local r = 1
    table.insert(layers, at("rimCardL", sw, sh, o.x - r, o.y - r, ui.box({
      key = "rimCard", width = o.w + 2 * r, height = o.h + 2 * r, radius = o.radius + r, fill = o.rim,
    })))
    table.insert(layers, at("rimBallL", sw, sh, lay.bx - o.bw / 2 - r, lay.by - o.bh / 2 - r, ui.box({
      key = "rimBall", width = o.bw + 2 * r, height = o.bh + 2 * r, radius = math.min(o.bw, o.bh) / 2 + r, fill = o.rim,
    })))
  end
  table.insert(layers, at("cardL", sw, sh, o.x, o.y, cardNode))
  local stack = ui.column({ key = "stack", width = sw, height = sh, gap = -sh, align = "start" }, layers)

  -- The ball row: on the ball's side only, as tall as the ball.
  local ballRow
  if lay.flipX then
    ballRow = ui.row({ key = "ballrow", align = "center" }, { o.ball, spacer("ball-r", sw - (lay.bx + o.bw / 2), 1) })
  else
    ballRow = ui.row({ key = "ballrow", align = "center" }, { spacer("ball-l", lay.bx - o.bw / 2, 1), o.ball })
  end

  return ui.column({
    key = "scene",
    width = sw,
    height = sh,
    align = if lay.flipX then "end" else "start",
    gap = lay.by - o.bh / 2 - sh,
  }, { stack, ballRow })
end

-- A round glyph button in the header.
local function iconButton(key, glyph, colors, onClick)
  return ui.row({
    key = key,
    width = 30,
    height = 30,
    radius = 15,
    fill = colors.soft,
    align = "center",
    justify = "center",
    onClick = onClick,
  }, { ui.glyph({ key = key .. "-g", name = glyph, size = 15, color = colors.muted }) })
end

local LINK_COLORS = { online = "#4caf50", degraded = "#f4b400", auth = "#f4b400", offline = "error", unknown = "on_surface_variant" }

--   flipX                ball on the right: header mirrors so the ball covers nothing
--   ballRoom             px kept clear in the header for the ball
--   title, status        "Hermes" and what it is up to, after a link-colored dot
--   link                 Hermes link status (the dot's color)
--   primaryGlyph         the orb's own action (stay out / call home), onPrimary
--   onSettings, onClose  callback names
--   tabs                 { { id, glyph, label, dot? } }, activeTab; each tab calls onTab_<id>
--                        (none: no tab bar, as while the card is locked for setup)
--   body                 the active tab's node
--   width                content width (the tab bar spans it)
--   colors               { ink, muted, soft, tile, accent, onAccent }
--   opacity              content fade
function M.content(m)
  local c = m.colors
  local titles = ui.column({ key = "titles", gap = 2, flexGrow = 1 }, {
    ui.label({ key = "title", text = m.title, fontSize = 17, fontWeight = "semibold", color = c.ink, maxLines = 1 }),
    ui.row({ key = "status-row", gap = 6, align = "center" }, {
      ui.box({ key = "link-dot", width = 7, height = 7, radius = 3.5, fill = LINK_COLORS[m.link or "unknown"] or LINK_COLORS.unknown }),
      ui.label({ key = "status", text = m.status or "", fontSize = 11, color = c.muted, maxLines = 1, maxWidth = m.statusWidth }),
    }),
  })
  -- Room for the ball, which overlaps the card's corner.
  local ballRoom = ui.box({ key = "ballroom", width = m.ballRoom or 30, height = 1, fill = face.CLEAR })
  local buttons = ui.row({ key = "head-buttons", gap = 6, align = "center" }, {
    iconButton("primary", m.primaryGlyph, c, m.onPrimary),
    iconButton("settings", "settings", c, m.onSettings),
    iconButton("close", "x", c, m.onClose),
  })
  local header = if m.flipX then { buttons, titles, ballRoom } else { ballRoom, titles, buttons }

  -- A segmented bar of equal tabs. Widths are always explicit: a retained node keeps an old
  -- width a render leaves out.
  local TAB_GAP, BAR_PAD = 2, 3
  local count = #(m.tabs or {})
  local tabW = if count > 0 then math.floor((m.width - 2 * BAR_PAD - (count - 1) * TAB_GAP) / count) else 0
  local tabs = {}
  for _, t in m.tabs or {} do
    local active = t.id == m.activeTab
    local ink = if active then c.onAccent else c.muted
    local children = {
      ui.glyph({ key = "tab-" .. t.id .. "-g", name = t.glyph, size = 15, color = ink }),
      ui.label({ key = "tab-" .. t.id .. "-t", text = t.label, fontSize = 12, fontWeight = "semibold", color = ink }),
    }
    if t.dot ~= nil then
      table.insert(children, ui.box({ key = "tab-" .. t.id .. "-dot", width = 6, height = 6, radius = 3, fill = t.dot }))
    end
    table.insert(tabs, ui.row({
      key = "tab-" .. t.id,
      fill = if active then c.accent else face.CLEAR,
      radius = 9,
      height = 30,
      width = tabW,
      paddingH = 10,
      gap = 6,
      align = "center",
      justify = "center",
      onClick = "onTab_" .. t.id,
    }, children))
  end

  local children = { ui.row({ key = "header", gap = 10, align = "center" }, header) }
  if count > 0 then
    table.insert(children, ui.row({ key = "tabs", width = m.width, gap = TAB_GAP, align = "center", fill = c.tile, radius = 12, padding = BAR_PAD }, tabs))
  end
  table.insert(children, m.body)
  return ui.column({ key = "content", gap = 12, flexGrow = 1, opacity = m.opacity }, children)
end

return M
