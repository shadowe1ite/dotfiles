--!nonstrict
-- Unit tests for lib/hermes/requests.luau. Run with tests/run.sh.

local R = require("../lib/hermes/requests")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

local cfg = { url = "http://h.ts.net/", apiPort = 8642, dashPort = 9119, key = "k1" }
local req = R.api(cfg, "POST", "/api/sessions", "{}")
check("api url, trailing slash dropped", req.url == "http://h.ts.net:8642/api/sessions", req.url)
check("api bearer header", table.find(req.headers, "Authorization: Bearer k1") ~= nil)
check("api json body header", table.find(req.headers, "Content-Type: application/json") ~= nil)
check("api GET has no content type", table.find(R.api(cfg, "GET", "/health").headers, "Content-Type: application/json") == nil)
local none, why = R.api({ url = "http://h", apiPort = 1, dashPort = 2 }, "GET", "/health")
check("no key, no request", none == nil and why == "no-key")
local blank = R.api({ url = "http://h", apiPort = 1, dashPort = 2, key = "" }, "GET", "/health")
check("empty key, no request", blank == nil)
check("public url", R.public(cfg, "/api/status").url == "http://h.ts.net:9119/api/status")

if failures > 0 then
  error(`{failures} requests test(s) failed`)
end
