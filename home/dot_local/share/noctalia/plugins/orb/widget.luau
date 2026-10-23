--!nonstrict
-- The orb at home in the bar. When it leaves it squashes and sinks into the bar,
-- leaving a puddle; when it lands it pops back out.
--
--   click        it drips out of the bar and its card grows out of it
--                (while it is out: call it home)
--   right-click  it comes out and stays (while it is out: call it home)
--
-- The bar has no frame ticks, so it ticks on update(): fast while something
-- moves, otherwise just in time for the next blink or glance.

local face = require("./lib/face.luau")
local Life = require("./lib/life.luau")
local motion = require("./lib/motion.luau")
local expression = require("./lib/expression.luau")

local SIZE = noctalia.getConfig("bar_size") or 26
local PACES = { slow = 1.5, normal = 1, fast = 0.6 }
local pace = PACES[noctalia.getConfig("animation_speed")] or 1
local DIVE_MS = 420 * pace
local POP_MS = 480 * pace

local body = noctalia.getConfig("body_color")
local eye = noctalia.getConfig("eye_color")
local rim = face.outline(
  noctalia.getConfig("outline") ~= false,
  noctalia.getConfig("outline_color") or "#ffffff",
  noctalia.getConfig("outline_opacity") or 10
)

local life = Life.new(math.random)
local orbState = noctalia.state.get("orb.state") or "home"
local anim = nil -- { kind = "dive" | "pop", t }
local lastMs = noctalia.nowMs()
local lastSig = ""

-- Hermes, as the service publishes it
local function stateTable(key)
  local v = noctalia.state.get(key)
  return if type(v) == "table" then v else {}
end
local hermesLink = stateTable("orb.hermes.link").status or "unknown"
local hermesActivity = stateTable("orb.hermes.activity")
local hermesNudge = stateTable("orb.hermes.nudge").kind
local clockMs = 0

-- What Hermes is up to, as the orb's expression (no status dots): see lib/expression.
local function currentPose()
  return expression.pose(expression.pick({ link = hermesLink, pet = hermesActivity.pet, nudge = hermesNudge }), clockMs)
end

local function send(cmd)
  noctalia.state.set("orb.cmd", `{cmd}:{noctalia.nowMs()}`)
end

-- The mark it leaves while out: whichever of its colors stands out on the bar.
local function hexOf(color)
  if string.sub(color, 1, 1) == "#" then
    return color
  end
  return noctalia.getColor(color)
end

local function puddleColor()
  local pick = face.contrasting({ hexOf(body), hexOf(eye) }, noctalia.getColor("surface_variant"))
  return face.withAlpha(if pick == 1 then body else eye, 0.85)
end

-- scale, sx, sy for the current animation frame
local function pose()
  if anim ~= nil and anim.kind == "dive" then
    local p = math.clamp(anim.t / DIVE_MS, 0, 1)
    if p < 0.3 then
      local q = p / 0.3
      return 1, 1 + 0.25 * q, 1 - 0.3 * q
    end
    return 1 - motion.easeInCubic((p - 0.3) / 0.7), 1.25, 0.7
  elseif anim ~= nil and anim.kind == "pop" then
    return motion.easeOutBack(math.clamp(anim.t / POP_MS, 0, 1)), 1, 1
  elseif orbState ~= "home" then
    return 0, 1, 1
  end
  return 1, 1, 1
end

local function render()
  local scale, sx, sy = pose()
  local look = { lid = life.lid, lookX = life.lookX, lookY = life.lookY, mood = life.mood, breath = life.breath }
  local dy, z = 0, nil
  if orbState == "home" and anim == nil then
    local p = currentPose()
    look = expression.apply(life, p)
    sx, sy = sx * p.sx, sy * p.sy
    dy, z = p.dy * 0.4, p.z -- the bar has little room to hop in
  end
  local sig = string.format(
    "%s|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%s|%.3f|%.2f",
    orbState, scale, sx, sy, look.lid, look.lookX, look.lookY, look.breath, look.mood, dy, z or -1
  )
  if sig == lastSig then
    return
  end
  lastSig = sig

  local child
  if scale < 0.05 then
    child = ui.box({ key = "puddle", width = SIZE * 0.9, height = 3, radius = 1.5, fill = puddleColor() })
  else
    child = face.render({
      size = SIZE,
      scale = scale,
      sx = sx,
      sy = sy,
      body = body,
      eye = eye,
      lid = look.lid,
      lookX = look.lookX,
      lookY = look.lookY,
      breath = look.breath,
      mood = look.mood,
      rim = rim,
    })
  end
  -- A hop: room under the face lifts it in the centered slot.
  local lift = -dy * SIZE * 2
  child = ui.column({ key = "hop", align = "center" }, {
    child,
    ui.box({ key = "hop-room", width = 1, height = math.max(lift, 0), fill = face.CLEAR, visible = lift > 0.5 }),
  })
  -- Fixed slot so squash, hops and pop never shove the neighbouring widgets. Asleep, a "z"
  -- drifts up from the slot's top-right corner.
  local w, h = SIZE * 1.4, SIZE * 1.2
  local slot = ui.row({ key = "slot", width = w, height = h, align = "center", justify = "center" }, { child })
  if z ~= nil then
    slot = ui.column({ key = "stack", width = w, height = h, gap = -h }, {
      slot,
      ui.row({ key = "marks", width = w, height = h * 0.5, justify = "end", align = "start", paddingH = 1 }, {
        ui.column({ key = "z-col", align = "center" }, {
          ui.box({ key = "z-room", width = 1, height = math.max((1 - z) * h * 0.25, 0), fill = face.CLEAR, visible = z < 0.98 }),
          ui.label({ key = "z", text = "z", fontSize = math.max(7, math.floor(SIZE * 0.3)), fontWeight = "semibold", color = puddleColor(), opacity = math.clamp(1 - z, 0, 1) }),
        }),
      }),
    })
  end
  barWidget.render(slot)
end

function update()
  local t = noctalia.nowMs()
  local dt = math.clamp(t - lastMs, 0, 200)
  lastMs = t
  clockMs += dt
  life:step(dt)
  if anim ~= nil then
    anim.t += dt
    if anim.t >= (if anim.kind == "dive" then DIVE_MS else POP_MS) then
      anim = nil
    end
  end
  render()
  local still = if orbState == "home" then currentPose().nextIn else math.huge
  if anim ~= nil or life:animating() or still == 0 then
    noctalia.setUpdateInterval(33)
  else
    noctalia.setUpdateInterval(math.clamp(math.min(life:nextEventIn(), still), 16, 250))
  end
end

noctalia.state.watch("orb.state", function(s)
  local was = orbState
  orbState = s
  if was == "home" and s ~= "home" then
    anim = { kind = "dive", t = 0 }
  elseif was ~= "home" and s == "home" then
    anim = { kind = "pop", t = 0 }
    life:poke("happy", 1100)
  end
  noctalia.setUpdateInterval(33)
  render()
end)

function onClick()
  send(if orbState == "home" then "card" else "home")
end

function onRightClick()
  send(if orbState == "home" then "out" else "home")
end

function onHover(entered)
  if (entered == true or entered == "true") and orbState == "home" then
    life:poke("happy", 900)
    noctalia.setUpdateInterval(33)
  end
end

local function watchTable(key, apply)
  noctalia.state.watch(key, function(v)
    apply(if type(v) == "table" then v else {})
    noctalia.setUpdateInterval(33)
  end)
end
watchTable("orb.hermes.link", function(v)
  hermesLink = v.status or "unknown"
end)
watchTable("orb.hermes.activity", function(v)
  hermesActivity = v
end)
watchTable("orb.hermes.nudge", function(v)
  hermesNudge = v.kind
end)

local output = barWidget.outputName()
if output ~= nil then
  noctalia.state.set("orb.output", output)
end

-- Draw right away instead of waiting for the first tick.
render()
noctalia.setUpdateInterval(33)
