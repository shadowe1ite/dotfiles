---
name: js_endpoint_extraction
description: Extract API endpoints, paths, and URLs hidden inside JavaScript files for security recon and bug hunting. Use when the user asks to extract endpoints from JS, find hidden APIs in JavaScript, recon a target's JS files, or hunt for IDOR/SSRF/open-redirect leads in JS.
---

# JavaScript Endpoint Extraction


## Inputs

- Local `.js` files only — a single file, specific files, or a directory. Defaults to
  every `.js` under the current working directory. No network access; nothing is fetched.

## Workflow

1. **Extract endpoints** — run `scripts/extract_endpoints.sh` (see below). With no args it
   scans every `.js` in the current working directory; pass files or a directory to narrow
   it. It applies the path/URL/AJAX regexes and de-duplicates.

2. **Triage the output** — group results: `/api/...` routes, absolute URLs (SSRF/redirect
   candidates), `.get/.post/.ajax/.load` call targets, and anything with IDs or tokens
   (IDOR candidates). Note params (`?id=`, `?url=`, `?redirect=`).


## Quick commands

The helper script (`scripts/extract_endpoints.sh`) does the extraction, adds AJAX/fetch-call
matching, and is portable to macOS — prefer it for real runs:

```bash
scripts/extract_endpoints.sh                 # every *.js in the current directory (recursive)
scripts/extract_endpoints.sh app.bundle.js   # one specific file
scripts/extract_endpoints.sh ./static/js     # a specific directory
```

Static extraction one-liner (the blog's method), for a single file or many concatenated
into `JS.txt` — grabs every quoted string that starts with `/`:

```bash
cat JS.txt | grep -aoP "(?<=(\"|'|\`))/[a-zA-Z0-9?&=\/\-#.]+(?=(\"|'|\`))" | sort -u >> endpoints.txt
```

- `-a` treats binary-ish minified blobs as text; `-o` prints only the match.
- `-P` enables Perl regex so the lookbehind/lookahead (`(?<=...)` / `(?=...)`) require the
  path to be wrapped in `"`, `'`, or a backtick.
- The character class limits matches to URL-path-safe characters.
- `sort -u >> endpoints.txt` appends a de-duplicated list.

> Note: `grep -P` is GNU-only and **fails on macOS BSD grep**. Use the helper script
> (Perl-based, portable) or install GNU grep (`brew install grep`, then `ggrep`).

## Notes / tips

- Beautify minified JS first (`js-beautify file.js`) so multi-line and concatenated
  strings extract cleanly.
- Many "endpoints" will be CSS/asset noise — filter obvious static paths
  (`.css`, `.png`, `.woff`, `.svg`) when triaging.
- Relative paths need the JS file's origin prepended to be testable.
- Source maps (`.js.map`) reveal original source and often more routes — grab them if exposed.
- Look for base-URL constants (`API_BASE`, `baseURL`) to reconstruct full endpoints.
- The output should ONLY include api endpoints, which are likely to be from the in-scope api and not third party sites 

## output
  - final output should be saved to all_endpoints.txt in the current working directory

Source: "Extract all endpoints from a JS file & hunt your bugs" (nexusphere, Medium).
