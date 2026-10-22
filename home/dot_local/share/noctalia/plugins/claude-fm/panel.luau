--!nonstrict
-- Panel: Claude-themed. A header with the name and the status and the dancing
-- mascot on the right, then one row of controls (stop, an orange play/pause
-- pill, open on the web, volume). The mascot animates from frame ticks, and
-- only while the panel is open; nothing else moves.
local common = require("./lib/common.luau")
local choreo = require("./choreo.luau")
local clawd = require("./clawd.luau")

local ANIM_MS = common.frameMs(noctalia.getConfig("fps")) -- 0 = animation off
local PIXEL = 3                     -- the mascot is 60 x 48 px
local MASCOT_INSET = 24             -- px between the mascot and the panel's right padding
local INK = "#1F1B16"               -- dark text/glyph on coral

local isOpen = false
local lastRender = 0
local lastNonZero = 70
local pb = common.playback()

local function statusText()
  if pb.status == "loading" then
    return "Connecting…"
  elseif pb.status == "playing" then
    return "Live"
  elseif pb.status == "paused" then
    return "Paused"
  end
  return "Stopped"
end

local function statusColor()
  if pb.status == "playing" or pb.status == "loading" then
    return common.CLAUDE
  end
  return "on_surface_variant"
end

local function header(now, playing)
  return ui.row({ gap = 12, align = "center" }, {
    ui.column({ gap = 4, flexGrow = 1 }, {
      ui.label({ text = "Claude FM", fontSize = 18, fontWeight = "bold", color = common.CLAUDE }),
      ui.row({ gap = 6, align = "center" }, {
        ui.box({ width = 7, height = 7, radius = 4, fill = statusColor() }),
        ui.label({ text = statusText(), fontSize = 12, color = "on_surface_variant" }),
      }),
    }),
    ui.row({ paddingH = MASCOT_INSET }, { clawd.render(now, playing, PIXEL, ui) }),
  })
end

-- Transport and volume in one row. pb.volume is updated optimistically on
-- change so the knob tracks a drag between state updates.
local function controls(playing)
  local vol = pb.volume
  local glyph = vol == 0 and "volume-off" or (vol < 50 and "volume-2" or "volume")
  return ui.row({ gap = 8, align = "center" }, {
    ui.button({ glyph = "player-stop", variant = "ghost", controlSize = "sm", tooltip = "Stop", onClick = function() common.request("stop") end }),
    ui.column({
      fill = common.CLAUDE,
      radius = 14,
      width = 52,
      height = 36,
      align = "center",
      justify = "center",
      tooltip = playing and "Pause" or "Play",
      onClick = function() common.request("toggle") end,
    }, {
      ui.glyph({ name = playing and "player-pause" or "player-play", size = 20, color = INK }),
    }),
    ui.button({ glyph = "external-link", variant = "ghost", controlSize = "sm", tooltip = "Open on the web", onClick = function() noctalia.runAsync({ "xdg-open", common.SITE_URL }) end }),
    ui.column({
      align = "center",
      justify = "center",
      onClick = function()
        if vol > 0 then
          lastNonZero = vol
          pb.volume = 0
          common.request("set-volume", 0)
        else
          local v = lastNonZero > 0 and lastNonZero or 70
          pb.volume = v
          common.request("set-volume", v)
        end
      end,
    }, {
      ui.glyph({ name = glyph, size = 16, color = "on_surface_variant" }),
    }),
    ui.column({ flexGrow = 1, align = "stretch" }, {
      ui.slider({
        min = 0,
        max = 100,
        step = 1,
        value = vol,
        onChange = function(v)
          local nv = math.floor(tonumber(v) or vol)
          pb.volume = nv
          if nv > 0 then
            lastNonZero = nv
          end
          common.request("set-volume", nv)
        end,
      }),
    }),
    ui.label({ text = tostring(math.floor(vol)) .. "%", fontSize = 12, color = "on_surface_variant", width = 34, textAlign = "end" }),
  })
end

function render()
  if not isOpen then
    return
  end
  local now = noctalia.nowMs()
  lastRender = now
  local playing = pb.status == "playing"
  panel.render(ui.column({ padding = 14, gap = 12, align = "stretch" }, {
    header(now, playing),
    controls(playing),
  }))
end

function update()
  render()
end

-- The host ticks a panel only through frame ticks (setUpdateInterval does not
-- reach panels): re-render once the next frame is due, slowly while the mascot
-- idles and at the animation rate while it dances.
function onFrameTick(_dt)
  if not isOpen then
    return
  end
  local now = noctalia.nowMs()
  if now - lastRender >= choreo.interval(now, pb.status == "playing", ANIM_MS) then
    render()
  end
end

function onOpen()
  isOpen = true
  pb = common.playback()
  if pb.volume > 0 then
    lastNonZero = pb.volume
  end
  panel.setNeedsFrameTick(ANIM_MS > 0)
  render()
end

function onClose()
  isOpen = false
  panel.setNeedsFrameTick(false)
end

noctalia.state.watch("playback", function(_v)
  pb = common.playback()
  if pb.volume > 0 then
    lastNonZero = pb.volume
  end
  render()
end)
