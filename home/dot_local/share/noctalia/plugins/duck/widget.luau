--!nonstrict
-- Bar: just the mail symbol. A dot appears when there is mail to read.
local common = require("./lib/common.luau")

local view = common.view()

local function tint(v)
  if v.status == "error" or v.status == "reconnecting" then
    return "error"
  end
  if v.unread > 0 or v.generating then
    return "primary"
  end
  return "on_surface"
end

local function open()
  noctalia.togglePanel(common.PANEL_ID)
end

local function mark()
  local items = {
    ui.glyph({ key = "g", name = view.generating and "loader" or "mail", size = 15, color = tint(view) }),
  }
  if view.unread > 0 then
    table.insert(items, ui.box({ key = "dot", width = 6, height = 6, radius = 3, fill = "primary" }))
  end
  return ui.row({ key = "m", gap = 4, align = "center", onClick = open }, items)
end

local function render()
  local v = view
  local tipAddress = v.address ~= "" and v.address or noctalia.tr("tooltip.none")
  barWidget.setTooltip({
    { noctalia.tr("tooltip.address"), tipAddress },
    { noctalia.tr("tooltip.unread"), tostring(v.unread) },
    { noctalia.tr("tooltip.status"), common.statusLabel(v.status) },
  })
  if barWidget.isVertical() then
    barWidget.render(ui.column({ align = "center" }, { mark() }))
    return
  end
  barWidget.render(mark())
end

function update()
  render()
  noctalia.setUpdateInterval(60000)
end

function onClick()
  open()
end

function onRightClick()
  common.request("generate")
end

noctalia.state.watch("duck", function()
  view = common.view()
  render()
end)

render()
