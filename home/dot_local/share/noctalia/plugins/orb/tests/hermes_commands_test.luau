--!nonstrict
-- Unit tests for lib/hermes/commands.luau. Run with tests/run.sh.

local C = require("../lib/hermes/commands")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

check("plain text is a message", C.parse("hello") == nil)
check("double slash is a message", C.parse("//etc/hosts?") == nil and C.unescape("//etc/hosts?") == "/etc/hosts?")
local new = C.parse("/new")
check("command", new ~= nil and new.name == "new" and new.args == "")
check("alias", C.parse("/clear").name == "new")
check("case and args", C.parse("/MODEL  gpt-6-sol ").name == "model" and C.parse("/MODEL  gpt-6-sol ").args == "gpt-6-sol")
check("unknown", C.parse("/frobnicate x").unknown == "frobnicate")

local s = C.suggest("/m")
check("suggest by prefix", #s == 1 and s[1].name == "model")
check("suggest by alias", C.suggest("/hist")[1].name == "chats")
check("bare slash lists all (capped)", #C.suggest("/") == 6)
check("no suggestions once typing args", #C.suggest("/model g") == 0)

check("skill prompt", C.skillPrompt("github-pr-workflow review #12") == 'Load the "github-pr-workflow" skill (skill_view) and follow it.\n\nreview #12')
check("skill needs a name", C.skillPrompt("") == nil)

local options = {
  provider = "openai-codex",
  model = "gpt-6.1-sol",
  providers = {
    { slug = "openai-codex", is_current = true, authenticated = true, models = { "gpt-6.1-sol", "gpt-6-sol" } },
    { slug = "anthropic", authenticated = true, models = { "claude-opus-5-5", "gpt-6-sol" } },
    { slug = "nvidia", authenticated = false, models = { "z-ai/glm-5.3" } },
  },
}
local r = C.resolveModel(options, "gpt-6-sol")
check("bare id prefers the current provider", r ~= nil and r.provider == "openai-codex")
r = C.resolveModel(options, "claude-opus-5-5")
check("bare id finds a signed-in provider", r ~= nil and r.provider == "anthropic")
r = C.resolveModel(options, "anthropic/gpt-6-sol")
check("provider/model", r ~= nil and r.provider == "anthropic" and r.model == "gpt-6-sol")
check("not signed in, not offered", C.resolveModel(options, "z-ai/glm-5.3") == nil)
r = C.resolveModel(options, "nvidia:z-ai/glm-5.3")
check("explicit provider still works", r ~= nil and r.provider == "nvidia" and r.model == "z-ai/glm-5.3")
check("unknown model", C.resolveModel(options, "nope") == nil)

if failures > 0 then
  error(`{failures} commands test(s) failed`)
end
