---
name: interceptor
description: Drive a real signed-in Chrome/Brave browser session AND native macOS apps from the command line via the `interceptor` CLI. Use when asked to control the browser, read/click/type on a live page, verify a deploy, fill a form, observe or override network traffic, capture SSE/ChatGPT streams, automate rich editors (Canva/Google Docs/Slides), screenshot a tab or app, read AX trees, drive/screenshot native macOS apps (Finder, Mail, etc.), run on-device vision/speech/NLP, dispatch Apple Events, or record-and-replay a browser or native flow. Operates inside the user's existing logged-in session — preserves cookies and auth.
---

# Interceptor

`interceptor` is an agent-driven automation CLI with two surfaces sharing one daemon:

- **Browser** (`interceptor <cmd>`) — drives the user's real, logged-in Chrome/Brave tab. Reads the DOM/accessibility tree, clicks/types, observes network (fetch/XHR/SSE), overrides requests, automates canvas-based rich editors, records & replays flows. Operates **inside the existing session** — cookies and auth are intact. No CDP unless you opt in.
- **macOS** (`interceptor macos <cmd>`) — drives native apps via the Accessibility (AX) tree + OS-level input. Captures occluded/minimized windows, runs on-device Vision/Speech/NLP, dispatches Apple Events, records & replays native flows.

## Binary resolution (IMPORTANT)

The CLI is **not on `PATH`** in this environment. Resolve it first:

```bash
INTC="$(command -v interceptor || echo "$HOME/.interceptor/bin/interceptor")"
"$INTC" status
```

Use `"$INTC" …` for every command below. (If a repo clone is present and you're inside it, `./dist/interceptor` also works.) The examples below write `interceptor` for readability — substitute `"$INTC"`.

## Always start here

```bash
interceptor status      # Confirm daemon is running (and which surface mode)
```

- `daemon: running` → good to go.
- If macOS commands fail with "requires full computer-use install", the install is **browser-only**. Tell the user to run `interceptor upgrade --full`; do not retry the macos command.
- For native input, first check `interceptor macos trust` (TCC: Accessibility / Screen Recording / Microphone). Don't fire `--prompt` unprompted.

## Core operating rules

1. **Compound commands over low-level verbs.** Prefer `open` / `read` / `act` / `inspect` — each does the multi-step thing (navigate+wait+read, click+wait+re-read) in one call.
2. **Structured reads over screenshots.** The DOM/AX tree and `text` are what the model consumes best. Only screenshot when you genuinely need pixels (visual layout, canvas, a VLM check). See `references/command-catalog.md` for the screenshot budget.
3. **Plain text by default.** Add `--json` ONLY when piping into a script. JSON costs more tokens and hurts comprehension otherwise.
4. **`eN` refs are short-lived.** Refs (`e5`, framed `e2_7`) come from `read`/`tree`/`find`. They survive layout flicker but NOT navigation or node removal. On "stale element," re-run `read`/`find` for a fresh ref before acting.
5. **Background-first by contract.** Routine work never steals the user's focus. The ONLY focus-moving verbs are: browser — `open --activate`, `tab new --activate`, `tab switch`, `window focus`; macOS — `macos app activate`, `macos open --activate`. Everything else (read, click, type, screenshot, net, scroll, capture, AX) runs invisibly. If focus changes otherwise, that's a bug.
6. **Use the real session.** No clean/isolated profiles unless the user asks. Don't use `--any-tab` unless explicitly authorized — Interceptor works in its own tracked tab group.
7. **Synthetic input first.** Browser `act`/`click`/`type` already satisfy `isTrusted`/activation gates on most sites. Escalate to `--os` (CGEvent) ONLY when synthetic is proven insufficient (anti-automation beyond `isTrusted`, IME, OS dialogs). For native macOS apps, use `interceptor macos`.

## Surface decision

| Target | Surface |
|---|---|
| Content inside a browser tab (DOM, network, SPA state, scene graph of a web editor) | browser (`interceptor …`) |
| Native app, OS dialog, browser chrome (URL bar/menu), occluded/minimized window | macOS (`interceptor macos …`) |
| "Open in Brave / Mail / <named app>" | macOS (Apple Events) |
| Visual overlay/HUD above all apps | macOS (`macos overlay`) |

**The user's words win.** "Open in Brave" = that browser. "Don't bring it up" = stay background. "Show me X" = focus is OK.

## Browser fast path

```bash
interceptor open "https://example.com"     # tab + wait + tree + text (background)
interceptor read                           # re-read current page after any change
interceptor find "Sign in" --role button   # locate an element → get its ref
interceptor act e5                          # click ref e5, wait, return updated tree + diff
interceptor act e7 "user@example.com"       # type into ref e7
interceptor inspect                         # tree + text + network + headers in one call
interceptor screenshot --save               # only when you need pixels
```

## macOS fast path

```bash
interceptor macos trust                     # confirm TCC permissions
interceptor macos apps                       # list running apps
interceptor macos open "Finder"             # AX tree + windows (background — won't raise it)
interceptor macos read --app "Mail"         # AX tree of a specific app
interceptor macos act e5                     # AX press of ref e5 (no focus change)
interceptor macos screenshot --app "Finder" --save   # captures even if occluded
```

## Recovery reflexes

- Stale ref → `read` / `find` again.
- Element in an iframe missing → `read --include-frames`.
- Canvas page has no DOM text / rich editor exposes no refs → `scene profile`, then `scene list` / `scene text`.
- Action did nothing → `inspect` before retrying.
- Network behavior unclear → `inspect --net-only` or `net log --filter <term>`.
- Native control failed → `interceptor macos trust`.
- Daemon down → `interceptor status`; the daemon should auto-start on first command.

## Going deeper

- **`references/command-catalog.md`** — the full command surface for BOTH browser and macOS, with flags: navigation, tabs, capture/eval, cookies, network (passive `net` vs CDP `network` vs passive `override`), SSE, scene graph (rich editors), monitor/replay, ChatGPT bridge, and the entire `macos` tree (AX, input, capture, vision/speech/NLP, Apple Events, files, notifications, personal data, documents, overlays). **Read this before composing any non-trivial command.**
- **`references/recipes.md`** — worked, copy-pasteable procedures for common tasks (verify a deploy, extract a value, drive a rich editor, override an XHR, capture an SSE stream, record-and-replay, screenshot for a VLM, drive a backgrounded native app).

## Scope discipline

If the user wants a **task done** (read this page, fill this form, screenshot that app), just run the commands. If they want Interceptor itself **installed/fixed/explained**, that's a different job — handle it explicitly, don't auto-dive into troubleshooting in the middle of a task.
