--!nonstrict
-- The orb out of the bar, after Marea. One layer surface that holds it and
-- moves itself by its own margins; the host creates this runtime on
-- layer.show and destroys it on hide. It never wanders: it stays where it
-- came out, or wherever it is put down.
--
--   emerge   hangs from the bar edge like a drop, the neck thins and snaps,
--            it shakes loose
--   appear   pops back in place: the runtime was reloaded (any settings
--            change does that) while the orb was out
--   idle     sits there: blinks, breathes
--   follow   picked up (double-click): trails the pointer until a click puts
--            it down
--   room     moves just enough for its card to fit on screen
--   opening  the card grows out of it (290 ms), the content follows (90 ms in)
--   open     the card is out; the ball sits in its corner
--   closing  the content goes first (50 ms), then the card folds back in
--   return   floats back under its home point
--   dive     rises to the edge, a neck forms, the bar swallows it
--
-- Input: a click opens the card, a double-click picks it up, so a single click
-- waits out the double-click window first. While it follows, the surface
-- covers the screen with a transparent ui.graph, whose pointer tracking gives
-- the pointer's position on screen; the click that lands anywhere on that
-- surface puts the orb down.
--
-- Comes out with orb.geo from the service: screen size, home point, and the
-- intent - "card" when it came out only to show its card (it goes home when
-- the card closes), "out" to stay out.

local face = require("./lib/face.luau")
local card = require("./lib/card.luau")
local Life = require("./lib/life.luau")
local motion = require("./lib/motion.luau")
local expression = require("./lib/expression.luau")

-- The card's tabs, in order. Each module renders its tab from Hermes state.
local TABS = {
  { id = "chat", glyph = "message-circle", mod = require("./lib/tabs/chat.luau") },
  { id = "chats", glyph = "history", mod = require("./lib/tabs/chats.luau") },
}
local setup = require("./lib/tabs/setup.luau")
local BUBBLE_W = 220
local NUDGE_COLORS = { approval = "#f4b400", unread = "primary" }

-- Sizes are tuned for a 46 px ball and scale with the Size setting (u).
local BALL = noctalia.getConfig("orb_size") or 46
local u = BALL / 46
local BALL_BOX = math.ceil(BALL + 18 * u)
local DRIP_W, DRIP_H = math.ceil(BALL + 26 * u), math.ceil(BALL + 58 * u)
local DRIP_ROOT = 8 -- the neck's root, this far inside the bar
local LAUNCH = 40 * u -- where it hovers below the edge, ball center
local CARD_W = noctalia.getConfig("card_width") or 360
local CARD_H = noctalia.getConfig("card_height") or 260
local CARD_PAD, CARD_INSET, CARD_RADIUS = 24, math.floor(14 * u), 22
local CARD_X = noctalia.getConfig("card_horizontal") -- "auto" | "right" | "left"
local CARD_Y = noctalia.getConfig("card_vertical") -- "auto" | "down" | "up"

-- Durations scale with the Animation speed setting.
local PACES = { slow = 1.5, normal = 1, fast = 0.6 }
local pace = PACES[noctalia.getConfig("animation_speed")] or 1
local HANG_MS, SETTLE_MS = 380 * pace, 460 * pace
local RISE_MS, SINK_MS = 260 * pace, 280 * pace
local POP_MS, SLIDE_MS = 520 * pace, 360 * pace -- side bars: no drip
local OPEN_MS, CONTENT_DELAY_MS, CONTENT_MS = 290 * pace, 90 * pace, 200 * pace
local CLOSE_FADE_MS, CLOSE_DELAY_MS, CLOSE_MS = 50 * pace, 30 * pace, 210 * pace
local GULP_MS = 450 * pace
local APPEAR_MS = 260 * pace
-- Out for the card (a bar click): a quick drip and a short dash to where the card fits.
local QUICK_HANG_MS, QUICK_SETTLE_MS, QUICK_POP_MS = 140 * pace, 170 * pace, 240 * pace
local ROOM_MAX_MS, QUICK_ROOM_MS = 900, 300 * pace
local quickRoom = false -- this card was opened from the bar
local RETURN_SPEED, ROOM_SPEED = 420, 600

local FOLLOW_SETTLE_MS = 80 -- pointer moves right after the surface grows are stale
local FOLLOW_LOST_MS = 2500 -- no pointer at all since pickup: tracking failed, put it down
local FOLLOW_IDLE_MS = 30000 -- pointer still this long while it follows: put it down
local FOLLOW_SNAPS = { loose = 8, normal = 18, tight = 32 } -- how quickly it catches up (1/s)
local FOLLOW_SNAP = FOLLOW_SNAPS[noctalia.getConfig("follow_speed")] or 18
local DOUBLE_CLICK_MS = noctalia.getConfig("double_click_ms") or 320
local REMEMBER = noctalia.getConfig("remember_position") ~= false

local body = noctalia.getConfig("body_color")
local eye = noctalia.getConfig("eye_color")
local rim = face.outline(
  noctalia.getConfig("outline") ~= false,
  noctalia.getConfig("outline_color") or "#ffffff",
  noctalia.getConfig("outline_opacity") or 10
)
-- The card has its own color (a surface role by default) and the theme's text colors, so
-- Hermes' markdown replies, which always use the theme text color, stay readable.
local cardFill = noctalia.getConfig("card_color") or "surface_variant"
local colors = {
  ink = "on_surface",
  muted = "on_surface_variant",
  soft = "on_surface/0.08",
  tile = "surface",
  accent = "primary",
  onAccent = "on_primary",
}

local geo = noctalia.state.get("orb.geo")
  or { w = 1920, h = 1080, edge = "top", thickness = 40, homeX = 960, homeY = 40, intent = "out" }
local intent = geo.intent or "out"
local vertical = geo.edge == "top" or geo.edge == "bottom"
local outX, outY = motion.outward(geo.edge)
local bounds = motion.roamBounds(geo.edge, geo.thickness, geo.w, geo.h, BALL_BOX / 2 + 2)
local launchX, launchY = geo.homeX + outX * LAUNCH, geo.homeY + outY * LAUNCH

-- Where it was last put down, kept across restarts in the plugin's data dir.
local POSITION_FILE = (noctalia.pluginDataDir() or noctalia.pluginDir()) .. "/position.json"

local function savedPosition()
  if not REMEMBER then
    return nil
  end
  local raw = noctalia.readFile(POSITION_FILE)
  if raw == nil then
    return nil
  end
  return motion.restorePoint(noctalia.json.decode(raw), geo.w, geo.h, bounds)
end

local life = Life.new(math.random)
local phase = "emerge"
local phaseT = 0
local gulpT = GULP_MS

local x, y = geo.homeX, geo.homeY -- ball center, screen coordinates
local vx, vy = 0, 0
local follow = nil -- { tx, ty, at, movedAt, seen }: where the pointer is, while it follows
local gotoX, gotoY = 0, 0 -- where it floats to on its way to the remembered spot
local pendingClick = nil -- when a first click landed that may still become a double

-- what this frame draws
local scale, sx, sy, neckW = 0, 1, 1, 0
local look = { lid = 1, lookX = 0, lookY = 0, mood = "normal", breath = 0 } -- Life + expression
local hopY, sleepZ = 0, nil -- expression: hop (ball heights, up < 0), sleeping "z" (0..1)
local lay = nil -- motion.cardLayout while the card is out
local cardP, contentP = 0, 0
local afterClose = "idle"

local surf = { mode = nil, w = 0, h = 0, left = 0, top = 0 }
local lastSig = ""
local clockMs = 0

-- ── Hermes, as the service publishes it (orb.hermes.*) ───────────────────────

local function stateTable(key)
  local v = noctalia.state.get(key)
  return if type(v) == "table" then v else {}
end

local hermes = {
  link = stateTable("orb.hermes.link").status or "unknown",
  linkDetail = stateTable("orb.hermes.link").detail,
  activity = stateTable("orb.hermes.activity"),
  chat = stateTable("orb.hermes.chat"),
  lists = stateTable("orb.hermes.lists"),
  models = stateTable("orb.hermes.models"),
  nudge = stateTable("orb.hermes.nudge").kind,
  tab = noctalia.state.get("orb.hermes.tab") or "chat",
}
local hermesRev = 0 -- bumped on every change, part of the render signature
local inputKey = 0 -- a fresh key empties the chat input after sending
local draft = "" -- the chat input's text, for the send button and / suggestions
local inputSeed = "" -- what a fresh input starts with (a picked / command)
local pickerOpen, reopenAfterPick = false, false -- the card steps aside for the file chooser
local modelPicker = false -- the chat's model list, in place of the messages
local modelSections = {} -- provider slug -> true/false once opened or closed by hand
local modelShowAll = false -- providers you did not set up, listed too
local confirmDelete = nil -- the chat whose delete button was tapped once
local openThinking = {} -- message index (or "live") -> true while its thinking is shown
local thinkingSession = nil -- openThinking belongs to this chat
local facePet = nil

local function watchHermes(key, apply)
  noctalia.state.watch(key, function(value)
    apply(if type(value) == "table" then value else {})
    hermesRev += 1
  end)
end

watchHermes("orb.hermes.link", function(v)
  hermes.link = v.status or "unknown"
  hermes.linkDetail = v.detail
end)
watchHermes("orb.hermes.activity", function(v)
  hermes.activity = v
end)
local BUSY = { sending = true, thinking = true, tool = true, waiting = true }
watchHermes("orb.hermes.chat", function(v)
  local wasBusy = BUSY[hermes.chat.status or ""] == true
  hermes.chat = v
  if v.sessionId ~= thinkingSession then
    thinkingSession, openThinking = v.sessionId, {}
  elseif wasBusy and not BUSY[v.status or ""] and openThinking.live then
    -- watching it think when the reply landed: keep watching, on the reply
    openThinking.live = nil
    openThinking[#(v.messages or {})] = true
  end
end)
watchHermes("orb.hermes.lists", function(v)
  hermes.lists = v
end)
watchHermes("orb.hermes.models", function(v)
  hermes.models = v
end)
-- "/model" without a model opens the picker
noctalia.state.watch("orb.hermes.pickmodel", function()
  modelPicker = true
  hermesRev += 1
end)
noctalia.state.watch("orb.hermes.tab", function(id)
  if type(id) == "string" and id ~= hermes.tab then
    hermes.tab = id
    hermesRev += 1
  end
end)
watchHermes("orb.hermes.nudge", function(v)
  hermes.nudge = v.kind
end)

local function hermesCmd(verb, args)
  noctalia.state.set("orb.hermes.cmd", `{verb}:{noctalia.nowMs()}:{if args ~= nil then noctalia.json.encode(args) else ""}`)
end

local function selectTab(id)
  hermes.tab = id
  confirmDelete = nil
  hermesRev += 1
  hermesCmd("tab", { id = id })
end

-- Callbacks the tabs use. Tabs re-render only when the signature changes, so closures are fine.
local function sendText(text)
  text = text or ""
  if string.match(text, "%S") or #(hermes.chat.pending or {}) > 0 then
    inputKey += 1 -- a fresh, empty input
    draft, inputSeed = "", ""
    modelPicker = false
    hermesRev += 1
    hermesCmd("send", { text = text })
  end
end

local function slashMode(text)
  return string.match(text, "^/%S*$") ~= nil
end

local tabCb = {
  cmd = hermesCmd,
  send = sendText,
  draft = function(text)
    text = text or ""
    -- the input owns its text; re-render only while / suggestions follow it
    local redraw = slashMode(text) or slashMode(draft)
    draft = text
    if redraw then
      hermesRev += 1
    end
  end,
  sendDraft = function()
    sendText(draft)
  end,
  fill = function(text)
    inputKey += 1 -- a new input, seeded and focused
    inputSeed, draft = text, text
    hermesRev += 1
  end,
  stop = function()
    hermesCmd("stop")
  end,
  new = function()
    hermesCmd("new")
  end,
  approve = function(choice)
    hermesCmd("approve", { choice = choice })
  end,
  models = function()
    modelPicker = not modelPicker
    if modelPicker and hermes.models.status ~= "ready" then
      hermesCmd("models")
    end
    hermesRev += 1
  end,
  -- pick(nil) is Hermes' default, locked as the provider and model it is now
  pickModel = function(pick)
    local default = hermes.models.default
    if pick == nil and default ~= nil then
      pick = { provider = default.provider, model = default.model, default = true }
    end
    modelPicker = false
    hermesRev += 1
    if pick ~= nil then
      hermesCmd("set-model", pick)
    end
  end,
  toggleProvider = function(slug, open)
    modelSections[slug] = not open
    hermesRev += 1
  end,
  showAllModels = function()
    modelShowAll = true
    hermesRev += 1
  end,
  -- Chats: the trash button asks, Delete deletes, anything else cancels
  askDelete = function(id)
    confirmDelete = id
    hermesRev += 1
  end,
  cancelDelete = function()
    confirmDelete = nil
    hermesRev += 1
  end,
  deleteChat = function(id)
    confirmDelete = nil
    hermesRev += 1
    hermesCmd("delete-chat", { id = id })
  end,
  toggleThinking = function(key)
    openThinking[key] = not openThinking[key] or nil
    hermesRev += 1
  end,
}

-- One global per tab: card tab buttons call them by name.
function onTab_chat() selectTab("chat") end
function onTab_chats() selectTab("chats") end

-- The keyboard. niri gives an on-demand layer the keys the way it gives them to a window:
-- when it is clicked, when it maps, and (focus-follows-mouse) when the pointer moves onto
-- it; a click or the pointer elsewhere takes them back. So the orb is on demand while the
-- pointer is on it (the click that opens the card hands the card the keys) and while the
-- card is out, and takes no keys otherwise, so a roaming orb never holds the keyboard.
-- (Exclusive would keep the keys from every window until the card closes.)
local keys = { card = intent == "card", hover = false, mode = nil }

local function syncKeys()
  local want = if keys.card or keys.hover then "on_demand" else "none"
  if want ~= keys.mode then
    keys.mode = want
    noctalia.layer.configure("roamer", { keyboard = want })
  end
end

-- The service polls faster while the card is out.
local function cardOpened()
  if hermes.nudge == "approval" or hermes.nudge == "unread" then
    selectTab("chat")
  end
  keys.card = true
  syncKeys()
  hermesCmd("open", { open = true })
end

local function cardClosed()
  keys.card = false
  syncKeys()
  modelPicker, modelShowAll, confirmDelete = false, false, nil
  hermesCmd("open", { open = false })
end

function onExit(_signal, _reason)
  hermesCmd("open", { open = false })
end

-- The host keeps a layer's configuration across hide/show, so a runtime destroyed with
-- its card open (sent home mid-close) would leave the next one taking keys. Start clean:
-- on demand only when coming out for the card (the service maps it so, and niri hands a
-- newly mapped on-demand layer the keys).
syncKeys()
hermesCmd("open", { open = false })

-- noctalia msg plugin shadow/orb:roamer all tab <chat|chats>
function onIpc(event, payload)
  if event == "tab" and payload ~= nil then
    for _, t in TABS do
      if t.id == payload then
        selectTab(payload)
      end
    end
  end
end

local function setPhase(p)
  phase = p
  phaseT = 0
  if p ~= "room" then
    quickRoom = false -- it only speeds up the dash to the card
  end
  -- Where it is, for a reloaded runtime to carry on from (see the bottom).
  if p ~= "emerge" and p ~= "dive" and p ~= "gone" then
    noctalia.state.set("orb.spot", { x = x, y = y })
  end
end

local function easeInOut(p)
  return 0.5 - math.cos(p * math.pi) / 2
end

local function send(cmd)
  noctalia.state.set("orb.cmd", `{cmd}:{noctalia.nowMs()}`)
end

-- ── the card ─────────────────────────────────────────────────────────────────

local function cardOut()
  return phase == "room" or phase == "opening" or phase == "open" or phase == "closing"
end

local function openCard()
  -- Lay the card out in the screen minus the bar, so it never covers the bar.
  local ox = if geo.edge == "left" then geo.thickness else 0
  local oy = if geo.edge == "top" then geo.thickness else 0
  local aw = geo.w - (if vertical then 0 else geo.thickness)
  local ah = geo.h - (if vertical then geo.thickness else 0)
  lay = motion.cardLayout(x - ox, y - oy, CARD_W, CARD_H, CARD_PAD, CARD_INSET, aw, ah, CARD_X, CARD_Y)
  lay.left += ox
  lay.top += oy
  lay.ballX += ox
  lay.ballY += oy
  cardP, contentP = 0, 0
  life:poke("happy", 900)
  cardOpened()
  if math.abs(lay.ballX - x) > 1.5 or math.abs(lay.ballY - y) > 1.5 then
    setPhase("room")
  else
    setPhase("opening")
  end
end

local function closeCard(next)
  afterClose = next
  if phase == "room" then
    lay = nil -- nothing grown yet
    cardClosed()
    setPhase(next)
  elseif phase == "opening" or phase == "open" then
    setPhase("closing")
  end
end

noctalia.state.watch("orb.hermes.picker", function(v)
  pickerOpen = type(v) == "table" and v.open == true
  if pickerOpen and (phase == "opening" or phase == "open") then
    reopenAfterPick = true
    closeCard("idle") -- stays out; the frame loop brings the card back after
  end
end)

-- After the card: home if it only came out for the card, otherwise stay put.
local function defaultAfter()
  return if intent == "card" then "return" else "idle"
end

-- ── input ────────────────────────────────────────────────────────────────────
-- Callbacks are named globals: the tree re-renders every frame.

local function startFollow()
  local now = noctalia.nowMs()
  follow = { tx = x, ty = y, at = now, movedAt = now, seen = false }
  life:poke("happy", 1200)
  setPhase("follow")
end

local function putDown()
  follow = nil
  gulpT = 0 -- set down with a little shake
  setPhase("idle")
  if REMEMBER then
    local data = noctalia.json.encode({ x = math.floor(x), y = math.floor(y), w = geo.w, h = geo.h })
    if data ~= nil then
      noctalia.writeFile(POSITION_FILE, data)
    end
  end
end

function onOrbClick()
  if phase == "idle" then
    local now = noctalia.nowMs()
    if pendingClick ~= nil and now - pendingClick <= DOUBLE_CLICK_MS then
      pendingClick = nil
      startFollow()
    else
      pendingClick = now -- the card opens once the double-click window passes
    end
  elseif phase == "opening" or phase == "open" or phase == "room" then
    closeCard(defaultAfter())
  end
end

function onOrbHover(state)
  if state == "true" and phase == "idle" then
    life:poke("surprised", 700)
  end
  -- on demand under the pointer, so the click that opens the card gives it the keys
  keys.hover = state == "true"
  syncKeys()
end

-- While it follows: the graph covering the screen reports the pointer.
function onFollowMove(nx, ny)
  if follow == nil then
    return
  end
  local now = noctalia.nowMs()
  if now - follow.at < FOLLOW_SETTLE_MS then
    return
  end
  follow.tx, follow.ty = motion.clampPoint(tonumber(nx) * geo.w, tonumber(ny) * geo.h, bounds)
  follow.movedAt = now
  follow.seen = true
end

-- Any click on the screen-covering surface puts it down.
function onFollowClick()
  if follow ~= nil then
    x, y = follow.tx, follow.ty
    putDown()
  end
end

function onCardPrimary()
  if intent == "card" then
    intent = "out" -- stay out instead of going home
    closeCard("idle")
  else
    send("home")
    closeCard("return")
  end
end

function onCardSettings()
  closeCard(defaultAfter())
  noctalia.openSettings()
end

function onCardClose()
  closeCard(defaultAfter())
end

noctalia.state.watch("orb.state", function(s)
  if s ~= "returning" then
    return
  end
  if phase == "room" or phase == "opening" or phase == "open" then
    closeCard("return")
  elseif phase == "closing" then
    afterClose = "return"
  elseif phase == "emerge" then
    -- afterEmerge sends it home once it is out
  elseif phase ~= "return" and phase ~= "dive" and phase ~= "gone" then
    -- idle, follow, goto, appear
    follow = nil
    scale = 1
    setPhase("return")
  end
end)

noctalia.state.watch("orb.open", function()
  if phase == "idle" then
    quickRoom = true -- a bar click, while it is already out
    openCard()
  end
end)

-- ── the surface ──────────────────────────────────────────────────────────────

-- Size and place the layer surface; returns where it actually went (clamped).
local function setSurface(mode, w, h, left, top)
  left = math.clamp(math.floor(left + 0.5), 0, math.max(0, geo.w - w))
  top = math.clamp(math.floor(top + 0.5), 0, math.max(0, geo.h - h))
  if surf.mode ~= mode or surf.w ~= w or surf.h ~= h then
    surf.mode, surf.w, surf.h, surf.left, surf.top = mode, w, h, left, top
    noctalia.layer.configure("roamer", { width = w, height = h, margins = { top = top, left = left } })
    lastSig = ""
  elseif left ~= surf.left or top ~= surf.top then
    surf.left, surf.top = left, top
    noctalia.layer.configure("roamer", { margins = { top = top, left = left } })
  end
  return left, top
end

-- outlined: whether the ball draws its own outline (not inside the card,
-- which outlines ball and card together).
local function ball(outlined)
  return face.render({
    size = BALL,
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
    rim = if outlined then rim else nil,
    onClick = "onOrbClick",
    onHover = "onOrbHover",
  })
end

local function ballSize()
  local s = BALL * scale * (1 + 0.04 * life.breath)
  return s * sx, s * sy
end

local function clear(key, w, h)
  return ui.box({ key = key, width = math.max(w, 0), height = math.max(h, 0), fill = face.CLEAR, visible = w > 0.5 and h > 0.5 })
end

-- The ball placed at (lx, ly) in a w x h layer.
local function ballLayer(w, h, lx, ly, bw, bh)
  return ui.column({ key = "ballL", width = w, height = h, align = "start" }, {
    clear("ball-t", 1, ly - bh / 2),
    ui.row({ key = "ball-r", align = "start" }, { clear("ball-l", lx - bw / 2, 1), ball(true) }),
  })
end

-- What the orb says while it sits out with its card closed, like Hermes' own pet.
local function bubbleText()
  local st = hermes.chat.status
  if st == "waiting" then
    return noctalia.tr("hermes.bubble.waiting")
  elseif st == "tool" then
    return noctalia.tr("hermes.bubble.working")
  elseif st == "thinking" or st == "sending" then
    return noctalia.tr("hermes.bubble.thinking")
  end
  return nil
end

local function bubbleSide()
  return if x + BALL_BOX / 2 + BUBBLE_W + 8 > geo.w then "left" else "right"
end

-- Sitting: the ball (which takes its own clicks), asleep a "z" drifting up from its corner,
-- and maybe a speech bubble beside it.
local function floatTree(lx, ly, bw, bh, text)
  local ballBox = ballLayer(BALL_BOX, BALL_BOX, lx, ly, bw, bh)
  if sleepZ ~= nil then
    local room = math.max(ly - bh / 2, 8) -- above the ball, so it never covers the ball's clicks
    ballBox = ui.column({ key = "ballbox", width = BALL_BOX, height = BALL_BOX, gap = -BALL_BOX }, {
      ballBox,
      ui.row({ key = "marks", width = BALL_BOX, height = room, justify = "end", align = "start", paddingH = 4 }, {
        ui.column({ key = "z-col", align = "center" }, {
          clear("z-room", 1, (1 - sleepZ) * room * 0.6),
          ui.label({ key = "z", text = "z", fontSize = math.max(9, math.floor(bh * 0.28)), fontWeight = "semibold", color = body, opacity = math.clamp(1 - sleepZ, 0, 1) }),
        }),
      }),
    })
  end
  if text == nil then
    return ballBox
  end
  local bubble = ui.row({ key = "bubble-area", width = BUBBLE_W, height = BALL_BOX, align = "center", justify = if bubbleSide() == "right" then "start" else "end" }, {
    ui.column({ key = "bubble", fill = "surface", radius = 12, paddingH = 10, paddingV = 6 }, {
      ui.label({ key = "bubble-t", text = text, fontSize = 12, color = "on_surface", maxWidth = BUBBLE_W - 24, maxLines = 2 }),
    }),
  })
  local row = if bubbleSide() == "right" then { ballBox, bubble } else { bubble, ballBox }
  return ui.row({ key = "float-row", align = "center" }, row)
end

-- Following: the surface covers the screen; a transparent graph on top tracks
-- the pointer, and a click anywhere falls through it to the clickable root.
local function followTree(lx, ly, bw, bh)
  return ui.column({ key = "follow", width = geo.w, height = geo.h, align = "start", gap = -geo.h, onClick = "onFollowClick" }, {
    ballLayer(geo.w, geo.h, lx, ly, bw, bh),
    ui.graph({
      key = "tracker",
      width = geo.w,
      height = geo.h,
      values = {},
      color = face.CLEAR,
      fillOpacity = 0,
      lineWidth = 0,
      onPointerMove = "onFollowMove",
    }),
  })
end

-- The header says only whether Hermes is reachable; what it is doing shows in the chat.
local function cardStatus()
  return noctalia.tr("hermes.status." .. hermes.link)
end

local function cardContent()
  -- No key (or a rejected one): the card is one setup screen, without tabs.
  if hermes.link == "auth" then
    return card.content({
      flipX = lay.flipX,
      ballRoom = math.floor(30 * u),
      width = CARD_W - 36,
      title = noctalia.tr("card.title"),
      status = cardStatus(),
      statusWidth = CARD_W - 36 - math.floor(30 * u) - 3 * 30 - 2 * 6 - 2 * 10 - 13,
      link = hermes.link,
      primaryGlyph = if intent == "card" then "pin" else "home",
      onPrimary = "onCardPrimary",
      onSettings = "onCardSettings",
      onClose = "onCardClose",
      tabs = {},
      body = setup.render({ linkDetail = hermes.linkDetail }),
      colors = colors,
      opacity = contentP,
    })
  end
  local tabs, mod = {}, TABS[1].mod
  for _, t in TABS do
    local dot = nil
    if t.id == "chat" and (hermes.nudge == "approval" or hermes.nudge == "unread") then
      dot = NUDGE_COLORS[hermes.nudge]
    end
    table.insert(tabs, { id = t.id, glyph = t.glyph, label = noctalia.tr("tabs." .. t.id), dot = dot })
    if t.id == hermes.tab then
      mod = t.mod
    end
  end
  local tabBody = mod.render({
    chat = hermes.chat,
    link = hermes.link,
    linkDetail = hermes.linkDetail,
    activity = hermes.activity,
    lists = hermes.lists,
    models = hermes.models,
    modelPicker = modelPicker,
    modelSections = modelSections,
    modelShowAll = modelShowAll,
    confirmDelete = confirmDelete,
    openThinking = openThinking,
    width = CARD_W - 36, -- inside the card's padding
    inputKey = inputKey,
    inputSeed = inputSeed,
    draft = draft,
    cb = tabCb,
  })
  return card.content({
    flipX = lay.flipX,
    ballRoom = math.floor(30 * u),
    width = CARD_W - 36,
    title = noctalia.tr("card.title"),
    status = cardStatus(),
    statusWidth = CARD_W - 36 - math.floor(30 * u) - 3 * 30 - 2 * 6 - 2 * 10 - 13, -- header row minus ball room, buttons, gaps, dot
    link = hermes.link,
    primaryGlyph = if intent == "card" then "pin" else "home",
    onPrimary = "onCardPrimary",
    onSettings = "onCardSettings",
    onClose = "onCardClose",
    tabs = tabs,
    activeTab = hermes.tab,
    body = tabBody,
    colors = colors,
    opacity = contentP,
  })
end

local function render()
  local bw, bh = ballSize()
  local mode
  if cardOut() and phase ~= "room" then
    mode = "card"
  elseif (phase == "emerge" or phase == "dive") and vertical then
    mode = "drip"
  elseif phase == "follow" then
    mode = "follow"
  else
    mode = "float"
  end

  local left, top
  if mode == "card" then
    left, top = setSurface(mode, lay.sw, lay.sh, lay.left, lay.top)
  elseif mode == "drip" then
    local t0 = if geo.edge == "top" then geo.homeY - DRIP_ROOT else geo.homeY + DRIP_ROOT - DRIP_H
    left, top = setSurface(mode, DRIP_W, DRIP_H, geo.homeX - DRIP_W / 2, t0)
  elseif mode == "follow" then
    left, top = setSurface(mode, geo.w, geo.h, 0, 0)
  end
  local text = if mode == "float" and (phase == "idle" or phase == "goto") then bubbleText() else nil
  if mode == "float" and text ~= nil then
    local side = bubbleSide()
    mode = "float-" .. side
    left, top = setSurface(mode, BALL_BOX + BUBBLE_W, BALL_BOX, x - BALL_BOX / 2 - (if side == "left" then BUBBLE_W else 0), y - BALL_BOX / 2)
  elseif mode == "float" then
    left, top = setSurface(mode, BALL_BOX, BALL_BOX, x - BALL_BOX / 2, y - BALL_BOX / 2)
  end
  local lx, ly = x - left, y - top
  if string.sub(mode, 1, 5) == "float" then
    ly += hopY * bh -- the expression's hop, inside the ball's box
  end
  if mode == "float-left" then
    lx -= BUBBLE_W -- the ball sits after the bubble
  end

  local sig = string.format(
    "%s|%.1f|%.1f|%.1f|%.1f|%.1f|%.1f|%.2f|%.2f|%.2f|%.2f|%.2f|%s|%s|%s|%s",
    mode, bw, bh, lx, ly, neckW, cardP * 100, contentP, look.lid, look.lookX, look.lookY, look.breath, look.mood,
    intent, phase, tostring(noctalia.state.get("orb.state"))
  ) .. `|{hermesRev}|{text or ""}`
  if sig == lastSig then
    return
  end
  lastSig = sig

  if mode == "card" then
    local cx, cy, cw, ch = motion.cardRect(lay, CARD_W, CARD_H, CARD_PAD, CARD_INSET, cardP)
    layer.render(card.scene({
      lay = lay,
      x = cx,
      y = cy,
      w = cw,
      h = ch,
      radius = math.min(CARD_RADIUS, math.min(cw, ch) / 2),
      fill = cardFill,
      rim = rim,
      shadow = cardP,
      ball = ball(false),
      bw = bw,
      bh = bh,
      content = if contentP > 0.01 then cardContent() else nil,
    }))
  elseif mode == "drip" then
    -- The neck runs from the bar edge to the ball's center, drawn under the ball.
    -- No outline here: the ball's would cut across the neck.
    local neckFill = if neckW > 0.5 then body else face.CLEAR
    local nw = math.max(neckW, 1)
    if geo.edge == "top" then
      layer.render(ui.column({ key = "drip", width = DRIP_W, height = DRIP_H, align = "center", gap = -bh / 2 }, {
        ui.box({ key = "neck", width = nw, height = math.max(ly, 1), radius = nw / 2, fill = neckFill }),
        ball(false),
      }))
    else
      local neckH = math.max(DRIP_H - ly, 1)
      layer.render(ui.column({ key = "drip", width = DRIP_W, height = DRIP_H, align = "center" }, {
        clear("lead", 1, math.max(ly, 1)),
        ui.column({ key = "drop", align = "center", gap = -(neckH + bh / 2) }, {
          ui.box({ key = "neck", width = nw, height = neckH, radius = nw / 2, fill = neckFill }),
          ball(false),
        }),
      }))
    end
  elseif mode == "follow" then
    layer.render(followTree(lx, ly, bw, bh))
  else
    layer.render(floatTree(lx, ly, bw, bh, text))
  end
end

-- ── phases ───────────────────────────────────────────────────────────────────

local function afterEmerge()
  x, y = launchX, launchY
  if noctalia.state.get("orb.state") == "returning" then
    setPhase("return") -- called home while it was still coming out
    return
  end
  if intent == "card" then
    openCard()
    return
  end
  local sx0, sy0 = savedPosition()
  if sx0 ~= nil then
    gotoX, gotoY = sx0, sy0
    setPhase("goto") -- back to where it was put last time
  else
    setPhase("idle")
  end
end

local function stepEmerge()
  local quick = intent == "card"
  local hangMs = if quick then QUICK_HANG_MS else HANG_MS
  local settleMs = if quick then QUICK_SETTLE_MS else SETTLE_MS
  if not vertical then
    -- a side bar: no drip, a plain pop
    local p = math.clamp(phaseT / (if quick then QUICK_POP_MS else POP_MS), 0, 1)
    local e = motion.easeOutCubic(p)
    scale = motion.easeOutBack(p)
    x = geo.homeX + (launchX - geo.homeX) * e
    y = geo.homeY + (launchY - geo.homeY) * e
    if p >= 1 then
      afterEmerge()
    end
    return
  end

  if phaseT < hangMs then
    -- hanging from the edge, pulled long, the neck thinning
    local p = phaseT / hangMs
    local e = easeInOut(p)
    scale = 0.55 + 0.45 * motion.easeOutCubic(p)
    x = geo.homeX
    y = geo.homeY + outY * (-6 + 36 * e) * u
    local stretch = 0.11 * math.sin(p * math.pi)
    sx, sy = 1 - stretch * 0.6, 1 + stretch
    neckW = BALL * 0.8 * (1 - p) + 5 * p
  elseif phaseT < hangMs + settleMs then
    -- snapped: falls the last bit and shakes loose
    local t = phaseT - hangMs
    scale = 1
    local p = math.clamp(t / 160, 0, 1)
    y = geo.homeY + outY * (30 * u + (LAUNCH - 30 * u) * motion.easeOutCubic(p))
    local j = motion.jiggle(t / pace)
    sx, sy = 1 - j * 0.8, 1 + j
  else
    afterEmerge()
  end
end

local function stepDive()
  if not vertical then
    local p = math.clamp(phaseT / SLIDE_MS, 0, 1)
    local e = motion.easeInCubic(p)
    x = launchX + (geo.homeX - launchX) * e
    y = launchY + (geo.homeY - launchY) * e
    scale = 1 - e
  elseif phaseT < RISE_MS then
    -- rises to the edge; the water reaches down for it
    local p = phaseT / RISE_MS
    local e = easeInOut(p)
    x = geo.homeX
    y = launchY + (geo.homeY + outY * 24 * u - launchY) * e
    neckW = 5 + (BALL * 0.5 - 5) * p
    sx, sy = 1 - 0.05 * p, 1 + 0.08 * p
  else
    -- swallowed: the neck widens and the bar drinks it
    local p = math.clamp((phaseT - RISE_MS) / SINK_MS, 0, 1)
    local e = motion.easeInCubic(p)
    y = geo.homeY + outY * (24 - 34 * e) * u
    scale = 1 - 0.8 * e
    neckW = BALL * (0.5 + 0.3 * p) * scale
    sx, sy = 0.95 - 0.1 * e, 1.08 + 0.1 * e
  end
  if phaseT >= (if vertical then RISE_MS + SINK_MS else SLIDE_MS) then
    setPhase("gone")
    scale = 0
    layer.setNeedsFrameTick(false)
    noctalia.state.set("orb.landed", noctalia.nowMs())
  end
end

-- Flying home, making room for the card, or going to the remembered spot.
local function stepTravel(dt)
  local gx, gy, speed = launchX, launchY, RETURN_SPEED
  local roomMax = ROOM_MAX_MS
  if phase == "room" then
    gx, gy, speed = lay.ballX, lay.ballY, ROOM_SPEED
    if intent == "card" or quickRoom then
      speed, roomMax = ROOM_SPEED * 2.5, QUICK_ROOM_MS
    end
  elseif phase == "goto" then
    gx, gy, speed = gotoX, gotoY, ROOM_SPEED
  end
  x, y, vx, vy = motion.steer(x, y, vx, vy, gx, gy, dt, speed, 6)
  if motion.arrived(x, y, vx, vy, gx, gy) or (phase == "room" and phaseT > roomMax) then
    x, y, vx, vy = gx, gy, 0, 0
    if phase == "room" then
      setPhase("opening")
    elseif phase == "goto" then
      gulpT = 0
      setPhase("idle")
    else
      setPhase("dive")
    end
  end
  local v = math.sqrt(vx * vx + vy * vy)
  if v > 20 then
    life:aim(vx / v, vy / v * 0.7, 300)
    local f = math.clamp(v / RETURN_SPEED, 0, 1)
    if math.abs(vx) >= math.abs(vy) then
      sx, sy = 1 + 0.10 * f, 1 - 0.07 * f
    else
      sx, sy = 1 - 0.07 * f, 1 + 0.10 * f
    end
  end
end

-- Trails the pointer, leaning and looking where it goes.
local function stepFollow(dt)
  local now = noctalia.nowMs()
  if (not follow.seen and now - follow.at > FOLLOW_LOST_MS) or now - follow.movedAt > FOLLOW_IDLE_MS then
    putDown() -- never leave the screen covered
    return
  end
  local k = 1 - math.exp(-FOLLOW_SNAP * dt)
  local nx, ny = x + (follow.tx - x) * k, y + (follow.ty - y) * k
  vx, vy = (nx - x) / math.max(dt, 0.001), (ny - y) / math.max(dt, 0.001)
  x, y = nx, ny
  local v = math.sqrt(vx * vx + vy * vy)
  if v > 20 then
    life:aim(vx / v, vy / v * 0.7, 300)
    local f = math.clamp(v / 900, 0, 1)
    if math.abs(vx) >= math.abs(vy) then
      sx, sy = 1 + 0.12 * f, 1 - 0.08 * f
    else
      sx, sy = 1 - 0.08 * f, 1 + 0.12 * f
    end
  end
end

local function stepCard()
  if phase == "opening" then
    cardP = motion.easeOutCubic(math.clamp(phaseT / OPEN_MS, 0, 1))
    contentP = math.clamp((phaseT - CONTENT_DELAY_MS) / CONTENT_MS, 0, 1)
    if phaseT >= math.max(OPEN_MS, CONTENT_DELAY_MS + CONTENT_MS) then
      setPhase("open")
    end
  elseif phase == "open" then
    cardP, contentP = 1, 1
  elseif phase == "closing" then
    contentP = 1 - math.clamp(phaseT / CLOSE_FADE_MS, 0, 1)
    cardP = 1 - motion.easeInCubic(math.clamp((phaseT - CLOSE_DELAY_MS) / CLOSE_MS, 0, 1))
    if phaseT >= CLOSE_DELAY_MS + CLOSE_MS then
      lay = nil
      cardP, contentP = 0, 0
      cardClosed()
      gulpT = 0 -- it swallows the card
      local returning = noctalia.state.get("orb.state") == "returning"
      setPhase(if afterClose == "return" or returning then "return" else "idle")
    end
  end
end

-- Hermes' state on the face (lib/expression), in place of status dots: asleep while Hermes
-- is out of reach, lively once connected, its own look for thinking, working, needing you
-- and the rest. Hops and the sleeping "z" only while it sits; travel keeps its own shape.
local function applyExpression()
  local p = expression.pose(expression.pick({ link = hermes.link, pet = hermes.activity.pet, nudge = hermes.nudge }), clockMs)
  look = expression.apply(life, p)
  hopY, sleepZ = 0, nil
  if phase == "idle" or phase == "open" or phase == "opening" then
    sx, sy = sx * p.sx, sy * p.sy
  end
  if phase == "idle" then
    hopY, sleepZ = p.dy, p.z
  end
end

local function frame(dtMs, draw)
  local dt = dtMs / 1000
  phaseT += dtMs
  gulpT += dtMs
  clockMs += dtMs
  life:step(dtMs)
  sx, sy, neckW = 1, 1, 0
  if pendingClick ~= nil and noctalia.nowMs() - pendingClick > DOUBLE_CLICK_MS then
    pendingClick = nil
    if phase == "idle" then
      openCard()
    end
  end

  if phase == "emerge" then
    stepEmerge()
  elseif phase == "appear" then
    scale = motion.easeOutBack(math.clamp(phaseT / APPEAR_MS, 0, 1))
    if phaseT >= APPEAR_MS then
      setPhase("idle")
    end
  elseif phase == "dive" then
    stepDive()
  elseif phase == "return" or phase == "room" or phase == "goto" then
    scale = 1
    stepTravel(dt)
  elseif phase == "opening" or phase == "open" or phase == "closing" then
    scale = 1
    stepCard()
  elseif phase == "follow" then
    scale = 1
    stepFollow(dt)
  else -- idle
    scale = 1
  end

  if gulpT < GULP_MS and not cardOut() then
    local j = motion.jiggle(gulpT / pace) * 0.7
    sx, sy = sx * (1 - j * 0.8), sy * (1 + j)
  end
  applyExpression()
  if reopenAfterPick and not pickerOpen and phase == "idle" then
    reopenAfterPick = false
    openCard()
  end

  if draw and phase ~= "gone" then
    render()
  end
end

local lastTickMs = noctalia.nowMs()

function onFrameTick(deltaMs)
  lastTickMs = noctalia.nowMs()
  frame(math.clamp(tonumber(deltaMs) or 16, 0, 50), true)
end

-- Frame ticks only come while the compositor draws the surface. Under a
-- fullscreen window it does not, and the orb would freeze mid-animation; this
-- slow timer catches up on the missed time so it still finishes what it does.
function update()
  local now = noctalia.nowMs()
  local missed = now - lastTickMs
  if missed < 300 or phase == "gone" then
    return
  end
  lastTickMs = now
  missed = math.min(missed, 3000)
  while missed > 0 do
    local step = math.min(missed, 50)
    missed -= step
    frame(step, missed <= 0)
  end
end

-- A reload (any settings change, a script edit) recreates this runtime while
-- the orb is out. Carry on from where it was instead of dripping out of the
-- bar again, and head home if it was called back in the meantime.
do
  local spot = noctalia.state.get("orb.spot")
  local st = noctalia.state.get("orb.state")
  if type(spot) == "table" and spot.x ~= nil and (st == "away" or st == "returning") then
    x, y = motion.clampPoint(spot.x, spot.y, bounds)
    if st == "returning" then
      scale = 1
      setPhase("return")
    else
      setPhase("appear")
    end
  end
end

render()
noctalia.setUpdateInterval(250)
layer.setNeedsFrameTick(true)
