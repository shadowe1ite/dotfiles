# Interceptor Recipes

Worked procedures for common tasks. Each assumes `INTC` is resolved (see skill.md) and the daemon is running (`interceptor status`). Substitute `"$INTC"` for `interceptor`.

---

## Verify a deploy / check a page renders

```bash
interceptor open "https://your-app.com/feature" --full   # tab + wait + tree + text
interceptor find "Expected heading"                       # confirm key content exists
interceptor inspect --net-only                            # confirm API calls succeeded (no 4xx/5xx)
```
Then read the tree/text for the specific thing you're verifying. Screenshot only if you need to confirm *visual* layout: `interceptor screenshot --save`.

## Extract a value off a live page (incl. SPA state)

```bash
interceptor open "https://site.com/dashboard" --text-only --full
# If the value is rendered from an API response rather than static text:
interceptor net log --filter dashboard --limit 20
# Or pull it from a known element:
interceptor find "Balance" && interceptor read e12 --text-only
```
For values only in JS state, `interceptor eval "JSON.stringify(window.__STATE__)"` (isolated world) or `--main` if it must read page globals.

## Fill and submit a form

```bash
interceptor open "https://site.com/signup"
interceptor find "Email" --role textbox        # → e7
interceptor act e7 "user@example.com"
interceptor find "Password" --role textbox     # → e9 (refs may shift; re-find)
interceptor act e9 "hunter2"
interceptor find "Sign up" --role button       # → e11
interceptor act e11                            # click + re-read; inspect the diff
```
If a click "did nothing," run `interceptor inspect` before retrying. If a ref went stale, re-`find`.

## Drive a rich/canvas editor (Canva, Google Docs/Slides)

```bash
interceptor scene profile --verbose            # detect the editor; confirm support
interceptor scene list                         # enumerate objects (filter --type shape|text|image)
interceptor scene click <id>                   # select an object by scene id
interceptor scene text                         # read Docs/Slides text
interceptor scene insert "New text here"       # type into focused writable surface
interceptor scene slide goto 4                 # Slides: navigate deck (0-indexed)
interceptor scene render <id> --save           # render an object to PNG
```
Plain DOM `read`/`act` won't see canvas-rendered objects — always go through `scene` for these.

## Observe network traffic (passive — no debugger)

```bash
interceptor net clear                           # flush buffer, then trigger the action
interceptor act e5                              # do the thing that fires requests
interceptor net log --filter api --limit 50     # see captured fetch/XHR
interceptor net headers --filter api            # grab CSRF / auth headers
```
Only escalate to CDP (`interceptor network on …`) if passive capture misses what you need.

## Download all JS (or static assets) a page loaded from a domain

`net log` is the WRONG tool here — passive `net` only captures fetch/XHR, **not** `<script>`/`<link>`/document loads, so it returns nothing (or times out) for bundle files. Enumerate via the Performance API instead, then download with `curl` (static assets under `/static/…` are usually public, no auth needed).

```bash
interceptor open "https://target.com"
# Enumerate loaded JS for the domain. Use --main: strict CSP (no 'unsafe-eval')
# blocks isolated-world eval; the page's own world is exempt.
interceptor eval "JSON.stringify([...new Set(performance.getEntriesByType('resource').map(e=>e.name).filter(n=>/^https:\/\/target\.com\//.test(n) && /\.js(\?|\$)/.test(n)))])" --main > urls.json
# Download in parallel (basename strips the ?query); verify HTTP codes after.
mkdir -p js && python3 -c "import json;print('\n'.join(json.load(open('urls.json'))))" \
  | xargs -P8 -I{} sh -c 'curl -sS -A "Mozilla/5.0" -o "js/$(basename "${1%%\?*}")" -w "%{http_code} %{url_effective}\n" "$1"' _ {}
```
Caveats:
- This captures only what the **current page state** loaded. Code-split SPAs lazy-load chunks on sign-in / opening tools — interact to trigger more, then re-enumerate. For the *complete* manifest of unreferenced chunks, use the `lazy_chunk_downloader` skill.
- Don't `export -f` or run `xargs` with a bash function from an interactive zsh — it dumps the whole function table into output. Use a plain `sh -c` one-liner as above.

## Override a request before it hits the server

Passive param override (no CDP), e.g. bump a page-size limit:
```bash
interceptor override "*api/list*" limit=200 offset=0
interceptor act e5                              # re-trigger the request
interceptor net log --filter api/list           # confirm the override applied
interceptor override clear                       # always clean up after
```
For body/status/header rewrites, use CDP: `interceptor network override on '<json>'` … `interceptor network override off`.

## Capture a streaming response (SSE) or a ChatGPT answer

```bash
interceptor sse streams                          # see active streams
interceptor sse tail --filter chat               # live-tail chunks
interceptor sse log --filter chat --limit 5      # completed streams

# ChatGPT bridge:
interceptor chatgpt send "Summarize this" --stream
interceptor chatgpt read
```

## Screenshot for a VLM check

```bash
interceptor screenshot --save --format webp --quality 60   # budgeted, on-disk
interceptor screenshot --element 12 --save                  # just one element
interceptor screenshot --full --save                        # whole scrollable page
```
Prefer tree/text reads first; reach for pixels only when layout/visual correctness is the actual question.

## Record a user flow and replay it

```bash
interceptor monitor start --instruction "log in and open settings"
# (user performs the flow in the browser)
interceptor monitor stop
interceptor monitor list                          # find the sessionId
interceptor monitor export <sessionId> --plan     # emit a runnable interceptor script
```
Run the emitted plan back to replay. `--with-bodies` merges cached response bodies into the export.

---

# macOS recipes

## Screenshot a backgrounded / occluded app (no focus change)

```bash
interceptor macos trust                                  # confirm Screen Recording granted
interceptor macos apps                                   # exact app name
interceptor macos screenshot --app "Finder" --save --target-max-long-edge 1568
```
CGS capture works even if the window is occluded, minimized, or on another Space. Never `app activate` just to screenshot.

## Drive a backgrounded native app (click/type without raising it)

```bash
interceptor macos trust                                  # Accessibility must be granted
interceptor macos tree --app "TextEdit" --filter interactive --depth 6
interceptor macos act e5                                 # AX press, no focus change
interceptor macos type e3 "hello"                        # AX value-set
interceptor macos keys "Meta+S" --app "TextEdit"         # routed keystroke via postToPid
```
Refs change as the AX tree updates — re-read before acting. Escalate to `--os` only if AX input is filtered.

## Read the AX tree of any app (incl. Electron)

```bash
interceptor macos tree --app "Cursor"     # auto-wakes Electron via AXManualAccessibility
interceptor macos find "Run" --app "Cursor" --role button
```

## Dispatch an Apple Event to a named app

```bash
interceptor macos intent warmup com.brave.Browser
interceptor macos intent dispatch --bundle com.brave.Browser \
  --script 'tell application "Brave Browser" to return URL of active tab of front window'
```
Do NOT put `activate` in the script unless the user asked to foreground the app. First dispatch per bundle prompts for Apple Events consent.

## On-device vision / speech / NLP

```bash
interceptor macos vision text --app "Preview"            # OCR a window
interceptor macos nlp entities "Tim Cook visited Cupertino"
interceptor macos nlp sentiment "this is great"
interceptor macos ai prompt "Summarize the frontmost window"   # macOS 26+
```

## Record & replay a native flow

```bash
interceptor macos monitor start --instruction "file an expense" --app "Numbers"
# (user performs the flow)
interceptor macos monitor stop <sid>
interceptor macos monitor export <sid> --plan
```

---

## Cleanup checklist

After a task, undo anything global you turned on so the user's session is left clean:
- `interceptor override clear`
- `interceptor network off` / `interceptor network override off` (if you attached CDP)
- `interceptor headers clear` (if you added header rules)
- `interceptor monitor stop` / `interceptor macos monitor stop <sid>` (if still recording)
- `interceptor macos overlay close` (if you created an overlay)
