-- Habit usage panel: header with live status, range picker, summary card with chart, habit breakdown.
local common = require("./lib/common.luau")

local CHART_HEIGHT = 120
local RANGES = {
  { label = "Today", days = 1 },
  { label = "3 days", days = 3 },
  { label = "14 days", days = 14 },
}

local rangeIndex = 1
local isOpen = false
local confirmingReset = false

local function dayTotal(data, key)
  local total = 0
  for _, hours in pairs(data.days[key] or {}) do
    total = total + common.sum(hours)
  end
  return total
end

-- buckets[i][habit] = seconds; hourly for a single day, daily otherwise.
local function snapshot(days)
  local data = noctalia.state.get("data") or common.load()
  local habits = common.habits()
  local dayKeys = common.lastDays(days)
  local snap = { habits = habits, buckets = {}, labels = {}, totals = {}, total = 0, days = days }

  local function addBucket(values, label)
    table.insert(snap.buckets, values)
    table.insert(snap.labels, label)
    for name, seconds in pairs(values) do
      snap.totals[name] = (snap.totals[name] or 0) + seconds
      snap.total = snap.total + seconds
    end
  end

  if days == 1 then
    local day = data.days[dayKeys[1]] or {}
    for hour = 1, 24 do
      local values = {}
      for _, habit in ipairs(habits) do
        local hours = day[habit.name]
        values[habit.name] = hours and hours[hour] or 0
      end
      addBucket(values, nil)
    end
    snap.highlight = tonumber(os.date("%H")) + 1
    snap.previous = dayTotal(data, common.dayKey(os.time() - 86400))
  else
    for index, key in ipairs(dayKeys) do
      local day = data.days[key] or {}
      local values = {}
      for _, habit in ipairs(habits) do
        values[habit.name] = common.sum(day[habit.name])
      end
      local weekday = os.date("%a", os.time() - (days - index) * 86400)
      addBucket(values, days > 7 and string.sub(weekday, 1, 2) or weekday)
    end
    snap.highlight = days
  end
  return snap
end

local function status()
  if noctalia.state.get("paused") == true then
    return "Paused", "on_surface_variant", nil
  end
  local current = noctalia.state.get("current")
  if current ~= nil and current ~= "" then
    for _, habit in ipairs(common.habits()) do
      if habit.name == current then
        return "Tracking " .. current, habit.color, current
      end
    end
  end
  return "Idle - no habit in focus", "on_surface_variant", nil
end

local function header(statusText, statusColor)
  local paused = noctalia.state.get("paused") == true
  return ui.row({ gap = 12, align = "center" }, {
    ui.column({ width = 40, height = 40, radius = 12, fill = "primary/0.15", align = "center", justify = "center" }, {
      ui.glyph({ name = "target", size = 22, color = "primary" }),
    }),
    ui.column({ gap = 3, flexGrow = 1 }, {
      ui.label({ text = "Habits", fontSize = 17, fontWeight = "bold" }),
      ui.row({ gap = 6, align = "center" }, {
        ui.box({ width = 7, height = 7, radius = 4, fill = statusColor }),
        ui.label({ text = statusText, fontSize = 12, color = "on_surface_variant", maxLines = 1 }),
      }),
    }),
    ui.button({
      glyph = paused and "player-play" or "player-pause",
      variant = "ghost",
      controlSize = "sm",
      tooltip = paused and "Resume tracking" or "Pause tracking",
      onClick = function()
        noctalia.state.set("pauseRequest", { paused = not paused, at = noctalia.nowMs() })
      end,
    }),
    ui.button({
      glyph = "trash",
      variant = "ghost",
      controlSize = "sm",
      tooltip = "Reset history",
      onClick = function()
        confirmingReset = true
        render()
      end,
    }),
  })
end

-- Replaces the range picker while a reset is pending, so clearing history takes two clicks.
local function resetConfirm()
  return ui.row({ gap = 8, padding = 10, radius = 12, align = "center", fill = "error/0.12" }, {
    ui.glyph({ name = "trash", size = 16, color = "error" }),
    ui.label({ text = "Delete all habit history? A backup is kept.", fontSize = 13, flexGrow = 1 }),
    ui.button({
      text = "Reset",
      variant = "destructive",
      controlSize = "sm",
      onClick = function()
        confirmingReset = false
        noctalia.state.set("resetRequest", noctalia.nowMs())
      end,
    }),
    -- Cancel sits where "14 days" was, so a stray click there cannot wipe history.
    ui.button({
      text = "Cancel",
      variant = "ghost",
      controlSize = "sm",
      onClick = function()
        confirmingReset = false
        render()
      end,
    }),
  })
end

local function rangePicker()
  local buttons = {}
  for index, range in ipairs(RANGES) do
    table.insert(buttons, ui.button({
      key = range.label,
      text = range.label,
      controlSize = "sm",
      variant = index == rangeIndex and "primary" or "ghost",
      flexGrow = 1,
      onClick = function()
        rangeIndex = index
        render()
      end,
    }))
  end
  return ui.row({ gap = 4, padding = 4, radius = 12, fill = "surface_variant/0.45" }, buttons)
end

local function comparison(snap)
  if snap.days == 1 then
    local delta = snap.total - (snap.previous or 0)
    if snap.previous == 0 or snap.previous == nil then
      return "No habit time yesterday", "on_surface_variant", "clock"
    end
    if delta >= 0 then
      return common.formatDuration(delta) .. " more than yesterday", "primary", "trending-up"
    end
    return common.formatDuration(-delta) .. " less than yesterday", "on_surface_variant", "trending-down"
  end
  return common.formatDuration(snap.total / snap.days) .. " average per day", "on_surface_variant", "chart-bar"
end

local function shareBar(snap)
  local segments = {}
  for _, habit in ipairs(snap.habits) do
    local seconds = snap.totals[habit.name] or 0
    if seconds > 0 then
      table.insert(segments, ui.box({
        key = habit.name,
        fill = habit.color,
        radius = 4,
        height = 8,
        width = 1,
        flexGrow = seconds / snap.total,
      }))
    end
  end
  if #segments == 0 then
    segments = { ui.box({ fill = "surface_variant/0.6", radius = 4, height = 8, flexGrow = 1 }) }
  end
  return ui.row({ gap = 3 }, segments)
end

local function chart(snap)
  local peak = 0
  for _, values in ipairs(snap.buckets) do
    local sum = 0
    for _, seconds in pairs(values) do
      sum = sum + seconds
    end
    peak = math.max(peak, sum)
  end

  local columns = {}
  for index, values in ipairs(snap.buckets) do
    local segments = {}
    -- Children stack top-down in a bottom-justified column, so add the last habit first.
    for i = #snap.habits, 1, -1 do
      local habit = snap.habits[i]
      local seconds = values[habit.name] or 0
      if seconds > 0 and peak > 0 then
        table.insert(segments, ui.box({
          key = habit.name,
          fill = habit.color,
          radius = 3,
          height = math.max(3, (CHART_HEIGHT - 4) * seconds / peak),
        }))
      end
    end
    table.insert(columns, ui.column({
      key = tostring(index),
      justify = "end",
      gap = 1,
      fill = index == snap.highlight and "primary/0.12" or "surface_variant/0.35",
      radius = 4,
      flexGrow = 1,
      height = CHART_HEIGHT,
    }, segments))
  end

  local labels = {}
  if snap.days == 1 then
    for _, text in ipairs({ "12 AM", "6 AM", "12 PM", "6 PM" }) do
      table.insert(labels, ui.label({ text = text, fontSize = 10, color = "on_surface_variant", flexGrow = 1 }))
    end
  else
    for index, text in ipairs(snap.labels) do
      table.insert(labels, ui.label({
        text = text,
        fontSize = 10,
        fontWeight = index == snap.highlight and "bold" or "normal",
        color = index == snap.highlight and "primary" or "on_surface_variant",
        textAlign = "center",
        flexGrow = 1,
      }))
    end
  end

  return ui.column({ gap = 6 }, {
    ui.row({ gap = snap.days == 1 and 3 or 5, height = CHART_HEIGHT }, columns),
    ui.row({ gap = 3 }, labels),
  })
end

local function summaryCard(snap)
  local text, color, glyph = comparison(snap)
  return ui.column({ gap = 14, padding = 16, radius = 16, fill = "surface_variant/0.3" }, {
    ui.column({ gap = 4 }, {
      ui.label({ text = common.formatDuration(snap.total), fontSize = 32, fontWeight = "bold" }),
      ui.row({ gap = 6, align = "center" }, {
        ui.glyph({ name = glyph, size = 14, color = color }),
        ui.label({ text = text, fontSize = 12, color = color }),
      }),
    }),
    shareBar(snap),
    chart(snap),
  })
end

local function habitCard(habit, seconds, share, live)
  local nameRow = {
    ui.label({ text = habit.name, fontSize = 14, fontWeight = "medium", maxLines = 1 }),
  }
  if live then
    table.insert(nameRow, ui.row({ paddingH = 6, paddingV = 2, radius = 6, fill = common.tint(habit.color, 0.2) }, {
      ui.label({ text = "LIVE", fontSize = 9, fontWeight = "bold", color = habit.color }),
    }))
  end
  table.insert(nameRow, ui.spacer({ flexGrow = 1 }))
  table.insert(nameRow, ui.label({
    text = seconds > 0 and common.formatDuration(seconds) or "-",
    fontSize = 13,
    fontWeight = "medium",
    color = seconds > 0 and "on_surface" or "on_surface_variant",
  }))

  return ui.row({
    key = habit.name,
    gap = 12,
    padding = 12,
    radius = 14,
    align = "center",
    fill = live and common.tint(habit.color, 0.08) or "surface_variant/0.22",
    opacity = seconds > 0 and 1 or 0.55,
  }, {
    ui.column({ width = 40, height = 40, radius = 12, fill = common.tint(habit.color, 0.18), align = "center", justify = "center" }, {
      ui.glyph({ name = habit.glyph, size = 20, color = habit.color }),
    }),
    ui.column({ gap = 8, flexGrow = 1 }, {
      ui.row({ gap = 8, align = "center" }, nameRow),
      ui.row({ gap = 10, align = "center" }, {
        ui.progress({ progress = share, fill = habit.color, height = 5, flexGrow = 1 }),
        ui.label({
          text = string.format("%d%%", math.floor(share * 100 + 0.5)),
          fontSize = 11,
          color = "on_surface_variant",
          width = 32,
          textAlign = "end",
        }),
      }),
    }),
  })
end

local function breakdown(snap, liveHabit)
  if #snap.habits == 0 then
    return {
      ui.column({ gap = 10, padding = 16, radius = 14, fill = "surface_variant/0.22", align = "center" }, {
        ui.label({ text = "No habits configured yet.", color = "on_surface_variant" }),
        ui.button({ text = "Open settings", glyph = "settings", variant = "outline", onClick = function() noctalia.openSettings() end }),
      }),
    }
  end

  local ordered = table.clone(snap.habits)
  table.sort(ordered, function(a, b)
    local sa, sb = snap.totals[a.name] or 0, snap.totals[b.name] or 0
    if sa ~= sb then
      return sa > sb
    end
    return a.name < b.name
  end)

  local cards = {}
  for _, habit in ipairs(ordered) do
    local seconds = snap.totals[habit.name] or 0
    local share = snap.total > 0 and seconds / snap.total or 0
    table.insert(cards, habitCard(habit, seconds, share, habit.name == liveHabit))
  end
  return cards
end

function render()
  if not isOpen then
    return
  end
  local snap = snapshot(RANGES[rangeIndex].days)
  local statusText, statusColor, liveHabit = status()
  panel.render(ui.column({ padding = 18, gap = 14 }, {
    header(statusText, statusColor),
    confirmingReset and resetConfirm() or rangePicker(),
    summaryCard(snap),
    ui.label({ text = "BREAKDOWN", fontSize = 11, fontWeight = "bold", color = "on_surface_variant" }),
    ui.scroll({ gap = 8, flexGrow = 1 }, breakdown(snap, liveHabit)),
  }))
end

function onOpen()
  isOpen = true
  render()
end

function onClose()
  isOpen = false
  confirmingReset = false
end

noctalia.state.watch("data", function() render() end)
noctalia.state.watch("current", function() render() end)
noctalia.state.watch("paused", function() render() end)
