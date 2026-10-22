--!nonstrict
-- Bar widget: a coral radio glyph plus a mini equalizer while playing.
-- Click opens the panel; right-click toggles play/pause.
local common = require("./lib/common.luau")

local FRAME = common.frameMs(noctalia.getConfig("fps"))
local pb = common.playback()

local function render()
  local playing = pb.status == "playing"
  local active = common.isActive(pb.status)
  local glyphColor = active and common.CLAUDE or "on_surface_variant"

  if barWidget.isVertical() then
    barWidget.setVisible(true)
    barWidget.render(ui.column({ align = "center" }, {
      ui.glyph({ name = "radio", size = 16, color = glyphColor }),
    }))
    return
  end

  local items = { ui.glyph({ key = "g", name = "radio", size = 15, color = glyphColor }) }

  local animate = playing and FRAME > 0
  local heights = common.bars(4, noctalia.nowMs(), animate, 3, 13)
  local bars = {}
  for i, h in ipairs(heights) do
    table.insert(bars, ui.box({
      key = "b" .. i,
      width = 3,
      height = h,
      radius = 2,
      fill = playing and common.CLAUDE or "on_surface_variant/0.4",
    }))
  end
  table.insert(items, ui.row({ key = "eq", gap = 2, align = "end", height = 14 }, bars))

  barWidget.setVisible(true)
  barWidget.render(ui.row({ gap = 5, align = "center" }, items))
end

function update()
  render()
  local playing = pb.status == "playing"
  noctalia.setUpdateInterval((playing and FRAME > 0) and FRAME or 60000)
end

function onClick()
  noctalia.togglePanel(common.PANEL_ID)
end

function onRightClick()
  common.request("toggle")
end

noctalia.state.watch("playback", function(_v)
  pb = common.playback()
  render()
  update()
end)

render()
