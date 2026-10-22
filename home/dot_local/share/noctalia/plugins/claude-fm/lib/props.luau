-- The little the mascot styles need: a rect constructor and the spin length.
local props = {}

props.SPIN_MS = 1300

function props.rect(x, y, w, h, color)
  return { x = x, y = y, w = w, h = h, color = color }
end

return props
