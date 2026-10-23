--!nonstrict
-- Draws the orb as a ui.* tree, after Marea: a ball with two tall pills for
-- eyes and, on its own, a faint outline. Colors come from the plugin settings
-- (the theme's primary for the body and surface for the eyes, by default). The same inputs give the same tree, so the bar widget and
-- the roamer show the same character.
--
--   face.render({
--     size, scale?, sx?, sy?,      -- px, overall scale, squash/stretch
--     body, eye,                   -- palette role or #rrggbb
--     rim?,                        -- outline color (M.outline), nil for none
--     lid?, lookX?, lookY?,        -- from Life
--     breath?, mood?,              -- "normal" | "happy" | "surprised" | "sleepy"
--     key?, onClick?, onHover?,    -- callback names or functions
--   })

local M = {}

-- ui.box draws a default fill when it has none: spacers need an explicit clear one.
M.CLEAR = "#00000000"

-- "primary" -> "primary/0.4", "#rrggbb" -> "#rrggbb66"
function M.withAlpha(color, alpha)
  if string.sub(color, 1, 1) == "#" then
    if #color == 7 then
      return color .. string.format("%02x", math.floor(alpha * 255 + 0.5))
    end
    return color
  end
  return `{color}/{alpha}`
end

-- Relative luminance (0..1) of a #rrggbb / #rrggbbaa color; nil for anything else.
function M.luminance(hex)
  if type(hex) ~= "string" or not string.match(hex, "^#%x%x%x%x%x%x") then
    return nil
  end
  local function channel(i)
    local c = tonumber(string.sub(hex, i, i + 1), 16) / 255
    return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * channel(2) + 0.7152 * channel(4) + 0.0722 * channel(6)
end

-- Index of the color in `hexes` that stands out most against `background`.
function M.contrasting(hexes, background)
  local bg = M.luminance(background) or 0
  local best, bestRatio = 1, -1
  for i, hex in hexes do -- skips missing entries
    local l = M.luminance(hex)
    if l ~= nil then
      local ratio = (math.max(l, bg) + 0.05) / (math.min(l, bg) + 0.05)
      if ratio > bestRatio then
        best, bestRatio = i, ratio
      end
    end
  end
  return best
end

-- The outline settings as a color, or nil when it is off.
function M.outline(enabled, color, opacity)
  if not enabled or (opacity or 0) <= 0 then
    return nil
  end
  return M.withAlpha(color, opacity / 100)
end

-- Gaze moves the eyes by padding them with invisible boxes on one side: flex
-- layout has no absolute positions.
local function spacer(key, w, h)
  return ui.box({ key = key, width = math.max(w, 0), height = math.max(h, 0), fill = M.CLEAR, visible = w > 0.5 and h > 0.5 })
end

local function eye(key, o, s)
  if o.mood == "happy" then
    return ui.glyph({ key = key, name = "chevron-up", size = math.max(s * 0.34, 6), color = o.eye })
  end
  local w, h = s * 0.11, s * 0.29
  if o.mood == "surprised" then
    w, h = s * 0.17, s * 0.17
  elseif o.mood == "sleepy" then
    h *= 0.2
  end
  h = math.max(h * (o.lid or 1), math.max(1.5, s * 0.05))
  return ui.box({ key = key, width = w, height = h, radius = math.min(w, h) / 2, fill = o.eye })
end

function M.render(o)
  local key = o.key or "ball"
  local s = o.size * (o.scale or 1) * (1 + 0.04 * (o.breath or 0))
  if s < 1 then
    return ui.box({ key = key, width = 1, height = 1, fill = M.CLEAR, visible = false })
  end
  local bw, bh = s * (o.sx or 1), s * (o.sy or 1)
  local dx = (o.lookX or 0) * s * 0.12
  local dy = (o.lookY or 0) * s * 0.10 - (o.breath or 0) * s * 0.04

  local eyes = ui.row({ key = "eyes", align = "center" }, {
    spacer("pl", 2 * dx, 1),
    eye("el", o, s),
    ui.box({ key = "gap", width = s * 0.22, height = 1, fill = M.CLEAR }),
    eye("er", o, s),
    spacer("pr", -2 * dx, 1),
  })

  return ui.column({
    key = key,
    width = bw,
    height = bh,
    radius = math.min(bw, bh) / 2,
    fill = o.body,
    border = o.rim,
    borderWidth = if o.rim ~= nil then 1 else nil,
    align = "center",
    justify = "center",
    onClick = o.onClick,
    onHover = o.onHover,
  }, {
    ui.column({ key = "face", align = "center" }, {
      spacer("pt", 1, 2 * dy),
      eyes,
      spacer("pb", 1, -2 * dy),
    }),
  })
end

return M
