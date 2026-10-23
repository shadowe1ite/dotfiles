--!nonstrict
-- Putting the plugin's settings back to their defaults. Noctalia keeps the
-- values a user changed in settings.toml under [plugin_settings."<id>"], and
-- neither the plugin API nor IPC can clear them, so the service edits that
-- file and reloads. Pure: tests/reset_test.luau runs it with the luau CLI.

local M = {}

-- settings.toml text without the plugin's table (and any of its subtables).
-- Returns the new text and whether anything was removed.
function M.dropPluginSettings(text, id)
  local header = `[plugin_settings."{id}"]`
  local subPrefix = `[plugin_settings."{id}".`
  if string.sub(text, -1) ~= "\n" then
    text ..= "\n"
  end

  local kept = {}
  local skipping, removed = false, false
  for line in string.gmatch(text, "([^\n]*)\n") do
    local trimmed = string.match(line, "^%s*(.-)%s*$")
    if string.sub(trimmed, 1, 1) == "[" then
      skipping = trimmed == header or string.sub(trimmed, 1, #subPrefix) == subPrefix
      removed = removed or skipping
    end
    if not skipping then
      table.insert(kept, line)
    end
  end
  if not removed then
    return text, false
  end
  return table.concat(kept, "\n") .. "\n", true
end

return M
