-- Facade for the panel header: draw the mascot for this moment of the loop.
local sprite = require("./lib/sprite.luau")
local scene = require("./lib/scene.luau")
local choreo = require("./choreo.luau")
local styles = require("./styles.luau")

local clawd = {}

-- Sub-pixel window around the sprite (x 0..17, y 0..5) with a step of headroom.
clawd.VIEW = { x = -1, y = -1, w = 20, h = 8 }

-- playing: the radio plays, so dance the loop; otherwise idle. p: pixel size.
function clawd.render(now, playing, p, ui)
  local name, snap = choreo.frame(now, playing)
  local sc = styles.get(name).frame(now, snap, { compact = true })
  return scene.toUi(scene.compose(sc, sprite, clawd.VIEW), p, ui)
end

return clawd
