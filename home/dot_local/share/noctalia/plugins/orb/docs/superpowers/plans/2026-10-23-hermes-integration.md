# Orb × Hermes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the orb into Hermes's body on the desktop: it mirrors Hermes activity, chats with Hermes in its card, and shows chats, memory, agents and cron, with nudges.

**Architecture:** Pure Luau modules under `lib/hermes/` (request builders, SSE parser, chat reducer, view normalizers, activity map) are unit-tested with the `luau` CLI. One impure module, `lib/hermes/client.luau`, owns all network I/O (Noctalia `http`/`httpStream` for the API server and public status, `curl` with a cookie jar for the password-gated dashboard) and is driven by `service.luau`, which publishes `orb.hermes.*` state. The card renders one tab at a time from `lib/tabs/*.luau`.

**Tech Stack:** Noctalia plugin API 36 (Luau), `luau` CLI for tests, `curl`, `secret-tool` (libsecret), Hermes Agent 0.21.7 API server + dashboard backend.

**Spec:** `docs/superpowers/specs/2026-10-23-hermes-integration-design.md`

## Global Constraints

- `plugin_api` stays `36`; every file starts with `--!nonstrict`.
- Pure modules (`lib/hermes/{requests,sse,chat,views,activity}.luau`, `lib/tabs/*.luau` helpers) never call `noctalia.*` and never `require` another module, so `tests/*_test.luau` can load them with `require("../lib/hermes/<name>")`.
- Secrets only in the keyring: `secret-tool lookup service orb-hermes kind api-key` and `… kind dashboard-password`. Never in settings, logs, or argv.
- Defaults: server `http://server.tailf72995.ts.net`, API port `8642`, dashboard port `9119`.
- Polling: status every 5 s with the card open, 20 s closed, 60 s after a failure; lists on tab open and every 60 s while that tab shows; learning graph every 10 min.
- Streamed reply renders at most 10 times per second; the chat model keeps the last 50 messages.
- `curl` always in argv form via `noctalia.runAsync({ "curl", ... })`; jar and login body live in `pluginDataDir() .. "/private"`, created with `mkdir -m 700 -p`.
- Card defaults become 420 × 540 (`card_width`, `card_height`); changing a default needs a plugin disable/enable to take effect on this machine.
- Every `ui.box` used as a spacer has `fill = face.CLEAR`; roamer UI callbacks are named globals (the tree re-renders every frame).
- Log only status changes, prefixed `orb-hermes:`; never log request bodies.

## Review Focus

1. **Hermes unreachable** (Tailscale down, server off): no request storm, offline view with Retry, polling backs off to 60 s. → `activity.pollDelay` tests (Task 5).
2. **Key missing from the keyring** (`secret-tool` exits 1): card says how to store it, no API requests are sent. → `requests.api` returns `nil, "no-key"` test (Task 1).
3. **Stream ends without a terminal event** (network drop mid-reply): message marked interrupted, not left "running" forever. → `chat.close` test (Task 3).
4. **Session with no title** (fresh Telegram chat): row shows its preview, else "Untitled chat". → `views.chatRows` test (Task 4).
5. **SSE line edge cases**: `:` keepalives, `data:` with colons in JSON, multi-line data, missing blank line before close. → `sse` tests (Task 2).

---

### Task 0: Server, keyring, local repo (you + me)

**Files:** none in the plugin besides `git init`.

- [ ] **Step 1 (you, on the server): enable the API server on the Tailscale address**

```sh
TS_IP=$(tailscale ip -4)
cat >> ~/.hermes/.env <<EOF
API_SERVER_ENABLED=true
API_SERVER_HOST=$TS_IP
API_SERVER_KEY=$(openssl rand -hex 32)
EOF
chmod 600 ~/.hermes/.env
hermes gateway restart
grep API_SERVER_KEY ~/.hermes/.env
```

- [ ] **Step 2 (you, locally): store both secrets**

```sh
secret-tool store --label='Orb: Hermes API key' service orb-hermes kind api-key
secret-tool store --label='Orb: Hermes dashboard password' service orb-hermes kind dashboard-password
```

- [ ] **Step 3: verify**

Run: `curl -s -H "Authorization: Bearer $(secret-tool lookup service orb-hermes kind api-key)" http://server.tailf72995.ts.net:8642/v1/capabilities | jq .object`
Expected: `"hermes.api_server.capabilities"`

- [ ] **Step 4: local repo for commits**

Run: `cd ~/.local/share/noctalia/plugins/orb && git init -q && git add -A && git commit -qm "chore: orb before Hermes integration"`
Expected: `git log --oneline` shows one commit.

---

### Task 1: Request builders and settings

**Files:**
- Create: `lib/hermes/requests.luau`
- Modify: `plugin.toml` (settings, defaults, dependencies, version `0.5.0`), `translations/en.json`
- Test: `tests/hermes_requests_test.luau`

**Interfaces:**
- Produces: `cfg` table `{ url: string, apiPort: number, dashPort: number, user: string, key: string? }`
- `requests.api(cfg, method: string, path: string, body: string?) -> (HttpRequest?, string?)` — `nil, "no-key"` when `cfg.key` is nil/empty; headers `Authorization: Bearer <key>`, `Accept: application/json`, plus `Content-Type: application/json` when `body`.
- `requests.public(cfg, path: string) -> HttpRequest` — dashboard URL, no auth.
- `requests.curlArgs(cfg, method: string, path: string, jar: string, bodyFile: string?) -> { string }` — `curl -s -S -m 15 -b jar -c jar -X <method> -H "Accept: application/json" [-H "Content-Type: application/json" --data @bodyFile] <dashboard url><path>` followed by `-w "\n%{http_code}"`.
- `requests.loginBody(user: string, password: string) -> table` — `{ provider = "basic", username = user, password = password, next = "/" }`.
- `requests.splitStatus(stdout: string) -> (string, number)` — body and the trailing status code written by `-w`.

- [ ] **Step 1: Write the failing test** `tests/hermes_requests_test.luau` (same `check` helper as `tests/motion_test.luau`):

```lua
local R = require("../lib/hermes/requests")
local cfg = { url = "http://h.ts.net", apiPort = 8642, dashPort = 9119, user = "admin", key = "k1" }
local req = R.api(cfg, "POST", "/api/sessions", "{}")
check("api url", req.url == "http://h.ts.net:8642/api/sessions")
check("api bearer", table.find(req.headers, "Authorization: Bearer k1") ~= nil)
check("api json body header", table.find(req.headers, "Content-Type: application/json") ~= nil)
local none, why = R.api({ url = cfg.url, apiPort = 8642, dashPort = 9119, user = "a" }, "GET", "/health")
check("no key, no request", none == nil and why == "no-key")
check("public url", R.public(cfg, "/api/status").url == "http://h.ts.net:9119/api/status")
local argv = R.curlArgs(cfg, "DELETE", "/api/learning/node", "/j", "/b")
check("curl argv", argv[1] == "curl" and table.find(argv, "-b") and table.find(argv, "@/b") and argv[#argv - 2] == "http://h.ts.net:9119/api/learning/node")
check("password never in argv", not table.find(argv, "secret"))
local body, code = R.splitStatus('{"ok":true}\n200')
check("split status", body == '{"ok":true}' and code == 200)
check("login body", R.loginBody("admin", "pw").provider == "basic")
```

- [ ] **Step 2: Run it** — `./tests/run.sh` → FAIL: `could not resolve child component "hermes"`.
- [ ] **Step 3: Implement `lib/hermes/requests.luau`** with the signatures above (trailing slash on `cfg.url` stripped).
- [ ] **Step 4: Settings in `plugin.toml`** — add `hermes_url` (string, default `http://server.tailf72995.ts.net`), `hermes_api_port` (int 8642, 1–65535), `hermes_dashboard_port` (int 9119), `hermes_dashboard_user` (string, default `""`); `card_width` default `420`, `card_height` default `540`; `dependencies = ["curl", "libsecret"]`; `version = "0.5.0"`. Labels/descriptions in `translations/en.json` under `settings.hermes_*`.
- [ ] **Step 5: Run** `./tests/run.sh` (PASS) and `noctalia plugins lint .` → the four new settings are reported "never read" (expected until Task 6); no errors.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(hermes): request builders and connection settings"`

---

### Task 2: SSE parser

**Files:** Create `lib/hermes/sse.luau`; Test `tests/hermes_sse_test.luau`

**Interfaces:**
- `sse.new() -> Parser`; `Parser:push(line: string) -> { event: string, data: string }?` — returns an event when a blank line ends one; `event` defaults to `"message"`; lines starting with `:` are ignored; repeated `data:` lines join with `"\n"`; one optional space after the colon is stripped.
- `Parser:finish() -> { event: string, data: string }?` — flushes a pending event at stream close.

- [ ] **Step 1: Failing test** covering: a delta event (`event: assistant.delta` / `data: {"delta":"Hi: there"}` / blank) yields `{event="assistant.delta", data='{"delta":"Hi: there"}'}`; `: keepalive` yields nothing; two `data:` lines join with `\n`; a line `data:x` (no space) keeps `x`; `finish()` returns the event left without a trailing blank line; a blank line with nothing pending returns nil.
- [ ] **Step 2: Run** → FAIL (module missing).
- [ ] **Step 3: Implement** with the interface above.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `feat(hermes): SSE line parser`

---

### Task 3: Chat reducer

**Files:** Create `lib/hermes/chat.luau`; Test `tests/hermes_chat_test.luau`

**Interfaces:**
- `chat.new(sessionId: string?) -> Chat` with fields `sessionId`, `messages = {}` (each `{ role = "user"|"assistant", text, tools = {}, state = "done"|"interrupted"|"failed"|"cancelled"|"partial" }`), `streaming: string?`, `tools = {}` (each `{ name, preview, state = "running"|"done"|"error" }`), `runId: string?`, `status = "idle"|"sending"|"thinking"|"tool"|"waiting"|"done"|"failed"|"cancelled"|"interrupted"`, `approval: { requestId, command, description, choices }?`, `lastEventAt: number?`.
- `chat.addUser(c, text: string) -> Chat` — appends the user message, `status = "sending"`, clears `streaming`, `tools`, `approval`.
- `chat.apply(c, event: string, payload: table, nowMs: number) -> Chat` — rules:
  - every event: `runId = payload.run_id or runId`, `lastEventAt = nowMs`
  - `run.started` → `status = "thinking"`
  - `assistant.delta` → `streaming ..= payload.delta`; `status = "thinking"` unless a tool is running
  - `tool.progress` with `tool_name == "_thinking"` → `status = "thinking"`
  - `tool.started` → push `{ name = payload.tool, preview = payload.preview, state = "running" }`, `status = "tool"`
  - `tool.completed` / `tool.failed` → last running tool with that name → `"done"` / `"error"`
  - `approval.request` → `approval = { requestId = payload.request_id, command = payload.command, description = payload.description, choices = payload.choices }`, `status = "waiting"`
  - `run.completed` → assistant message from `streaming` (`state = "done"`, or `"partial"` when `payload.partial`), `status = "done"`
  - `run.failed` → assistant message with `streaming` or `payload.error` (`state = "partial"` when `payload.partial`, else `"failed"`), `status = "failed"`
  - `run.cancelled` → `state = "cancelled"`, `status = "cancelled"`
  - terminal events clear `streaming`, `approval`, `runId`
- `chat.close(c, ok: boolean) -> Chat` — stream closed; if `status` is not terminal, keep `streaming` as an assistant message with `state = "interrupted"`, `status = "interrupted"`.
- `chat.trim(c, max: number) -> Chat` — keeps the last `max` messages (called with 50).

- [ ] **Step 1: Failing test** — `run.failed{partial=true}` after deltas keeps the text with `state = "partial"`; a full turn (`addUser` → `run.started` → two `assistant.delta` → `tool.started{tool="terminal", preview="ls"}` → `tool.completed` → `run.completed`) ends with 2 messages, assistant text = the two deltas joined, its tools = `{terminal done}`, `status = "done"`, `runId = nil`; `runId` captured from any event's `run_id` while running; `approval.request` sets `status = "waiting"` and `approval.requestId`; `close(c, false)` mid-stream → last message `state = "interrupted"`; `run.failed` with no deltas uses `payload.error`; `trim` on 60 messages keeps 50, the newest last.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `feat(hermes): chat reducer`

---

### Task 4: View normalizers

**Files:** Create `lib/hermes/views.luau`; Test `tests/hermes_views_test.luau`

**Interfaces** (inputs are decoded JSON tables; all tolerate missing fields):
- `views.status(json) -> { link = "online"|"degraded", agents: number, sessions: number, busy: boolean, profiles: { string } }` — `link = "online"` when `overall == "ok"`.
- `views.chatRows(json, nowS: number) -> { { id, title, source, ago: string, mine: boolean } }` from `json.data`; `title = title or preview (first 60 chars) or "Untitled chat"`; `mine = source == "api-server"`; `ago` like `"now"`, `"5m"`, `"3h"`, `"2d"` from `last_active` (unix seconds).
- `views.messageRows(json) -> { { role, text } }` from `json.data`, keeping roles `user`/`assistant` with non-empty string `content`.
- `views.jobRows(json, nowS: number) -> { { id, name, schedule, next: string, nextAt: number?, last: string, paused: boolean, failed: boolean } }` from `json.jobs` (`nextAt` = `next_run_at` as unix seconds); `schedule = schedule_display or schedule`; `failed = last_status == "error" or last_status == "failed"`; `paused = paused or enabled == false`.
- `views.memory(graph, sizes) -> { entries = { { id, title, source, ts } }, skills = { { id, title, ts } }, fill = { memory: number, user: number } }` — nodes with `kind == "memory"` / `"skill"`, newest first by `timestamp`; `fill.memory = builtin_files.memory / 2200`, `fill.user = builtin_files.user / 1375`, clamped to 0–1.
- `views.newIds(seen: { [string]: boolean }, entries) -> { string }` — ids not in `seen`.
- `views.agents(statusProfiles, profilesJson, activeJson) -> { { name, description, model, active: boolean } }`.

- [ ] **Step 1: Failing test** — includes Review Focus #4 (`title = nil`, `preview = nil` → `"Untitled chat"`; long preview cut to 60 chars), a failed job (`last_status = "error"` → `failed = true`), a disabled job reads as paused, memory fill `1100/2200 → 0.5` and over-limit clamps to `1`, `newIds` returns only unseen ids, `ago(nowS - 30) == "now"`, `ago(nowS - 7200) == "2h"`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `feat(hermes): view normalizers`

---

### Task 5: Activity map and poll timing

**Files:** Create `lib/hermes/activity.luau`; Test `tests/hermes_activity_test.luau`

**Interfaces:**
- `activity.pet(input) -> "idle"|"review"|"run"|"wave"|"failed"|"waiting"` with `input = { chatStatus, busyElsewhere: boolean, finishedAt: number?, failedAt: number?, nowMs: number }`. Priority: `waiting` (chatStatus `"waiting"`) › `failed` (within 2000 ms of `failedAt`) › `wave` (within 1500 ms of `finishedAt`) › `run` (chatStatus `"tool"`) › `review` (chatStatus `"thinking"`/`"sending"`) › `run` (busyElsewhere) › `idle`.
- `activity.face(pet: string) -> { mood: string?, lookY: number?, wiggle: boolean }` — `review` → `lookY = -0.6`; `run` → `wiggle = true`; `wave` → `mood = "happy"`; `failed` → `mood = "surprised"`; `waiting` → `lookY = 0`, `mood = "normal"`; `idle` → empty.
- `activity.pollDelay(link: string, cardOpen: boolean) -> number` — `"offline"`/`"auth"`/`"error"` → `60000`; else `cardOpen and 5000 or 20000`.

- [ ] **Step 1: Failing test** — each priority case, the 1500/2000 ms windows expire, and Review Focus #1: `pollDelay("offline", true) == 60000`, `pollDelay("online", true) == 5000`, `pollDelay("online", false) == 20000`.
- [ ] **Step 2–4:** run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** — `feat(hermes): activity map and poll timing`

---

### Task 6: Client and service wiring (no UI yet)

**Files:**
- Create: `lib/hermes/client.luau` (impure; uses `noctalia.*`)
- Modify: `service.luau` (require client, publish state, IPC verbs)

**Interfaces:**
- Consumes: Tasks 1–5.
- `client.new(cfg, publish: (key: string, value: any) -> ()) -> Client`
- `Client:loadSecrets(done: (ok: boolean) -> ())` — `runAsync({ "secret-tool", "lookup", "service", "orb-hermes", "kind", "api-key" })`, then the dashboard password; trims trailing newline; on failure publishes `orb.hermes.link = { status = "auth", detail = "no-key" }`.
- `Client:pollStatus()` — `http(requests.public(cfg, "/api/status"))` → `views.status` → publishes `orb.hermes.link` and feeds `busyElsewhere`; on failure `{ status = "offline" }`.
- `Client:send(text: string)` — creates the session if needed (`POST /api/sessions`, id from `json.session.id`, saved in `pluginDataDir()/hermes.json` as `{ "session": id }`), then `httpStream(requests.api(cfg, "POST", "/api/sessions/" .. id .. "/chat/stream", json{input=text}))`, feeding lines through `sse` → `chat.apply`; publishes `orb.hermes.chat` at most every 100 ms and on every terminal event; `onClose` → `chat.close`.
- `Client:stop()` — `POST /v1/runs/{runId}/stop` when `runId`, else `stream.stop()`.
- `Client:newChat()` — forgets the session id and the chat model.
- `Client:history()` — `GET /api/sessions/{id}/messages?inline_images=false` → `views.messageRows` into the chat model.
- `Client:api(method, path, body, done: (ok, json) -> ())` — generic helper used by later tasks; 401 publishes link `auth`; 429 on `send` sets the chat notice "Hermes is busy" and retries once after 5 s.
- `Client:dash(method, path, bodyTable?, done: (ok, json) -> ())` — curl path: ensure `private/` exists (`mkdir -m 700 -p`), on 401 log in once (`loginBody` encoded to `private/login.json`, `curlArgs(..., "POST", "/auth/password-login", jar, file)`, then `removeFile(file)`) and retry once.
- Service publishes `orb.hermes.activity = { pet, agents, sessions }` (via `activity.pet`) every status poll and on every chat publish; polls on `activity.pollDelay`; reads cfg from the four `hermes_*` settings.
- Service handles `orb.hermes.cmd` strings `"<verb>:<ms>:<json args>"` with verbs `send`, `stop`, `new`, `refresh`, `job-run`, `job-pause`, `job-resume`, `job-delete`, `memory-delete`, `agent-activate`, `approve`, `tab` (`tab` stores `orb.hermes.tab`; `{ id = "chat" }` also runs `Client:history()`; later tasks add per-tab fetches).
- IPC (testing): `hermes-status`, `hermes-send <text>`, `hermes-stop`, `hermes-new`.

- [ ] **Step 1: Implement** `client.luau` and the service wiring above.
- [ ] **Step 2: Syntax + lint** — `for f in *.luau lib/*.luau lib/hermes/*.luau; do luau-compile --null $f >/dev/null || echo ERR $f; done; noctalia plugins lint .` → no ERR, `0 errors, 0 warnings`.
- [ ] **Step 3: Live check** — `noctalia msg plugin shadow/orb:service all hermes-status; sleep 2; grep 'orb-hermes:' ~/.cache/noctalia/noctalia.log | tail -2` → `orb-hermes: link online`.
- [ ] **Step 4: Live chat check** — `noctalia msg plugin shadow/orb:service all hermes-send "reply with the word pong"`; within 30 s the log shows `orb-hermes: run done`, and `cat ~/.local/state/noctalia/plugins/data/shadow/orb/hermes.json` holds `{"session": "<id>"}`.
- [ ] **Step 5: Commit** — `feat(hermes): client and service wiring`

---

### Task 7: Alive — the orb reacts

**Files:** Modify `roamer.luau`, `widget.luau`

**Interfaces:**
- Consumes: `orb.hermes.activity`, `orb.hermes.link`, `activity.face(pet)`.
- Both watch `orb.hermes.activity` and overlay `activity.face` on `Life`: `mood` via `life:poke(mood, 1500)` on change, `lookY` via `life:aim(0, lookY, 600)` while the pet holds, `wiggle` adds `sx/sy` oscillation `±0.03` at 6 Hz.
- Widget: a 6 px dot at the slot's top-right when `orb.hermes.link.status` is not `"online"` (grey offline, amber degraded/auth).

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Syntax + lint** (command from Task 6 Step 2).
- [ ] **Step 3: Live check (you)** — send your Telegram bot a message; within 20 s the bar orb glances side to side; when Hermes replies it returns to idle. Stop Tailscale (`tailscale down`), within 60 s a grey dot appears; `tailscale up` clears it.
- [ ] **Step 4: Commit** — `feat(hermes): orb mirrors Hermes activity`

---

### Task 8: Tabbed card and Chat tab

**Files:**
- Create: `lib/tabs/chat.luau`
- Modify: `lib/card.luau` (tab row), `roamer.luau` (active tab, keyboard focus, input forwarding), `translations/en.json`

**Interfaces:**
- `card.content(m)` gains `m.tabs = { { id, label } }`, `m.activeTab`, `m.body` (node from the active tab), `m.link` (header dot: green online, amber degraded/auth, grey offline) and `m.banner: { text, action?, onAction? }?` (offline/auth messages). Tab buttons call named globals the roamer defines, one per tab: `onTab_chat`, `onTab_now`, `onTab_chats`, `onTab_memory`, `onTab_agents`, `onTab_cron`.
- Tab ids/order: `chat`, `now`, `chats`, `memory`, `agents`, `cron`; labels in `translations/en.json` under `tabs.*`.
- `chatTab.render(model, cb) -> node` — `model = { chat = orb.hermes.chat, link, colors }`; `ui.scroll({ stickToBottom = true })` of messages (`ui.markdown` for assistant text, muted line per tool `"<name> · <preview>"`), streaming text as a live markdown block, then a row: `ui.input({ key = "hermes-input", submitOnEnter = true, multiline = true, onSubmit = cb.send })`, Stop button while `status` is `sending|thinking|tool|waiting`, New chat button.
- Roamer: on card open `noctalia.layer.configure("roamer", { keyboard = "on_demand" })` and `hermesCmd("tab", { id = <tab> })` (the Chat tab makes the service load history), on close `{ keyboard = "none" }`; card opens on the last used tab (`orb.hermes.tab`). New helper `hermesCmd(verb: string, args: table?)` writes `"<verb>:<nowMs>:<json args>"` to `orb.hermes.cmd`; the existing `send()` for `orb.cmd` stays as is.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Syntax + lint.**
- [ ] **Step 3: Live check (you)** — click the orb, type a question, press Enter: the reply streams in, the orb looks up while thinking; ask for something long and press Stop: it stops and the message reads "stopped"; New chat clears the card.
- [ ] **Step 4: Commit** — `feat(hermes): tabbed card with chat`

---

### Task 9: Now, Chats and Cron tabs

**Files:** Create `lib/tabs/now.luau`, `lib/tabs/chats.luau`, `lib/tabs/cron.luau`; Modify `service.luau` (list fetching per tab), `roamer.luau`

**Interfaces:**
- Service, on `tab:<id>` and every 60 s while that tab shows: `chats` → `Client:api("GET", "/api/sessions?limit=30")` → `views.chatRows`; `cron` → `GET /api/jobs?include_disabled=true` → `views.jobRows`; publishes `orb.hermes.lists`.
- Job commands: `job-run` → `POST /api/jobs/{id}/run`, `job-pause` → `/pause`, `job-resume` → `/resume`, `job-delete` → `DELETE /api/jobs/{id}`; refresh the list after each.
- `nowTab.render(model, cb)` — link state, `agents`/`sessions` counts, our chat status, next cron job (`views.jobRows` row with the smallest `next_run_at`), **Open Hermes Desktop** (`runAsync({ "hermes-desktop" })`).
- `chatsTab.render(model, cb)` — rows (source glyph: `telegram` → `brand-telegram`, `cli` → `terminal-2`, `api-server` → `mood-smile`, `cron` → `clock`, else `message`); tapping a row: `mine` → switch to Chat tab on that session (`Client` adopts the id), else read-only view from `GET /api/sessions/{id}/messages?inline_images=false&limit=50`.
- `cronTab.render(model, cb)` — rows with Run now, Pause/Resume, Delete; Delete needs a second tap within 3 s (button text changes to "Tap again").

- [ ] **Step 1: Implement.** **Step 2: Syntax + lint.**
- [ ] **Step 3: Live check (you)** — Chats lists your Telegram chats with titles; tapping one shows its messages; Cron lists your jobs; Run now fires one (its last run updates after refresh).
- [ ] **Step 4: Commit** — `feat(hermes): now, chats and cron tabs`

---

### Task 10: Memory tab and learned nudge

**Files:** Create `lib/tabs/memory.luau`; Modify `service.luau`, `roamer.luau`, `widget.luau`

**Interfaces:**
- Service: `memory` tab and every 10 min → `Client:dash("GET", "/api/learning/graph")` + `Client:dash("GET", "/api/memory")` → `views.memory`; first load seeds `seen` ids; later loads → `views.newIds` → for each new id publish `orb.hermes.learned = { title, at }` (newest only).
- `memory-delete` → `Client:dash("DELETE", "/api/learning/node", { id = id })`, then refresh.
- Recall: input `onSubmit` → `Client:dash("GET", "/api/sessions/search?limit=20&q=" .. noctalia.string.urlEncode(q))` → rows like Chats (read-only on tap).
- `memoryTab.render(model, cb)` — two fill bars (`fill.memory`, `fill.user`), entries newest first (title, source `MEMORY.md`/`USER.md`), Delete with the same double-tap rule as Cron, recall input + results.
- Roamer and widget watch `orb.hermes.learned`: sparkle (`life:poke("happy", 1200)`) and a speech bubble `"learned: <title>"` for 4 s next to the orb (roamer: `ui.label` in a rounded `ui.row` placed beside the ball in float mode; widget: tooltip text).
- Dashboard login failure → Memory tab banner "Dashboard sign-in failed — check the user in settings and the keyring password".

- [ ] **Step 1: Implement.** **Step 2: Syntax + lint.**
- [ ] **Step 3: Live check (you)** — Memory shows your entries and fill bars; tell Hermes in the Chat tab "remember that my test word is banana"; within 10 min (or on reopening the tab) the orb shows "learned: …"; delete that entry from the tab; it is gone from `~/.hermes/memories/MEMORY.md` on the server.
- [ ] **Step 4: Commit** — `feat(hermes): memory tab and learned nudge`

---

### Task 11: Agents tab

**Files:** Create `lib/tabs/agents.luau`; Modify `service.luau`, `widget.luau`, `roamer.luau`

**Interfaces:**
- Service: `agents` tab → `Client:dash("GET", "/api/profiles")` + `("GET", "/api/profiles/active")` + status `profiles` → `views.agents`.
- `agent-activate` → `Client:dash("POST", "/api/profiles/active", { name = name })` (double-tap confirm), then refresh.
- `agentsTab.render(model, cb)` — one row per agent: name, description, model, active badge, Make active; live counts (`agents`, `sessions`) at the top.
- Widget and roamer: a number badge (`agents`) at the orb's bottom-right when `orb.hermes.activity.agents > 1`.

- [ ] **Step 1: Implement.** **Step 2: Syntax + lint.**
- [ ] **Step 3: Live check (you)** — Agents shows `default` as active, matching the dashboard's Profiles page.
- [ ] **Step 4: Commit** — `feat(hermes): agents tab`

---

### Task 12: Nudges and approvals

**Files:** Modify `service.luau`, `lib/tabs/chat.luau`, `widget.luau`, `roamer.luau`

**Interfaces:**
- Service publishes `orb.hermes.nudge = { kind = "approval"|"cron"|"unread"|nil, count }` — `approval` while `chat.approval`; `cron` when a job row turned `failed` since the Cron tab was last opened (job list also fetched every 10 min in the background); `unread` when a run finished while the card was closed. Opening the matching tab (`approval`/`unread` → chat, `cron` → cron) clears it.
- `approve` → `Client:api("POST", "/v1/runs/" .. runId .. "/approval", json{ request_id = approval.requestId, choice = choice })`, `choice` one of `approval.choices` (`once`, `session`, `always`, `deny`).
- Chat tab: while `chat.approval`, a box above the input with the redacted command and one button per choice (labels: Allow once, Allow this session, Always allow, Deny).
- Widget and roamer: an 8 px dot at the orb's top-right — amber approval, red cron, accent unread (precedence in that order); the roamer face uses pet `waiting` while approval is pending.

- [ ] **Step 1: Implement.** **Step 2: Syntax + lint.**
- [ ] **Step 3: Live check (you)** — ask Hermes from the orb to run `rm -rf /tmp/orb-test-dir`; the amber dot and Allow/Deny appear; Deny → the reply says it was blocked. Close the card, send a question via `noctalia msg plugin shadow/orb:service all hermes-send "say hi"`, the accent dot appears and clears when you open the Chat tab.
- [ ] **Step 4: Commit** — `feat(hermes): nudges and approvals`

---

### Task 13: Docs and final checks

**Files:** Modify `README.md` (Hermes section: setup = Task 0 commands, tabs, nudges, limits from spec §2), spec §10 (mark items 1 and 6 resolved: events carry `run_id`; approvals arrive as `approval.request` on the session stream).

- [ ] **Step 1: Write the README section.**
- [ ] **Step 2: Full verification** — `./tests/run.sh` (all pass), syntax loop, `noctalia plugins lint .` (`0 errors, 0 warnings`), disable/enable the plugin, then the Task 7–12 live checks once more in order.
- [ ] **Step 3: Commit** — `docs(hermes): README and spec updates`
