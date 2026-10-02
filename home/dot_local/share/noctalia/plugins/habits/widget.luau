-- Bar widget: current habit glyph + today's habit total. Click opens the panel.
local common = require("./lib/common.luau")

local function refresh()
  local data = noctalia.state.get("data")
  local today = data and data.days[common.dayKey(os.time())] or {}
  local total = 0
  for _, hours in pairs(today) do
    total = total + common.sum(hours)
  end

  local glyph = "target"
  local current = noctalia.state.get("current")
  for _, habit in ipairs(common.habits()) do
    if habit.name == current then
      glyph = habit.glyph
    end
  end
  barWidget.setGlyph(glyph)
  barWidget.setText(common.formatDuration(total))
end

function update()
  -- Live changes arrive through state.watch; this tick only catches the day rollover.
  noctalia.setUpdateInterval(60000)
  refresh()
end

function onClick()
  noctalia.togglePanel(common.PANEL_ID)
end

noctalia.state.watch("data", refresh)
noctalia.state.watch("current", refresh)
