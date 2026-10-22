-- Style registry for the header mascot: idle, headbang and showtime (spin). The
-- only place that requires the style files; it passes the shared props in.
local props = require("./lib/props.luau")

local FACTORIES = {
  idle = require("./lib/styles/idle.luau"),
  headbang = require("./lib/styles/headbang.luau"),
  spin = require("./lib/styles/spin.luau"),
}

local styles = {}

local built = {}
for name, factory in pairs(FACTORIES) do
  built[name] = factory(props)
end

function styles.get(name)
  return built[name]
end

return styles
