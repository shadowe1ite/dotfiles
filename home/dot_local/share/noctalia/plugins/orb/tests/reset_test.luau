--!nonstrict
-- Unit tests for lib/reset.luau. Run with tests/run.sh.

local reset = require("../lib/reset")

local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

local text = table.concat({
  "[bar]",
  'order = [ "default" ]',
  "",
  '[plugin_settings."shadow/habits"]',
  'habits = "x"',
  "",
  '[plugin_settings."shadow/orb"]',
  'body_color = "primary"',
  "outline = false",
  "",
  '[plugin_settings."shadow/orb".nested]',
  'a = "b"',
  "",
  "[plugins]",
  'enabled = [ "shadow/orb" ]',
  "",
}, "\n")

local out, removed = reset.dropPluginSettings(text, "shadow/orb")
check("reports a removal", removed)
check("drops the plugin's table", not string.find(out, 'plugin_settings."shadow/orb"]', 1, true))
check("drops its subtables", not string.find(out, "nested", 1, true))
check("drops its keys", not string.find(out, "body_color", 1, true))
check("keeps other plugins' settings", string.find(out, '[plugin_settings."shadow/habits"]', 1, true) ~= nil)
check("keeps the tables after it", string.find(out, '[plugins]\nenabled = [ "shadow/orb" ]', 1, true) ~= nil)
check("keeps the tables before it", string.sub(out, 1, 5) == "[bar]")
check("ends with one newline", string.sub(out, -1) == "\n" and string.sub(out, -2) ~= "\n\n")

local same, none = reset.dropPluginSettings("[bar]\nx = 1\n", "shadow/orb")
check("nothing to drop leaves the text alone", not none and same == "[bar]\nx = 1\n")

if failures > 0 then
  error(`{failures} reset test(s) failed`)
end
