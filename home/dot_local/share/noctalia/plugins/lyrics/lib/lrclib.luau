-- LRCLIB (https://lrclib.net) lookups. The exact /api/get and a looser
-- /api/search go out at the same time; the exact one is preferred, the search
-- catches what the player's metadata spells differently.
local M = {}

local API = "https://lrclib.net/api/"
local HEADERS = { "User-Agent: noctalia-lyrics" }

-- Bracketed parts or " - suffixes" containing one of these are dropped from the title.
local NOISE = {
  "feat", "ft%.", "with ", "remaster", "version", "edit", "official", "video", "audio",
  "lyric", "explicit", "mono", "stereo", "from ", "prod%.", "bonus", "deluxe",
}

local function trim(s)
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function noisy(s)
  s = string.lower(s)
  for _, word in ipairs(NOISE) do
    if string.find(s, word) then
      return true
    end
  end
  return false
end

local function cut(s, markers)
  local lower = string.lower(s)
  for _, marker in ipairs(markers) do
    local at = string.find(lower, marker, 1, true)
    if at ~= nil then
      s = string.sub(s, 1, at - 1)
      lower = string.sub(lower, 1, at - 1)
    end
  end
  return s
end

-- "Popular (with Playboi Carti & Madonna)" -> "Popular"
-- "Song - Remastered 2011" -> "Song"
function M.cleanTitle(title)
  local function drop(group)
    if noisy(group) then
      return ""
    end
    return nil
  end
  local t = string.gsub(title, "%s*(%b())", drop)
  t = string.gsub(t, "%s*(%b[])", drop)
  local head, tail = string.match(t, "^(.-)%s+%-%s+(.+)$")
  if head ~= nil and noisy(tail) then
    t = head
  end
  t = cut(t, { " feat. ", " feat ", " ft. ", " ft ", " featuring " })
  t = trim(t)
  return t ~= "" and t or trim(title)
end

-- First artist only, without YouTube channel decorations.
function M.mainArtist(artists)
  local a = artists[1] or ""
  a = string.gsub(a, "%s+%-%s+Topic$", "")
  a = string.gsub(a, "VEVO$", "")
  a = cut(a, { ", ", " & ", " x ", " feat", " ft.", ";", " / " })
  return trim(a)
end

local function nonEmpty(s)
  return type(s) == "string" and string.find(s, "%S") ~= nil
end

local function result(entry)
  if entry.instrumental then
    return { kind = "instrumental", id = entry.id }
  elseif nonEmpty(entry.syncedLyrics) then
    return { kind = "synced", lyrics = entry.syncedLyrics, id = entry.id }
  elseif nonEmpty(entry.plainLyrics) then
    return { kind = "plain", lyrics = entry.plainLyrics, id = entry.id }
  end
  return nil
end

local function squash(s)
  s = string.lower(s or "")
  s = string.gsub(s, "%s*[,&]%s*", " ")
  return (string.gsub(s, "%s+", " "))
end

-- Same idea as lrcsnc's pickBest: points for synced lyrics, matching album,
-- artist and duration. Entries whose duration is way off would be out of sync
-- anyway, so they don't count at all.
local function score(entry, track)
  local s = 0
  if entry.instrumental then
    s += 3
  elseif nonEmpty(entry.syncedLyrics) then
    s += 5
  elseif nonEmpty(entry.plainLyrics) then
    s += 1
  else
    return nil
  end

  if track.length > 0 and type(entry.duration) == "number" then
    local diff = math.abs(entry.duration - track.length)
    if diff > 8 then
      return nil
    elseif diff < 1 then
      s += 5
    elseif diff <= 2 then
      s += 3
    elseif diff <= 5 then
      s += 1
    end
  end

  local album, other = string.lower(track.album), string.lower(entry.albumName or "")
  if album ~= "" and other ~= "" then
    if album == other then
      s += 2
    elseif string.find(album, other, 1, true) or string.find(other, album, 1, true) then
      s += 1
    end
  end

  local artist = squash(entry.artistName)
  if artist == squash(table.concat(track.artists, ", ")) then
    s += 3
  elseif artist == squash(M.mainArtist(track.artists)) then
    s += 1
  end

  if string.lower(entry.trackName or "") == string.lower(M.cleanTitle(track.title)) then
    s += 1
  end
  return s
end

local function pick(entries, track)
  local best, bestScore = nil, -1
  for _, entry in ipairs(entries) do
    local s = score(entry, track)
    if s ~= nil and s > bestScore then
      best, bestScore = entry, s
    end
  end
  return best and result(best)
end

local function query(params)
  local parts = {}
  for _, kv in ipairs(params) do
    if kv[2] ~= nil and kv[2] ~= "" then
      table.insert(parts, kv[1] .. "=" .. noctalia.string.urlEncode(tostring(kv[2])))
    end
  end
  return table.concat(parts, "&")
end

local function request(path, params, callback)
  noctalia.http({ url = API .. path .. "?" .. query(params), headers = HEADERS }, function(res)
    if not res.ok then
      callback(nil, "network")
      return
    end
    if res.status == 404 then
      callback(nil)
      return
    end
    if res.status ~= 200 then
      callback(nil, "http " .. res.status)
      return
    end
    local body = noctalia.json.decode(res.body)
    if body == nil then
      callback(nil, "bad response")
      return
    end
    callback(body)
  end)
end

-- track = { title, artists = { ... }, album, length (seconds) }
-- done({ kind = "synced" | "plain" | "instrumental" | "missing" | "error", lyrics?, id? })
function M.find(track, done)
  local exact, found
  local waiting = 2
  local failed = false
  local finished = false

  local function finish(r)
    if not finished then
      finished = true
      done(r)
    end
  end

  local function settle()
    waiting -= 1
    if waiting > 0 then
      return
    end
    if found ~= nil and found.kind ~= "plain" then
      finish(found)
    elseif exact ~= nil then
      finish(exact)
    elseif found ~= nil then
      finish(found)
    elseif failed then
      finish({ kind = "error" })
    else
      finish({ kind = "missing" })
    end
  end

  local length = track.length > 0 and math.floor(track.length + 0.5) or nil
  request("get", {
    { "track_name", track.title },
    { "artist_name", table.concat(track.artists, ", ") },
    { "album_name", track.album },
    { "duration", length },
  }, function(body, err)
    if body ~= nil then
      exact = result(body)
      if exact ~= nil and exact.kind ~= "plain" then
        finish(exact)
      end
    end
    -- LRCLIB answers 503 when its upstream lookup fails; that's just "not found" for us
    failed = failed or (err ~= nil and err ~= "http 503")
    settle()
  end)

  request("search", {
    { "track_name", M.cleanTitle(track.title) },
    { "artist_name", M.mainArtist(track.artists) },
  }, function(body, err)
    if type(body) == "table" then
      found = pick(body, track)
    end
    failed = failed or err ~= nil
    settle()
  end)
end

return M
