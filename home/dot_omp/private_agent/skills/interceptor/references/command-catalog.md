# Interceptor Command Catalog

Full command surface, verified against `interceptor help` / `interceptor macos` (v0.6.x). Plain text output by default; append `--json` only when piping to a script. Prefix every command with the resolved binary (`"$INTC"` — see skill.md).

---

# BROWSER SURFACE  (`interceptor <cmd>`)

## Compound (agent-optimized — prefer these)

```
interceptor open <url>                  Open URL, wait for stable, return tree + text
  --tree-only | --text-only             Return only one
  --full                                Full text instead of 2000-char summary
  --timeout <ms>                        Override wait-stable (default 5000)
  --no-wait                             Return immediately after tab creation
  --activate                            Foreground the new tab (focus change)
  --reuse                               Reuse the current tab instead of new
interceptor read [ref]                  Tree + text for active tab (or element subtree)
  --tree-only | --text-only
interceptor act <ref>                   Click + wait + return updated tree + diff
interceptor act <ref> "value"           Type into field + wait + updated tree
  --os                                  Use OS-level trusted input (escalation)
  --keys "Enter"                        Send a keyboard shortcut instead
  --no-read                             Skip post-action tree read
interceptor inspect                     Tree + text + network log + headers
  --net-only                            Only network data
```

## State / read

```
interceptor state [--full]              DOM tree + metadata (--full adds static text)
interceptor tree                        Semantic accessibility tree
  --filter all                          Include landmarks + headings
  --depth N --max-chars N               Limit depth / output size
interceptor diff                        Changes since last state/tree read
interceptor find "query" [--role button]  Find elements by name (optionally role)
interceptor text [index|ref]            All visible text (or one element's)
interceptor html <index|ref>            HTML of a specific element
```

## Actions

```
interceptor click <index|ref>           Click (e.g. click e5)
  --at X,Y                              Click at coords on the element
interceptor dblclick <index> --at X,Y
interceptor rightclick <index> --at X,Y
interceptor type <index|ref> <text>     Type (clears first)
  --append                              Type without clearing
interceptor type "role:name" <text>     Type using a semantic selector
interceptor select <index|ref> <value>  Select a dropdown option
interceptor focus <index|ref>
interceptor hover <index|ref> [--from X,Y]
interceptor drag <index> --from X,Y --to X,Y [--steps 20] [--duration 500]
interceptor keys <combo>                Keyboard shortcut, e.g. "Control+A"
```

## Navigation / tabs

```
interceptor navigate <url>              Go to URL (current tab)
interceptor back | forward
interceptor scroll <up|down|top|bottom>
interceptor wait <ms>
interceptor tabs                        List tabs
interceptor tab new [url] [--activate]
interceptor tab close [id]
interceptor tab switch <id>             FOCUS CHANGE
```

## Capture / eval

```
interceptor screenshot                  Viewport screenshot (returns data URL)
  --save                                Also save to disk
  --format png                          (default jpeg)
  --quality 80                          JPEG quality 0-100 (default 50)
  --full                                Full-page scroll + stitch
  --clip X,Y,W,H                        Region
  --element N                           Element bounding rect
interceptor eval <code>                 Run JS in an isolated world
interceptor eval <code> --main          Run JS in page context (see cautions below)
```

**CSP gotcha:** on sites with a strict `script-src` (no `'unsafe-eval'`) — e.g. Adobe, Google — isolated-world `eval` fails with `Evaluating a string as JavaScript violates the following Content Security Policy directive`. `--main` runs in the page's own world and is exempt, so fall back to it for read-only enumeration too (e.g. `performance.getEntriesByType('resource')`).

**`eval --main` cautions:** runs in the page's own world. Use for canvas-rendered editor input, monkey-patching protocol sniffers, or dispatching events that must look real — tag dispatched events with `event.__interceptor_trust = true` to satisfy per-event `isTrusted` checks. Prefer a named compound command when one already covers the task.

## Cookies / headers

```
interceptor cookies <domain>            List cookies
interceptor cookies set <json>
interceptor cookies delete <url> <name>
interceptor headers add <name> <value>  Add a request header rule
interceptor headers remove <name>
interceptor headers clear
```

## Network — three layers, pick the least invasive

**Passive (`net`)** — always-on capture of fetch/XHR, no debugger. **Start here.**
```
interceptor net log [--filter <pat>] [--since <ts>] [--limit <n>]
interceptor net clear
interceptor net headers [--filter <pat>]   Captured request headers (CSRF, auth tokens)
```

**Passive request override (`override`)** — rewrite query params, no CDP.
```
interceptor override "*pattern*" key=value          Override a query param on matches
interceptor override "*api*" limit=50 offset=0      Multiple params
interceptor override clear
```

**CDP (`network`)** — explicit opt-in; attaches the debugger. Use only when passive isn't enough.
```
interceptor network on [patterns...]     Start intercepting
interceptor network off
interceptor network log
interceptor network override on '<json>'  Rewrite matching requests before they leave
interceptor network override off
```

## SSE streams

```
interceptor sse log [--filter <pat>] [--limit N]   Completed SSE streams
interceptor sse streams                             List active streams
interceptor sse tail [--filter <pat>]               Live-tail stream chunks
```

## Scene graph — rich/canvas editors (Canva, Google Docs/Slides/Sheets)

When DOM refs aren't enough (canvas-rendered surfaces):
```
interceptor scene profile [--verbose]    Detect editor strategy/profile
interceptor scene list [--type image|shape|text|page|embed|slide]
interceptor scene click <id> | dblclick <id> | select <id>
interceptor scene hit <x> <y>            Identify object at viewport coords
interceptor scene selected                Read current selection
interceptor scene text [--with-html]      Read text from the editor surface
interceptor scene insert "<text>"         Insert into focused writable surface
interceptor scene cursor-to <x> <y>
interceptor scene slide list | current | goto <index> | notes [--slide N]
interceptor scene render <id> [--save]    Render an object as PNG
interceptor scene zoom
interceptor scene <cmd> --profile <name>  Force a profile (bypass detection)
```

## Canvas elements / stream capture / batch

```
interceptor canvas list | read N [--format png] [--region X,Y,W,H] [--webgl]
interceptor canvas diff <url1> <url2> [--threshold 10] [--image]
interceptor capture start | frame | stop          tabCapture stream
interceptor batch '<json_array>' [--stop-on-error] [--timeout 30000]
interceptor wait-stable [--ms 500] [--timeout 3000]
```

## Monitor (record) + replay

```
interceptor monitor start ["<instruction>"]   Record user actions on active tab
  --instruction "..."                          Annotate intent for replay
interceptor monitor stop | pause | resume
interceptor monitor status [--all] | list | tail [--raw] [--current]
interceptor monitor export <sessionId>         Aligned text
  --json | --plan | --with-bodies              Raw JSONL / replay script / merge bodies
```

## ChatGPT bridge

```
interceptor chatgpt send "<prompt>" [--stream]
interceptor chatgpt read | status | conversations
interceptor chatgpt switch <conversation-id>
interceptor chatgpt model [name]
interceptor chatgpt stop
```

## Other browser flags

```
--json                Machine-parseable output
--include-frames      Walk iframes in the DOM tree (for read/tree)
--any-tab             Operate outside the tracked tab group (needs explicit user OK)
```

---

# macOS SURFACE  (`interceptor macos <cmd>`)

Requires `mode: full`. Background-first: only `macos app activate` and `macos open --activate` change focus. Check `interceptor macos trust` before input.

## Compound

```
interceptor macos open "Finder" [--activate]   Tree + windows
interceptor macos read --app "Mail"            AX tree (other app stays focused)
interceptor macos act <ref> ["value"]          AX press / AX value-set
interceptor macos inspect [<ref>]              Tree + apps + frontmost
```

## Apps + windows

```
interceptor macos apps
interceptor macos windows --app "Brave Browser"
interceptor macos app activate "X"             FOCUS CHANGE — only when user asks
interceptor macos app hide | unhide | quit "X"
interceptor macos app move "X" 0 0 | app resize "X" 1440 900
interceptor macos frontmost
interceptor macos move <ref> --width N --height M
interceptor macos resize <ref> --width N --height M
```
Refs churn after geometry changes — refresh from `windows`.

## Tree / find / focused

```
interceptor macos tree --app "X"               Auto-wakes Electron apps
  --filter interactive|all|labels --depth 6
interceptor macos find "Save" --app "X" [--role button]
interceptor macos focused --app "X"
interceptor macos value <ref> | action <ref> | inspect <ref> | menu --app "X"
```

## Input (AX-first; --app/--pid routes via postToPid)

```
interceptor macos click <ref>                  AX press
interceptor macos click 100,200 --app "X"      Coordinate click via postToPid
interceptor macos type <ref> "..."             AX value-set (text roles)
interceptor macos type "..." --app "X"
interceptor macos keys "Meta+S" --app "X" | --pid 1234
interceptor macos scroll down 400 --app "Mail" --times 5 --interval-ms 80
interceptor macos drag 100,100 200,200 --app "X"
interceptor macos type/keys "..." --os         OS-level escalation (follows frontmost)
```

## Capture + screenshot

```
interceptor macos screenshot --app "X" --save --target-max-long-edge 1568
interceptor macos screenshot --window <ref> | --region X,Y,W,H
interceptor macos capture start | status | frame | stop
interceptor macos stream start | list | frame | stop
interceptor macos display
```
CGS capture works on occluded / minimized / cross-Space windows. Avoid `--mode display` for app-specific captures.

## Apple Events (intent)

```
interceptor macos intent dispatch --bundle <id> --script '<applescript>'
interceptor macos intent warmup com.brave.Browser com.apple.mail
```
Never include `activate` in the script unless the user asked to foreground. First dispatch per app prompts for consent.

## Vision / speech / NLP / AI

```
interceptor macos vision text|faces|hands|bodies
interceptor macos listen | vad | sounds | audio output
interceptor macos audio input start [--save] | stop
interceptor macos nlp entities|language|sentiment|tokens|similar|embed
interceptor macos ai status|prompt|session            macOS 26+ FoundationModels
interceptor macos sensitive check|monitor
```

## System / data / docs

```
interceptor macos log query --predicate '<NSPredicate>'     OSLogStore (system-wide)
interceptor macos fs read|write|search [--scope home|workspace|granted|<path>]
interceptor macos files watch --watch-path <p>
interceptor macos url get <url> | post <url> --body '...'
interceptor macos notifications tail|log|post|schedule-*|pending|delivered|badge
interceptor macos calendar|reminders|contacts|photos|location|music|maps|share <...>
interceptor macos pdf info|text|outline|annotations|forms|find|merge|split <path>
interceptor macos detect types|run|file | translate text|languages|file | thumbnail <path>
```

## Overlays / container / intents / auth

```
interceptor macos overlay create --html '<...>' --duration 5 | list | close
interceptor macos container run                       macOS 26+
interceptor macos appintent list|registered|donate|update-parameters|supports
interceptor macos auth status|confirm "<reason>"|invalidate|domain-state
```
Panic hotkey `Ctrl+Opt+Cmd+Escape` closes every active overlay.

## Trust / permissions

```
interceptor macos trust                  Current TCC grant snapshot (read-only by default)
interceptor macos trust --no-prompt      Force read-only snapshot
interceptor macos trust --prompt         Fire all three TCC prompts
interceptor macos trust --walkthrough    Prompt + open the Settings pane
interceptor macos trust --accessibility-prompt | --screen-prompt | --microphone-prompt
```

## Monitor (record) + replay — native

```
interceptor macos monitor start --instruction "..."
  --app | --apps a,b | --all-apps                       Scope
  --include clipboard|files|network|log|notifications|speech
  --frames N --vision-text --watch-path <p> --log-predicate "<NSPredicate>"
interceptor macos monitor status | list | tail <sid> [--raw] | pause | resume | stop <sid>
interceptor macos monitor export <sid> [--plan | --with-bodies | --json]
```
