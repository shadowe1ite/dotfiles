---
name: lazy_chunk_downloader
description: Find where lazy-loaded JS/CSS chunks are defined inside local JavaScript bundles and download the chunk files into the current working directory. Use when the user wants to grab a site's lazy/code-split webpack or Vite chunks, fetch all dynamically-imported chunks, or complete a local copy of a bundle for recon/analysis.
---

# Lazy Chunk Downloader

Reconstructs the lazy-loaded (code-split) chunk filenames that a bundler hard-codes
into its runtime, then downloads those chunk files into the current working directory.
Companion to `js_endpoint_extraction` — grab the chunks first, then mine them.

## How it finds chunks

Modern bundlers don't list chunk URLs directly; they build them at runtime from a
template plus a hash map. The script reconstructs them:

- **webpack 5** — the runtime defines `__webpack_require__.u(chunkId)` for JS (and
  `.miniCssF` for CSS), e.g.
  `u = e => "static/js/" + e + "." + {143:"a1b2c3",...}[e] + ".chunk.js"`.
  The script parses the string literals + chunkId + hash/name maps and expands them
  over every chunkId. The `__webpack_require__.p` publicPath prefix is reported.
- **Vite** — dynamic-import targets recorded in `__vite__mapDeps([...])` arrays.
- **Fallback** — any hard-coded quoted `*.js` / `*.chunk.js` / `*.css` asset path.
  This also covers Next.js `_buildManifest.js` route→chunk lists, including
  framework chunks whose names start with `_` (`_error`, `_app`) and dynamic-route
  chunks with literal bracketed segments (`[accountId]`, `[[...brandSlug]]`).

## Workflow

1. **List first (no network).** Run a dry run to see what would be fetched and to read
   any detected `publicPath`:
   ```bash
   node scripts/fetch_lazy_chunks.js --dry-run
   ```
   Each line is a chunk path; the script prints the count and detected publicPath(s).

2. **Get the base URL.** Chunk paths are relative. You need the URL the bundle was
   served from. If the user hasn't given one, ask for the site/asset base (e.g.
   `https://example.com/`). Combine it with the detected publicPath if the publicPath
   is an absolute URL or a subpath the chunk names don't already include.

3. **Download into the cwd.** Paths are mirrored under the current directory
   (`static/js/143.a1b2c3.chunk.js` lands at `./static/js/...`):
   ```bash
   node scripts/fetch_lazy_chunks.js https://example.com/
   ```
   Each chunk reports `ok`/`FAIL`; a `FAIL ... HTTP 404` just means that reconstructed
   id doesn't exist on the server (common — maps can list more ids than are emitted).

## Options

```bash
node scripts/fetch_lazy_chunks.js <baseURL> [--dir .] [--dry-run] [--ext js,css]
```
- `<baseURL>` — origin/asset base the chunk paths resolve against (required to download).
- `--dir` — directory to scan for `.js` bundles (default: current working directory).
- `--dry-run` — list discovered chunks + resolved URLs; download nothing.
- `--ext` — comma list of extensions to keep (default `js,css`; e.g. `--ext js`).

Locally-present bundles and `node_modules` / `.git` are skipped automatically.

## Notes / tips

- **publicPath matters.** If the dry run reports a publicPath like `/app/` or an absolute
  CDN URL, the real chunk lives at `<origin><publicPath><chunkname>`. Pass a `<baseURL>`
  that already includes that path (e.g. `https://example.com/app/`), or point `<baseURL>`
  straight at the CDN origin.
- **404s are expected.** webpack hash maps sometimes contain ids for chunks that weren't
  emitted in this build; failed fetches are reported and skipped, not fatal.
- **Beautify minified runtimes** (`js-beautify`) only if reconstruction misses chunks —
  the parser handles minified single-line runtimes, but extreme variants may need a look.
- After downloading, feed the new chunks back through `js_endpoint_extraction` or your
  own analysis — that's the usual reason to pull them.
- Only fetch from targets you're authorized to test.
```
