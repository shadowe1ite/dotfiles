--!nonstrict
-- Unit tests for the pure color helpers in lib/face.luau (withAlpha). Run with tests/run.sh.

local face = require("../lib/face")

local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

check("withAlpha on a palette role", face.withAlpha("primary", 0.4) == "primary/0.4")
check("withAlpha on a hex color", face.withAlpha("#ffffff", 0.1) == "#ffffff1a", face.withAlpha("#ffffff", 0.1))
check("withAlpha leaves #rrggbbaa alone", face.withAlpha("#11223344", 0.5) == "#11223344")

check("outline from a role", face.outline(true, "primary", 40) == "primary/0.4")
check("outline from hex", face.outline(true, "#ffffff", 10) == "#ffffff1a")
check("outline off when disabled", face.outline(false, "#ffffff", 10) == nil)
check("outline off at opacity 0", face.outline(true, "#ffffff", 0) == nil)

check("luminance of white and black", math.abs(face.luminance("#ffffff") - 1) < 1e-6 and face.luminance("#000000") == 0)
check("luminance ignores alpha", face.luminance("#ffffff80") == face.luminance("#ffffff"))
check("luminance of junk is nil", face.luminance("primary") == nil)
check("contrast picks the bright one on a dark bar", face.contrasting({ "#1a1c18", "#9ed67c" }, "#121410") == 2)
check("contrast picks the dark one on a light bar", face.contrasting({ "#1a1c18", "#e8f0e0" }, "#f4f4f0") == 1)
check("contrast skips unknown colors", face.contrasting({ nil, "#9ed67c" }, "#121410") == 2)

if failures > 0 then
  error(`{failures} face test(s) failed`)
end
