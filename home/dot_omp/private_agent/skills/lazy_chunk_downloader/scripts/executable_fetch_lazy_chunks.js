#!/usr/bin/env node
/*
 * fetch_lazy_chunks.js — find lazy-loaded JS/CSS chunk definitions inside local
 * bundles and download the chunk files into the current working directory.
 *
 * How modern bundlers name lazy chunks:
 *   - webpack 5 emits a runtime function `__webpack_require__.u(chunkId)` (and
 *     `.miniCssF` for CSS) that concatenates string literals, the chunkId, and a
 *     hash lookup map, e.g.
 *       u = e => "static/js/" + e + "." + {143:"a1b2c3",...}[e] + ".chunk.js"
 *     The publicPath prefix lives in `__webpack_require__.p`.
 *   - Vite records dynamic-import targets in a `__vite__mapDeps` array of paths.
 *   - Anything may hard-code quoted "*.js"/"*.chunk.js"/"*.css" asset paths.
 *
 * This script reconstructs those filenames, resolves them against a base URL, and
 * downloads each one (mirroring its relative path) under the cwd.
 *
 * Usage:
 *   node fetch_lazy_chunks.js <baseURL> [--dir .] [--dry-run] [--ext js,css]
 *   node fetch_lazy_chunks.js --dry-run            # just list discovered chunks
 *
 *   <baseURL>   Origin/asset base the chunk paths are relative to, e.g.
 *               https://example.com/  (use the path the main bundle was served
 *               from; CRA/webpack default publicPath is "/").
 *   --dir       Directory to scan for .js bundles (default: current directory).
 *   --dry-run   Print the chunk list and resolved URLs; download nothing.
 *   --ext       Comma list of extensions to keep (default: js,css).
 */

'use strict';
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// arg parsing
// ---------------------------------------------------------------------------
const argv = process.argv.slice(2);
const opts = { dir: '.', dryRun: false, exts: ['js', 'css'], base: null };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--dry-run') opts.dryRun = true;
  else if (a === '--dir') opts.dir = argv[++i];
  else if (a === '--ext') opts.exts = argv[++i].split(',').map(s => s.trim().replace(/^\./, ''));
  else if (a.startsWith('-')) { console.error(`unknown flag: ${a}`); process.exit(2); }
  else if (!opts.base) opts.base = a;
}
if (!opts.base && !opts.dryRun) {
  console.error('error: a <baseURL> is required to download (or pass --dry-run to only list).');
  console.error('usage: node fetch_lazy_chunks.js <baseURL> [--dir .] [--dry-run] [--ext js,css]');
  process.exit(2);
}

// ---------------------------------------------------------------------------
// collect local .js bundles
// ---------------------------------------------------------------------------
function walk(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.name === 'node_modules' || ent.name.startsWith('.git')) continue;
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, out);
    else if (ent.isFile() && ent.name.endsWith('.js')) out.push(p);
  }
  return out;
}

// ---------------------------------------------------------------------------
// balanced extraction: given source and an index just after an opening
// delimiter, return the substring up to the matching closer.
// ---------------------------------------------------------------------------
function matchBalanced(src, openIdx, open, close) {
  let depth = 0;
  for (let i = openIdx; i < src.length; i++) {
    const c = src[i];
    if (c === open) depth++;
    else if (c === close) { depth--; if (depth === 0) return src.slice(openIdx, i + 1); }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Parse a webpack filename-template expression into ordered parts, then expand
// it over every chunkId so we get concrete filenames.
//   parts: {lit:"static/js/"} | {param:true} | {map:{id:hash}, def:bool}
// ---------------------------------------------------------------------------
function expandTemplate(param, expr) {
  const parts = [];
  let i = 0;
  const isIdent = ch => /[A-Za-z0-9_$]/.test(ch);
  while (i < expr.length) {
    const c = expr[i];
    if (c === '"' || c === "'" || c === '`') {
      let j = i + 1, s = '';
      while (j < expr.length && expr[j] !== c) {
        if (expr[j] === '\\') { s += expr[j + 1]; j += 2; } else { s += expr[j]; j++; }
      }
      parts.push({ lit: s });
      i = j + 1;
    } else if (c === '{') {
      // hash/name lookup map: {id:"hash",...}[param]  (optionally ( ... || param))
      const obj = matchBalanced(expr, i, '{', '}');
      if (!obj) { i++; continue; }
      const map = {};
      const re = /(?:"([^"]+)"|'([^']+)'|([\w$]+))\s*:\s*(?:"([^"]*)"|'([^']*)'|([\w$.]+))/g;
      let m;
      while ((m = re.exec(obj))) {
        const key = m[1] ?? m[2] ?? m[3];
        const val = m[4] ?? m[5] ?? m[6];
        map[key] = val;
      }
      i += obj.length;
      // advance past a trailing [param] index access if present
      if (/^[\s()]*\[/.test(expr.slice(i))) {
        const idx = expr.indexOf(']', i);
        if (idx !== -1) i = idx + 1;
      }
      // consume a "|| <ident>" default so its identifier isn't read as a
      // separate concatenation (e.g. ({names}[e]||e) → map with def=true)
      let def = false;
      const dm = /^[\s)]*\|\|[\s]*[\w$]+/.exec(expr.slice(i));
      if (dm) { def = true; i += dm[0].length; }
      parts.push({ map, def });
    } else if (isIdent(c)) {
      let j = i; while (j < expr.length && isIdent(expr[j])) j++;
      const word = expr.slice(i, j);
      if (word === param) parts.push({ param: true });
      // other identifiers (publicPath var, helpers) are ignored
      i = j;
    } else {
      i++;
    }
  }

  // union of all chunkIds seen in any map
  const ids = new Set();
  for (const p of parts) if (p.map) for (const k of Object.keys(p.map)) ids.add(k);
  if (ids.size === 0) return [];

  const files = [];
  for (const id of ids) {
    let name = '';
    let ok = true;
    for (const p of parts) {
      if (p.lit != null) name += p.lit;
      else if (p.param) name += id;
      else if (p.map) {
        if (Object.prototype.hasOwnProperty.call(p.map, id)) name += p.map[id];
        else if (p.def) name += id;          // {name}[id] || id  → falls back to id
        else { ok = false; break; }          // this id isn't valid for this template
      }
    }
    if (ok && /[^/]\.(js|css)$/i.test(name)) files.push(name);
  }
  return files;
}

// ---------------------------------------------------------------------------
// find webpack .u / .miniCssF template functions in a source string
// ---------------------------------------------------------------------------
function findWebpackTemplates(src) {
  const out = [];
  const re = /\.(?:u|miniCssF)\s*=\s*(?:function\s*)?\(?\s*([\w$]+)\s*\)?\s*(?:=>|\{)/g;
  let m;
  while ((m = re.exec(src))) {
    const param = m[1];
    // capture the function body / arrow expression
    let body;
    const tail = src.slice(m.index + m[0].length - 1);
    if (src[m.index + m[0].length - 1] === '{') {
      // function/arrow block: strip the outer braces and a leading `return`
      body = matchBalanced(src, m.index + m[0].length - 1, '{', '}') || '';
      body = body.slice(1, -1).replace(/^\s*return\b/, '');
    } else {
      // arrow without braces — take until a depth-0 ; or , (cap length)
      let depth = 0, end = 0;
      for (let i = 0; i < tail.length && i < 6000; i++) {
        const c = tail[i];
        if (c === '(' || c === '{' || c === '[') depth++;
        else if (c === ')' || c === '}' || c === ']') { if (depth === 0) { end = i; break; } depth--; }
        else if ((c === ';' || c === ',') && depth === 0) { end = i; break; }
        end = i + 1;
      }
      body = tail.slice(0, end);
    }
    for (const f of expandTemplate(param, body)) out.push(f);
  }
  return out;
}

// ---------------------------------------------------------------------------
// fallbacks: Vite mapDeps + hard-coded quoted asset paths
// ---------------------------------------------------------------------------
function findFallbacks(src) {
  const out = [];
  // Vite: __vite__mapDeps([...]) or const __vite__fileDeps=["..."]
  const vite = /__vite__\w*[Dd]eps\s*=?\s*\(?\s*\[([^\]]*)\]/g;
  let m;
  while ((m = vite.exec(src))) {
    const inner = m[1];
    const sre = /["'`]([^"'`]+\.(?:js|css))["'`]/g;
    let s; while ((s = sre.exec(inner))) out.push(s[1]);
  }
  // generic quoted chunk-looking asset paths. Bracket chars are allowed in the
  // path segments and basename so framework dynamic-route chunks survive — e.g.
  // Next.js emits literal "[accountId]" / "[[...brandSlug]]" directory + file names.
  const quoted = /["'`]((?:\.{0,2}\/)?(?:[\w.\[\]-]+\/)*[\w.\[\]-]*\.(?:chunk\.)?(?:js|css))["'`]/g;
  while ((m = quoted.exec(src))) {
    const p = m[1];
    if (/(?:chunk|assets|static\/(?:js|css)|chunks)\b/i.test(p) || /\.chunk\.(js|css)$/i.test(p)) out.push(p);
  }
  return out;
}

// detect a webpack publicPath assignment to report to the user
function findPublicPaths(src) {
  const out = new Set();
  const re = /\.p\s*=\s*["'`]([^"'`]*)["'`]/g;
  let m; while ((m = re.exec(src))) if (m[1]) out.add(m[1]);
  return [...out];
}

// ---------------------------------------------------------------------------
// scan
// ---------------------------------------------------------------------------
const files = walk(opts.dir);
if (files.length === 0) { console.error(`no .js files found under ${opts.dir}`); process.exit(1); }

const chunks = new Set();
const publicPaths = new Set();
for (const f of files) {
  let src;
  try { src = fs.readFileSync(f, 'utf8'); } catch { continue; }
  for (const c of findWebpackTemplates(src)) chunks.add(c);
  for (const c of findFallbacks(src)) chunks.add(c);
  for (const p of findPublicPaths(src)) publicPaths.add(p);
}

// keep only requested extensions; drop the local bundles we already have
const localBasenames = new Set(files.map(f => path.basename(f)));
let list = [...chunks]
  .filter(c => opts.exts.some(e => c.toLowerCase().endsWith('.' + e)))
  .filter(c => /^[^.]/.test(path.basename(c)))   // drop bare ".chunk.js" noise (basename starting with a dot), but keep "_app"/"[accountId]" etc.
  .filter(c => !localBasenames.has(path.basename(c)))
  .sort();

console.error(`scanned ${files.length} .js file(s); found ${list.length} candidate chunk(s)`);
if (publicPaths.size) console.error(`detected publicPath(s): ${[...publicPaths].join(', ')}`);

if (list.length === 0) process.exit(0);

if (opts.dryRun) {
  for (const c of list) {
    const url = opts.base ? resolve(opts.base, c) : c;
    console.log(opts.base ? `${c}\t${url}` : c);
  }
  process.exit(0);
}

// ---------------------------------------------------------------------------
// resolve + download
// ---------------------------------------------------------------------------
function resolve(base, chunk) {
  if (/^https?:\/\//i.test(chunk)) return chunk;
  let b = base; if (!/\/$/.test(b)) b += '/';
  try { return new URL(chunk.replace(/^\.?\//, ''), b).href; } catch { return b + chunk; }
}

async function download(url, dest) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, buf);
  return buf.length;
}

(async () => {
  let ok = 0, fail = 0;
  for (const chunk of list) {
    const url = resolve(opts.base, chunk);
    // mirror the path under cwd, stripping any leading slash / origin
    let rel = chunk.replace(/^https?:\/\/[^/]+\//i, '').replace(/^\.?\//, '');
    const dest = path.join(opts.dir, rel);
    try {
      const n = await download(url, dest);
      console.log(`  ok   ${rel}  (${n} bytes)`);
      ok++;
    } catch (e) {
      console.log(`  FAIL ${rel}  <- ${url}  (${e.message})`);
      fail++;
    }
  }
  console.error(`done: ${ok} downloaded, ${fail} failed`);
  process.exit(fail && !ok ? 1 : 0);
})();
