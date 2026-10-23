# Orb × Hermes — design

Date: 2026-10-23 · Status: draft for review · Plugin: `shadow/orb` (Noctalia, `plugin_api` 36)

## 1. Goal

The orb becomes Hermes's body on the desktop: one glance shows what Hermes is doing anywhere,
one click talks to it, and it nudges when something needs you.

**Done when**

- The orb's face follows Hermes activity on every surface (CLI, Telegram, cron, Desktop) within
  ~5 s while the card is open, ~20 s while closed.
- From the card you can chat with Hermes (streamed reply, Stop, New chat), browse recent chats
  from every platform, see what Hermes remembers and delete a wrong entry, see your agents and
  switch the active one, and run / pause cron jobs.
- An unread reply, a failed cron job, or a pending approval shows as a dot on the orb.
- No secret is stored in Noctalia's `settings.toml`.

## 2. Not in scope

| Not doing | Why |
|---|---|
| Voice, wake word, TTS | User asked for none |
| Typing into an existing Telegram / Desktop / CLI chat | API server refuses sessions another surface owns (`permission_denied`); attaching needs the dashboard WebSocket, and Noctalia plugins have no WebSocket |
| `/handoff` | CLI-only command (official slash-command reference); not callable over HTTP |
| Creating / editing cron jobs (v1) | List, run, pause, resume, delete only; creation later (dashboard blueprints exist) |
| Chatting with non-default agents (v1) | Each profile needs its own `API_SERVER_KEY` for `/p/<profile>/` routing; v1 talks to `default` |
| Approving staged memory writes | No REST endpoint (`/memory approve` is a chat command); view and delete only |

## 3. Facts this design rests on

**Your Hermes** (probed 2026-10-23): runs on `server.tailf72995.ts.net`, v0.21.7. Dashboard backend
(`hermes serve`) on `:9119`, password login (`auth_providers: ["basic"]`), gateway running with
Telegram connected. API server **not enabled** (`:8642` refuses). One profile: `default`.

**Hermes surfaces** (official docs + `gateway/platforms/api_server*.py`, `hermes_cli/web_routers/*`):

| Surface | Auth | What we use |
|---|---|---|
| API server `:8642` | `Authorization: Bearer <API_SERVER_KEY>` | `/api/sessions` (list all sessions, any source), `/api/sessions/{id}/messages`, `POST /api/sessions`, `POST /api/sessions/{id}/chat/stream` (SSE), `/v1/runs/{id}/stop`, `/v1/runs/{id}/approval`, `/api/jobs` (+ `/run`, `/pause`, `/resume`, `DELETE`), `/health` |
| Dashboard `:9119` public | none | `GET /api/status` → `active_agents`, `active_sessions`, `gateway_busy`, `profiles`, `components`, `overall` |
| Dashboard `:9119` gated | session cookie from `POST /auth/password-login` | `GET /api/learning/graph` (memory + learned-skill nodes: `id`, `label`, `kind`, `timestamp`, `memorySource`), `DELETE /api/learning/node`, `GET /api/memory` (file sizes), `GET /api/sessions/search`, `GET /api/profiles`, `GET/POST /api/profiles/active` |

**Noctalia limits that shape it**: `noctalia.http` / `httpStream` do HTTP and line streaming (SSE)
but return no response headers (so no cookies) and there is no WebSocket. The dashboard ignores
the session-token header when password login is on (cookie auth is authoritative), so gated
dashboard calls go through `curl` with a private cookie jar, which also follows cookie rotation.

## 4. Features

### 4.1 Alive — the orb mirrors Hermes

Poll `GET /api/status` (public). Map to the pet states Hermes itself uses (`pets.md`):

| Signal | Pet state | Orb face |
|---|---|---|
| nothing active | `idle` | normal idle life (blink, glance, breathe) |
| our stream: `tool.progress` `_thinking` / no tool yet | `review` | eyes drift up, slower blinks |
| our stream: `tool.started` | `run` | quick glances side to side, small wiggle |
| other surfaces busy (`gateway_busy` or `active_agents > 0`) and nothing of ours running | `run` (soft) | slow side glances |
| our turn `run.completed` | `wave` | happy `^ ^` for 1.5 s |
| our turn `run.failed` / `run.cancelled` | `failed` | surprised + short shake |
| approval pending on our run | `waiting` | looks straight at you, attention dot |

Online dot: green when `/api/status` answers with `overall: ok`, amber when degraded, grey when
unreachable. Shown on the card header and, when not green, as a small dot on the bar orb.

### 4.2 Talk — chat in the card

- One ongoing **orb chat** (an API-server session). Its id lives in
  `pluginDataDir()/hermes.json`; **New chat** creates a fresh one (`POST /api/sessions`).
- Send: `POST /api/sessions/{id}/chat/stream` with `{"input": text}` via `httpStream`.
  Events: `run.started`, `assistant.delta` (`delta`), `tool.progress` (`tool_name`, `delta`),
  `tool.started`/`tool.completed`/`tool.failed`, `assistant.completed`, terminal
  `run.completed`/`run.failed`/`run.cancelled`. Lines starting with `:` are keepalives.
- Reply renders with `ui.markdown`, streamed text throttled to ≤ 10 renders/s. Tool activity
  shows as one muted line per tool ("terminal · `ls src/`").
- **Stop**: `POST /v1/runs/{run_id}/stop` when the stream gave a run id; otherwise `stream.stop()`.
- History on open: `GET /api/sessions/{id}/messages?inline_images=false`.
- Typing: while the card is open the roamer layer switches to `keyboard = "on_demand"`
  (`noctalia.layer.configure`), back to `"none"` when it closes.

### 4.3 Glance — Now, Chats, Cron

- **Now**: online state, active agents/sessions, our current run, next cron job.
- **Chats**: `GET /api/sessions?limit=30` across all sources; row = title or preview, source
  icon (telegram, cli, desktop, cron, api-server), last active. Tap a row: read-only messages.
  Rows that are the orb's own chats open in the Chat tab instead.
- **Cron**: `GET /api/jobs`; row = name, schedule, next run, last status. Buttons: Run now,
  Pause/Resume, Delete (Delete asks once in the card).
- **Open Hermes Desktop** button: `noctalia.runAsync({ "hermes-desktop" })`.

### 4.4 Memory — what Hermes knows

- `GET /api/learning/graph`: memory nodes (from `MEMORY.md` / `USER.md`) and learned skills,
  newest first. `GET /api/memory` sizes give the fill bars against the 2,200 / 1,375 char limits.
- **Delete** a memory node (`DELETE /api/learning/node`, asks once in the card).
- **Learned nudge**: refresh the graph every 10 min; a memory node id not seen before makes the
  orb sparkle and shows "learned: <label>" in a speech bubble for 4 s.
- **Recall**: full-text search over past chats on every platform with the dashboard's
  `GET /api/sessions/search` (gated, so it goes through the curl client); a hit opens that chat
  read-only.

### 4.5 Agents — who's working

- Agent names from public `/api/status.profiles`; details (description, model) from gated
  `GET /api/profiles`; active one from `GET /api/profiles/active`.
- **Switch active**: `POST /api/profiles/active` (asks once — it changes what the Desktop app
  and dashboard use).
- Live count: `active_agents` / `active_sessions`; the orb shows a small number badge when > 1.

### 4.6 Nudges

Dot on the orb (bar and out), highest wins: approval pending (amber) › cron failure since last
look (red) › unread orb reply (accent). Opening the matching tab clears it.
Approval card: the run's `pending_controls` → **Allow once** / **Deny**
(`POST /v1/runs/{run_id}/approval` with `request_id`, `execution_generation`, `choice`).

## 5. Architecture

```
widget.luau ──┐                      ┌── lib/hermes.luau   (pure: requests, SSE parser,
roamer.luau ──┼── noctalia.state ────┤                       normalizers, pet-state map)
 (card tabs)  │   orb.hermes.*       └── service.luau      (owns network, secrets, polling,
              └──────────────────────────────────────────    chat stream, curl client)
lib/tabs/{chat,now,chats,memory,agents,cron}.luau — pure render functions (model → ui tree)
```

| Unit | Does | Depends on |
|---|---|---|
| `lib/hermes.luau` | URL + request tables, SSE line parser (event/data framing), JSON → view models, activity → pet state | nothing (unit-tested with the luau CLI) |
| `service.luau` (grows) | reads secrets via `secret-tool`, polls status, runs the chat stream, calls API server + curl dashboard client, publishes `orb.hermes.*`, handles `orb.hermes.cmd` | `lib/hermes.luau` |
| `lib/tabs/*.luau` | one tab each: `render(model, callbacks) → ui tree` | `lib/face.luau` colors |
| `lib/card.luau` | card frame grows a tab row; content comes from the active tab | `lib/tabs/*` |
| `roamer.luau` | picks the tab, forwards input to the service, keyboard focus while open | state keys |
| `widget.luau` | nudge dot, activity mood in the bar | state keys |

`roamer.luau` is already ~700 lines; the tabs live in `lib/tabs/` so it does not grow further.

**State keys** (service → UI unless noted):

| Key | Shape |
|---|---|
| `orb.hermes.link` | `{ status = "online"\|"degraded"\|"offline"\|"auth", detail }` |
| `orb.hermes.activity` | `{ pet = "idle"\|"review"\|"run"\|"wave"\|"failed"\|"waiting", agents, sessions }` |
| `orb.hermes.chat` | `{ sessionId, messages = {...}, streaming = text?, tools = {...}, runId?, status }` |
| `orb.hermes.lists` | `{ chats = {...}, jobs = {...}, memory = {...}, agents = {...}, at = ms }` |
| `orb.hermes.nudge` | `{ kind = "approval"\|"cron"\|"unread"\|nil, count }` |
| `orb.hermes.cmd` (UI → service) | `"<verb>:<ms>:<json args>"`, verbs: `send`, `stop`, `new`, `refresh`, `job-run`, `job-pause`, `job-resume`, `job-delete`, `memory-delete`, `agent-activate`, `approve` |

**Polling**: status every 5 s while the card is open, 20 s while closed; lists on tab open and
every 60 s while that tab is shown; learning graph every 10 min; nothing else in the background.

## 6. Secrets and settings

- Keyring (`secret-tool`), read by the service at start and on 401:
  - `service orb-hermes kind api-key` — the API server key
  - `service orb-hermes kind dashboard-password` — the dashboard password
- New plugin settings (non-secret): **Hermes server** (default
  `http://server.tailf72995.ts.net`), **API port** (8642), **Dashboard port** (9119),
  **Dashboard user**.
- curl cookie jar: `pluginDataDir()/dashboard.cookies`, created under `umask 077`. Logged-in
  dashboard calls: `curl -s -b jar -c jar` in argv form (no shell interpolation).
- Never logged: keys, password, cookie values. `dependencies` gains `curl` and `libsecret`.

## 7. Errors

| Case | Behavior |
|---|---|
| server unreachable | grey dot, card banner "Can't reach Hermes" + Retry; polling backs off to 60 s |
| 401 on API server | banner "API key rejected" + how to fix (keyring command); no retry loop |
| dashboard login fails | Memory/Agents tabs show "Dashboard sign-in failed"; other tabs keep working |
| 429 (concurrent-run cap) | "Hermes is busy" + retry in 5 s |
| stream closes without terminal event | message marked "interrupted", Retry button |
| `run.failed` with `iteration_budget_exhausted` | show the partial answer with "stopped early" |

## 8. Testing

- Unit (luau CLI, `tests/run.sh`): SSE parser fed recorded event lines (deltas, tool events,
  keepalives, terminal events, partial lines), every normalizer, the pet-state map.
- Live checks per phase over IPC: `noctalia msg plugin shadow/orb:service all hermes-<verb>`
  (status, send, refresh) plus the log.
- Manual visual checks by you per phase (one-line checklist in each phase).

## 9. Phases

| # | Delivers | Acceptance |
|---|---|---|
| 0 | Server: API server on Tailscale; keys in local keyring (you, with exact commands below) | `curl -H "Authorization: Bearer …" http://server…:8642/health` → ok |
| 1 | Alive: link + activity → orb face, online dot | Send a Telegram message → orb looks busy within 20 s |
| 2 | Talk: chat tab with streaming, Stop, New chat, keyboard focus | Ask a question from the orb; reply streams; Stop works |
| 3 | Glance: Now, Chats, Cron tabs | Your Telegram chats listed; Run now on a job fires it |
| 4 | Memory: entries, fill bars, delete, learned nudge, recall filter | Delete a test entry; it is gone from `MEMORY.md` |
| 5 | Agents: list, active, switch, live count | Active agent shown matches the dashboard |
| 6 | Nudges: approval / cron-failure / unread dots, Allow/Deny | A gated command shows Allow/Deny on the orb |

**Phase 0 commands** (run on the server, then locally):

```sh
# server: enable the API server on the Tailscale address only
TS_IP=$(tailscale ip -4)
cat >> ~/.hermes/.env <<EOF
API_SERVER_ENABLED=true
API_SERVER_HOST=$TS_IP
API_SERVER_KEY=$(openssl rand -hex 32)
EOF
chmod 600 ~/.hermes/.env
hermes gateway restart
grep API_SERVER_KEY ~/.hermes/.env          # copy the value

# local: store the key and the dashboard password in the keyring
secret-tool store --label='Orb: Hermes API key' service orb-hermes kind api-key
secret-tool store --label='Orb: Hermes dashboard password' service orb-hermes kind dashboard-password
```

## 10. To confirm while building

1. `chat/stream` exposes a run id usable with `/v1/runs/{id}/stop` (check `run.started` payload;
   fall back to closing the stream).
2. API-server `/api/sessions/{id}/messages` reads sessions from other sources (listing does;
   reading expected to, as only *binding* is refused).
3. Dashboard accepts the cookie-jar session for `/api/learning/*` and `/api/profiles/*` via curl.
4. `hermes gateway restart` is the right restart for your server's service setup (systemd unit
   vs manual).
5. Card size for chat: tabs need ~420 × 540; the card width/height settings get those defaults.
6. Approval prompts on a `chat/stream` run: the Runs API emits `approval.request` and parks the
   run in `waiting_for_approval`; confirm the session stream surfaces it (else poll
   `GET /v1/runs/{run_id}` for `pending_controls` while a turn is running).
