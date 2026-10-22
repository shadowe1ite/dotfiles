--!nonstrict
-- Facade for the panel header: draw the mascot for this moment of the loop.
local sprite = require("./lib/sprite.luau")
local scene = require("./lib/scene.luau")
local choreo = require("./choreo.luau")

local clawd = {}

-- Sub-pixel window around the sprite (x 0..17, y 0..5) with a step of headroom.
clawd.VIEW = { x = -1, y = -1, w = 20, h = 8 }

-- playing: the radio plays, so dance the loop; otherwise idle. p: pixel size.
function clawd.render(now, playing, p, ui)
  return scene.toUi(scene.compose(choreo.scene(now, playing), sprite, clawd.VIEW), p, ui)
end

return clawd
