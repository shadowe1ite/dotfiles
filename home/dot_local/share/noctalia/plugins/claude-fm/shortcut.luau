--!nonstrict
-- Control center tile: shows play state, click toggles playback.
local common = require("./lib/common.luau")

local pb = common.playback()

local function refresh()
  shortcut.setLabel("Claude FM")
  shortcut.setIcon("radio")
  shortcut.setActive(pb.status == "playing")
end

function onClick()
  common.request("toggle")
end

noctalia.state.watch("playback", function(_v)
  pb = common.playback()
  refresh()
end)

refresh()
