--!nonstrict
-- The orb's slash commands. Hermes' API server runs every message through the agent as plain
-- text (its slash commands live in the gateway's messaging and CLI surfaces), so the orb
-- handles these itself. Pure, for tests/hermes_commands_test.luau.
--
--   parse(text)        -> nil (a message) | { name, args } | { unknown = word }
--   suggest(draft)     -> entries whose name or alias starts with what follows "/"
--   resolveModel(options, query) -> { provider, model } | nil

local M = {}

-- In the order /help lists them. desc is a translation key under hermes.cmd.
M.LIST = {
  { name = "new", aliases = { "clear", "reset" }, args = "" },
  { name = "chats", aliases = { "history", "resume" }, args = "" },
  { name = "attach", aliases = { "file", "upload" }, args = "" },
  { name = "model", aliases = {}, args = "[model]" },
  { name = "retry", aliases = {}, args = "" },
  { name = "stop", aliases = {}, args = "" },
  { name = "title", aliases = { "rename" }, args = "<name>" },
  { name = "fork", aliases = { "branch" }, args = "[title]" },
  { name = "skill", aliases = {}, args = "<name> [request]" },
  { name = "approve", aliases = {}, args = "[once|session|always]" },
  { name = "deny", aliases = {}, args = "" },
  { name = "help", aliases = { "commands" }, args = "" },
}

local BY_WORD = {}
for _, entry in M.LIST do
  BY_WORD[entry.name] = entry
  for _, alias in entry.aliases do
    BY_WORD[alias] = entry
  end
end

-- "//text" sends "/text" as a message.
function M.parse(text)
  if type(text) ~= "string" or string.sub(text, 1, 1) ~= "/" or string.sub(text, 1, 2) == "//" then
    return nil
  end
  local word, args = string.match(text, "^/(%S*)%s*(.-)%s*$")
  word = string.lower(word or "")
  local entry = BY_WORD[word]
  if entry == nil then
    return { unknown = word }
  end
  return { name = entry.name, args = args or "" }
end

-- What a message starting with "//" really says.
function M.unescape(text)
  if type(text) == "string" and string.sub(text, 1, 2) == "//" then
    return string.sub(text, 2)
  end
  return text
end

-- While the input holds only "/word" (no space yet): the commands it could become.
function M.suggest(draft, max)
  local prefix = string.match(draft or "", "^/(%S*)$")
  if prefix == nil then
    return {}
  end
  prefix = string.lower(prefix)
  local out = {}
  for _, entry in M.LIST do
    local hit = string.sub(entry.name, 1, #prefix) == prefix
    for _, alias in entry.aliases do
      hit = hit or string.sub(alias, 1, #prefix) == prefix
    end
    if hit then
      table.insert(out, entry)
      if #out >= (max or 6) then
        break
      end
    end
  end
  return out
end

-- "/skill <name> [request]" -> the message that asks Hermes to use that skill.
function M.skillPrompt(args)
  local name, request = string.match(args or "", "^(%S+)%s*(.-)$")
  if name == nil then
    return nil
  end
  local ask = `Load the "{name}" skill (skill_view) and follow it.`
  if request ~= "" then
    ask ..= `\n\n{request}`
  end
  return ask
end

local function models(provider)
  local out = {}
  for _, m in provider.models or {} do
    local id = if type(m) == "table" then (m.id or m.name) else m
    if type(id) == "string" then
      table.insert(out, id)
    end
  end
  return out
end

-- Finds the provider for "/model <query>": "provider/model" or "provider:model" picks that
-- provider; a bare model id prefers the current provider, then any signed-in one.
function M.resolveModel(options, query)
  query = string.match(query or "", "^%s*(.-)%s*$")
  if options == nil or query == "" then
    return nil
  end
  local providers = options.providers or {}
  local function find(slug, id)
    for _, p in providers do
      if (slug == nil or p.slug == slug) and (slug ~= nil or p.is_current or p.authenticated) then
        for _, m in models(p) do
          if m == id then
            return { provider = p.slug, model = m }
          end
        end
      end
    end
    return nil
  end
  local slug, id = string.match(query, "^([%w%-_]+)[:/](.+)$")
  if slug ~= nil then
    local hit = find(slug, id)
    if hit ~= nil then
      return hit
    end
  end
  for _, p in providers do
    if p.is_current then
      for _, m in models(p) do
        if m == query then
          return { provider = p.slug, model = m }
        end
      end
    end
  end
  return find(nil, query)
end

return M
