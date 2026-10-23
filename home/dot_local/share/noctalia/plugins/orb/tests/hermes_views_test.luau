--!nonstrict
-- Unit tests for lib/hermes/views.luau. Run with tests/run.sh.

local V = require("../lib/hermes/views")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

local now = 1000000
check("ago now", V.ago(now, now - 30) == "now")
check("ago minutes", V.ago(now, now - 300) == "5m")
check("ago hours", V.ago(now, now - 7200) == "2h")
check("ago days", V.ago(now, now - 3 * 86400) == "3d")
check("ago unknown", V.ago(now, nil) == "")

local st = V.status({ overall = "ok", active_agents = 2, active_sessions = 1, gateway_busy = true, profiles = { "default" } })
check("status online", st.link == "online" and st.agents == 2 and st.sessions == 1 and st.busy and st.profiles[1] == "default")
check("status degraded", V.status({ overall = "degraded" }).link == "degraded")

local long = string.rep("é", 70)
local rows = V.chatRows({ data = {
  { id = "a", title = "Refactor auth", source = "cli", last_active = now - 60 },
  { id = "b", title = nil, preview = long, source = "telegram" },
  { id = "c", title = "  ", preview = nil, source = "api_server" },
} }, now)
check("titled chat", rows[1].title == "Refactor auth" and rows[1].ago == "1m" and not rows[1].mine)
check("untitled chat uses its preview, cut on a character", utf8.len(rows[2].title) == 61, rows[2].title)
check("no title, no preview", rows[3].title == "Untitled chat" and rows[3].mine)

local msgs = V.messageRows({ data = {
  { role = "user", content = "hi" },
  { role = "tool", content = "output" },
  { role = "assistant", content = { { type = "text", text = "hello" } } },
  { role = "assistant", content = "" },
} })
check("messages keep user and assistant text", #msgs == 2 and msgs[2].text == "hello")

msgs = V.messageRows({ data = {
  { role = "user", content = "hi" },
  { role = "assistant", display_kind = "failed_turn", content = "Your request was not processed." },
  { role = "user", display_kind = "hidden", content = "[System: scaffolding]" },
  { role = "user", content = "[System: an untyped notice]" },
  { role = "user", display_kind = "model_switch", content = "[System: The active model for this chat has changed to opencode-free/glm-5.3-flash-free via provider main. From this point …]" },
  { role = "user", display_kind = "model_switch", content = "[System: The active model for this chat has changed to ds4.]" },
} })
check("hidden and untyped notices are skipped", #msgs == 4, #msgs)
check("a failed turn is an event", msgs[2].role == "event" and msgs[2].kind == "failed")
check("a model switch names the model", msgs[3].kind == "model" and msgs[3].text == "glm-5.3-flash-free", msgs[3].text)
check("a switch without a provider", msgs[4].text == "ds4", msgs[4].text)

msgs = V.messageRows({ data = {
  { role = "user", content = "plan it" },
  { role = "assistant", content = "", reasoning = "  first I look", tool_calls = { {} } },
  { role = "tool", content = "result" },
  { role = "user", display_kind = "hidden", content = "[System: nudge]" },
  { role = "assistant", content = "done", reasoning_content = "then I answer" },
  { role = "user", content = "thanks" },
  { role = "assistant", content = "np" },
} })
check("reasoning gathers over a turn's calls", msgs[2].thinking == "first I look\n\nthen I answer", msgs[2].thinking)
check("a reply without reasoning has none", msgs[4].thinking == nil)

check("short model", V.shortModel("NVIDIA/nvidia/nemotron-3-super") == "nemotron-3-super" and V.shortModel("gpt-6.1-sol") == "gpt-6.1-sol")

local picker = V.modelSections({
  provider = "main",
  model = "NVIDIA/z-ai/glm-5.3",
  providers = {
    { slug = "anthropic", authenticated = false, models = {} },
    { slug = "openai-codex", source = "hermes", authenticated = true, models = { "gpt-6.1-sol" } },
    { slug = "copilot", source = "built-in", authenticated = true, models = { "claude-fable-5.1" } },
    { slug = "nvidia", source = "built-in", authenticated = true, models = {} },
    { slug = "main", source = "user-config", is_user_defined = true, is_current = true, authenticated = true, models = { "NVIDIA/z-ai/glm-5.3" } },
  },
})
check("picker default", picker.default.provider == "main" and picker.default.model == "NVIDIA/z-ai/glm-5.3")
check("picker lists what you set up, current first", #picker.sections == 2 and picker.sections[1].slug == "main" and picker.sections[2].slug == "openai-codex")
check("built-in catalogs wait under more", #picker.more == 1 and picker.more[1].slug == "copilot")
check("picker without options", V.modelSections(nil).default == nil and #V.modelSections(nil).sections == 0)

if failures > 0 then
  error(`{failures} views test(s) failed`)
end
