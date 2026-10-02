-- Control center tile: shows the habit in focus, click opens the panel.
local common = require("./lib/common.luau")

local function refresh()
  local current = noctalia.state.get("current")
  local active = current ~= nil and current ~= ""
  shortcut.setLabel(active and current or "Habits")
  shortcut.setIcon("target")
  shortcut.setActive(active)
end

function onClick()
  noctalia.togglePanel(common.PANEL_ID)
end

refresh()
noctalia.state.watch("current", refresh)
