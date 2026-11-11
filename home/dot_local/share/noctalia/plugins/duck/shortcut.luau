--!nonstrict
-- Control-center tile. Click creates an alias. Right-click opens the inbox.
local common = require("./lib/common.luau")

local view = common.view()

local function refresh()
  local v = view
  if v.generating then
    shortcut.setLabel(noctalia.tr("shortcut.generating"))
    shortcut.setIcon("loader")
  elseif v.unread > 0 then
    shortcut.setLabel(noctalia.tr("shortcut.unread", { count = tostring(v.unread) }))
    shortcut.setIcon("mail")
  else
    shortcut.setLabel(noctalia.tr("shortcut.label"))
    shortcut.setIcon("mail")
  end
  shortcut.setActive(v.unread > 0 or v.generating)
end

function onClick()
  common.request("generate")
end

function onRightClick()
  noctalia.togglePanel(common.PANEL_ID)
end

noctalia.state.watch("duck", function()
  view = common.view()
  refresh()
end)

refresh()
