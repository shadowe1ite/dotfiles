--!nonstrict
-- Pure motion math for the orb: steering, drift targets, easing, and where the
-- bar sits on screen. No noctalia.* calls, so tests/motion_test.luau can run it
-- with the plain luau CLI.

local M = {}

function M.easeOutCubic(t)
  local u = 1 - t
  return 1 - u * u * u
end

function M.easeInCubic(t)
  return t * t * t
end

-- Overshoots past 1 and settles back: the "pop".
function M.easeOutBack(t)
  local c1 = 1.70158
  local c3 = c1 + 1
  local u = t - 1
  return 1 + c3 * u * u * u + c1 * u * u
end

-- One step of arrive-steering: accelerate toward the target, never faster than
-- maxSpeed (px/s), braking inside a radius of about a second of travel.
-- `response` is how quickly velocity follows the desired velocity (1/s).
function M.steer(px, py, vx, vy, tx, ty, dt, maxSpeed, response)
  local dx, dy = tx - px, ty - py
  local dist = math.sqrt(dx * dx + dy * dy)
  local dvx, dvy = 0, 0
  if dist > 0.001 then
    local speed = maxSpeed * math.min(1, dist / (maxSpeed * 0.9))
    dvx, dvy = dx / dist * speed, dy / dist * speed
  end
  local k = 1 - math.exp(-response * dt)
  vx += (dvx - vx) * k
  vy += (dvy - vy) * k
  return px + vx * dt, py + vy * dt, vx, vy
end

function M.arrived(px, py, vx, vy, tx, ty)
  local dx, dy = tx - px, ty - py
  return dx * dx + dy * dy < 9 and vx * vx + vy * vy < 144
end

-- A random point inside bounds at least minDist away from (px, py); after ten
-- misses, the farthest candidate seen.
function M.pickTarget(rng, bounds, px, py, minDist)
  local bestX, bestY, bestD = px, py, -1
  for _ = 1, 10 do
    local x = bounds.left + rng() * (bounds.right - bounds.left)
    local y = bounds.top + rng() * (bounds.bottom - bounds.top)
    local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
    if d >= minDist then
      return x, y
    end
    if d > bestD then
      bestX, bestY, bestD = x, y, d
    end
  end
  return bestX, bestY
end

-- Which of the nine panel positions is closest: screen split into thirds.
function M.nearestAnchor(x, y, w, h)
  local col = if x < w / 3 then "left" elseif x > w * 2 / 3 then "right" else "center"
  local row = if y < h / 3 then "top" elseif y > h * 2 / 3 then "bottom" else "center"
  if row == "center" and col == "center" then
    return "center"
  end
  return `{row}_{col}`
end

-- A guess at where the widget sits along its bar. Plugins cannot read a widget's
-- pixel position, so this uses its section and index with an average slot width.
local SLOT = 64
function M.homeAlong(section, index, count, length)
  if section == "start" then
    return 24 + (index - 0.5) * SLOT
  elseif section == "end" then
    return length - 24 - (count - index + 0.5) * SLOT
  elseif section == "center" then
    return length / 2 + (index - (count + 1) / 2) * SLOT
  end
  return length / 2
end

-- The point on the bar's inner edge where the orb dives in and out.
function M.homePoint(edge, thickness, along, w, h)
  if edge == "bottom" then
    return along, h - thickness
  elseif edge == "left" then
    return thickness, along
  elseif edge == "right" then
    return w - thickness, along
  end
  return along, thickness
end

-- Unit vector pointing from the bar into the screen.
function M.outward(edge)
  if edge == "bottom" then
    return 0, -1
  elseif edge == "left" then
    return 1, 0
  elseif edge == "right" then
    return -1, 0
  end
  return 0, 1
end

-- Where the card goes for a ball centered at (bx, by), Marea-style: the ball
-- sits `inset` px inside the card's corner and the card grows right and down,
-- flipping left / up when that would leave the screen. `pad` is room for the
-- shadow around the card. preferX ("right" / "left") and preferY ("down" /
-- "up") pick a side outright; nil or "auto" flips only when needed.
--
-- Returns the layer surface (left, top, sw, sh), the ball center inside it
-- (bx, by), the flips, and ballX / ballY: where the ball has to be on screen
-- for the card to fit. That differs from the input only when even a flipped
-- card cannot fit; the orb then moves there first.
function M.cardLayout(bx, by, cw, ch, pad, inset, w, h, preferX, preferY)
  local sw, sh = cw + pad * 2, ch + pad * 2
  local flipX = if preferX == "left" then true elseif preferX == "right" then false else bx - inset - pad + sw > w
  local flipY = if preferY == "up" then true elseif preferY == "down" then false else by - inset - pad + sh > h
  local lbx = if flipX then sw - pad - inset else pad + inset
  local lby = if flipY then sh - pad - inset else pad + inset
  local left = math.clamp(bx - lbx, 0, math.max(0, w - sw))
  local top = math.clamp(by - lby, 0, math.max(0, h - sh))
  return {
    flipX = flipX,
    flipY = flipY,
    sw = sw,
    sh = sh,
    left = left,
    top = top,
    bx = lbx,
    by = lby,
    ballX = left + lbx,
    ballY = top + lby,
  }
end

-- The card at progress c (0..1) inside the surface: a 2*inset square hidden
-- under the ball at 0, the full card at 1, always grown from the ball's corner.
function M.cardRect(lay, cw, ch, pad, inset, c)
  local min = inset * 2
  local w = min + (cw - min) * c
  local h = min + (ch - min) * c
  local x = if lay.flipX then lay.sw - pad - w else pad
  local y = if lay.flipY then lay.sh - pad - h else pad
  return x, y, w, h
end

-- The shake of a drop just let go: a squash, then a few damped bounces
-- (-7%, +5%, -1%...). Returns the vertical stretch offset at t ms.
function M.jiggle(t)
  return -0.073 * math.exp(-t / 140) * math.cos(2 * math.pi * t / 135)
end

function M.clampPoint(x, y, b)
  return math.clamp(x, b.left, b.right), math.clamp(y, b.top, b.bottom)
end

-- A saved spot { x, y, w, h }, kept on screen; nil when nothing was saved or
-- it was saved on a screen of another size.
function M.restorePoint(saved, w, h, b)
  if type(saved) ~= "table" or saved.w ~= w or saved.h ~= h then
    return nil
  end
  return M.clampPoint(saved.x, saved.y, b)
end

-- Where the orb's center may drift: the screen minus the bar, inset by pad.
function M.roamBounds(edge, thickness, w, h, pad)
  local b = { left = pad, top = pad, right = w - pad, bottom = h - pad }
  if edge == "top" then
    b.top += thickness
  elseif edge == "bottom" then
    b.bottom -= thickness
  elseif edge == "left" then
    b.left += thickness
  elseif edge == "right" then
    b.right -= thickness
  end
  return b
end

return M
