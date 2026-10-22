-- Showtime spin: the real turn-around frames play once after each drop;
-- the rest of the time Clawd just bounces lightly on the beat.
return function(P)
  return {
    name = "spin",
    frame = function(t, a, opts)
      local sc = { pose = { eyes = "open" }, dy = a.beat > 0.4 and -1 or 0 }
      if a.dropAt ~= nil then
        local elapsed = t - a.dropAt
        if elapsed >= 0 and elapsed < P.SPIN_MS then
          sc.turnPhase = elapsed / P.SPIN_MS
          sc.dy = 0
        end
      end
      return sc
    end,
  }
end
