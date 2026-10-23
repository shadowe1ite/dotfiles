--!nonstrict
-- Request builders for Hermes. Pure (no noctalia.* calls) so tests/hermes_requests_test.luau
-- can run it with the luau CLI.
--
--   cfg = { url, apiPort, dashPort, key }
--
-- The API server takes a bearer key. The dashboard port only serves the public /api/status.

local M = {}

local function base(cfg, port)
  return `{string.gsub(cfg.url or "", "/+$", "")}:{port}`
end

function M.apiBase(cfg)
  return base(cfg, cfg.apiPort)
end

function M.dashBase(cfg)
  return base(cfg, cfg.dashPort)
end

-- An API-server request table, or nil, "no-key" when the key is missing.
function M.api(cfg, method, path, body)
  if cfg.key == nil or cfg.key == "" then
    return nil, "no-key"
  end
  local headers = { `Authorization: Bearer {cfg.key}`, "Accept: application/json" }
  if body ~= nil then
    table.insert(headers, "Content-Type: application/json")
  end
  return { url = M.apiBase(cfg) .. path, method = method, headers = headers, body = body }
end

-- A request to the dashboard's public routes (no auth): /api/status.
function M.public(cfg, path)
  return { url = M.dashBase(cfg) .. path, method = "GET", headers = { "Accept: application/json" } }
end

return M
