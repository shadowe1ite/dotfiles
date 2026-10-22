-- Headbang: eyes shut, whole body dips on each kick, arms up on bass peaks.
return function(P)
  return {
    name = "headbang",
    frame = function(t, a, opts)
      return {
        pose = { arms = a.bass > 0.7 and "up" or "down", eyes = "closed", feet = "both" },
        dy = a.beat > 0.4 and 1 or 0,
      }
    end,
  }
end
