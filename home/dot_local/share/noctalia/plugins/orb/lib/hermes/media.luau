--!nonstrict
-- Files in and out of the chat. Pure (no noctalia.* calls) so tests/hermes_media_test.luau
-- can run it with the luau CLI.
--
-- Out: Hermes' API takes images inline (data URLs, up to 5 MB) and nothing else, so text
-- files go into the message itself and other files are copied to the server first.
-- In: a reply carries the images Hermes resolved as ![image](data:...) and every other
-- file as a MEDIA:<path> tag naming a path on the server.

local M = {}

M.IMAGE_MAX = 5 * 1024 * 1024
M.TEXT_MAX = 256 * 1024

local IMAGE_MIME = {
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  webp = "image/webp",
  bmp = "image/bmp",
}
local MIME_EXT = { ["image/png"] = "png", ["image/jpeg"] = "jpg", ["image/gif"] = "gif", ["image/webp"] = "webp", ["image/bmp"] = "bmp" }

function M.ext(path)
  return string.lower(string.match(path or "", "%.(%w+)$") or "")
end

function M.basename(path)
  return string.match(path or "", "([^/]+)/*$") or (path or "")
end

function M.isImage(path)
  return IMAGE_MIME[M.ext(path)] ~= nil
end

function M.mime(path)
  return IMAGE_MIME[M.ext(path)]
end

function M.extFor(mime)
  return MIME_EXT[mime] or "img"
end

-- One path component: no slashes, control characters or leading dots.
function M.safeName(name)
  name = string.gsub(name or "", "[%c/\\]", "_")
  name = string.gsub(name, "^%.+", "")
  if name == "" then
    name = "file"
  end
  return string.sub(name, 1, 120)
end

-- How an attachment travels: "image" inline, "text" pasted into the message, "file" copied
-- to the server. content: the whole file when it is small enough to read (nil otherwise);
-- a read cut short (at a NUL byte, say) is not text.
function M.kind(path, size, content)
  if M.isImage(path) and size <= M.IMAGE_MAX then
    return "image"
  end
  if
    size <= M.TEXT_MAX
    and content ~= nil
    and #content == size
    and not string.find(content, "\0", 1, true)
    and utf8.len(content) ~= nil
  then
    return "text"
  end
  return "file"
end

-- A text file as part of the message, fenced so its own backticks cannot close the fence.
function M.textBlock(name, content)
  local longest = 0
  for run in string.gmatch(content, "`+") do
    longest = math.max(longest, #run)
  end
  local fence = string.rep("`", math.max(3, longest + 1))
  return `File {name}:\n{fence}\n{content}\n{fence}`
end

-- The request's input: plain text, or text plus image parts.
--   images = { { mime, b64 } }
function M.input(text, images)
  if #images == 0 then
    return text
  end
  local parts = {}
  if text ~= "" then
    table.insert(parts, { type = "text", text = text })
  end
  for _, im in images do
    table.insert(parts, { type = "image_url", image_url = { url = `data:{im.mime};base64,{im.b64}` } })
  end
  return parts
end

local function isServerPath(path)
  return string.sub(path, 1, 1) == "/" or string.sub(path, 1, 2) == "~/"
end

-- A reply -> its text and the files in it.
--   media = { { kind = "image", mime, b64 } | { kind = "file", path, name, image } }
-- A MEDIA: tag that does not name a path stays in the text.
function M.extract(text)
  local media = {}
  text = string.gsub(text or "", "!%[[^%]\n]*%]%(data:(image/[%w%+%-%.]+);base64,([%w%+/=]+)%)", function(mime, b64)
    table.insert(media, { kind = "image", mime = mime, b64 = b64 })
    return ""
  end)

  local out, pos = {}, 1
  while true do
    local s, e = string.find(text, "MEDIA:", pos, true)
    if s == nil then
      table.insert(out, string.sub(text, pos))
      break
    end
    local before = string.gsub(string.sub(text, pos, s - 1), "[`\"'*_]+$", "")
    local rest = select(2, string.find(text, "^%s*", e + 1)) + 1
    local quote = string.sub(text, rest, rest)
    local path, after = nil, rest
    if quote == "`" or quote == '"' or quote == "'" then
      local close = string.find(text, quote, rest + 1, true)
      local newline = string.find(text, "\n", rest + 1, true)
      if close ~= nil and (newline == nil or close < newline) then
        path, after = string.sub(text, rest + 1, close - 1), close + 1
      end
    end
    if path == nil then
      local a, b = string.find(text, "^%S+", rest)
      path = if a ~= nil then string.sub(text, a, b) else ""
      local trimmed = string.gsub(path, "[%.,;:!%?%)%]}`\"'*_]+$", "")
      after = rest + #trimmed
      path = trimmed
    end
    after = select(2, string.find(text, "^[`\"'*_]*", after)) + 1
    if path ~= "" and isServerPath(path) then
      table.insert(out, before)
      table.insert(media, { kind = "file", path = path, name = M.basename(path), image = M.isImage(path) })
    else
      table.insert(out, string.sub(text, pos, after - 1))
    end
    pos = after
  end

  local clean = table.concat(out)
  clean = string.gsub(clean, "\n%s*\n%s*\n+", "\n\n")
  clean = string.gsub(clean, "^%s+", "")
  clean = string.gsub(clean, "%s+$", "")
  return clean, media
end

-- FNV-1a, 32 bit, as 8 hex digits: cache file names for media.
function M.hash(s)
  local h = 2166136261
  for i = 1, #s do
    h = bit32.bxor(h, string.byte(s, i))
    h = (bit32.lshift(h, 24) + h * 403) % 4294967296
  end
  return string.format("%08x", h)
end

-- dir/name, or dir/name (1).ext ... when taken.
function M.unique(dir, name, exists)
  local stem, ext = string.match(name, "^(.+)(%.[^.]+)$")
  if stem == nil then
    stem, ext = name, ""
  end
  local candidate, n = name, 1
  while exists(`{dir}/{candidate}`) do
    candidate = `{stem} ({n}){ext}`
    n += 1
  end
  return `{dir}/{candidate}`
end

return M
