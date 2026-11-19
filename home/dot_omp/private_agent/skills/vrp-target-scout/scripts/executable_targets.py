#!/usr/bin/env python3
"""VRP Patch Rewards target data. Run from the repo root.

  targets.py build                 refresh all data (~1-3 min) -> .cache/targets.tsv
  targets.py langs [--tier N]      count targets per language
  targets.py list  [filters]       table of targets (see --help)
  targets.py show  NAME            one target in full + AI-policy hits + past rewards
"""
import argparse, csv, datetime as dt, json, os, re, subprocess, sys

SKILL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIER1 = os.path.join(SKILL, "references", "tier1.tsv")
TIER2 = True  # include Tier 2 (projects in OSS-Fuzz). Set False to skip it
TIER1_SHA = "c2e0fac4"  # scope.md commit tier1.tsv was built from (2026-09-02)
CACHE = ".cache"
OSSF = os.path.join(CACHE, "oss-fuzz")
OUT = os.path.join(CACHE, "targets.tsv")
COLS = ["tier", "name", "area", "parser", "lang", "langs", "repo", "mirror", "ai",
        "stars", "open_prs", "merged_90d", "merged_total", "last_push", "archived"]
T1_PARTS = {"llvm_libcxx", "llvm_libcxxabi", "libpng-proto"}  # OSS-Fuzz parts of Tier 1 projects
SKIP = re.compile(r"(^|[-_])(example|test|demo|dummy|template|playground)([-_]|$)", re.I)
LANG_FIX = {"c++": "C++", "c": "C", "jvm": "Java", "go": "Go", "rust": "Rust", "python": "Python",
            "javascript": "JavaScript", "swift": "Swift", "ruby": "Ruby"}


def sh(*cmd, check=True):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode and not r.stdout:
        sys.exit(f"failed: {' '.join(cmd)}\n{r.stderr}")
    return r.stdout


def gh_repo(url):
    m = re.search(r"github\.com[/:]([^/\s]+)/([^/\s?#]+)", url or "")
    if not m:
        return None
    return f"{m.group(1)}/{re.sub(r'(\.git)?/?$', '', m.group(2))}"


def yaml_field(text, key):
    m = re.search(rf"^{key}:\s*['\"]?([^'\"\n]*)", text, re.M)
    return m.group(1).strip() if m else ""


# ---------------------------------------------------------------- build
def build(tier2=TIER2):
    os.makedirs(CACHE, exist_ok=True)
    if tier2:
        if os.path.isdir(OSSF):
            sh("git", "-C", OSSF, "pull", "-q", check=False)
        else:
            sh("git", "clone", "-q", "--depth", "1", "--filter=blob:none", "--sparse",
               "https://github.com/google/oss-fuzz", OSSF)
            sh("git", "-C", OSSF, "sparse-checkout", "set", "--no-cone", "/projects/*/project.yaml")

    rows = []
    t1_ossfuzz = set()
    with open(TIER1) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            t1_ossfuzz.add(r["ossfuzz"])
            rows.append({"tier": "1", "name": r["name"], "area": r["area"], "parser": r["parser"],
                         "lang": r["lang"], "repo": r["repo"], "mirror": r["mirror"], "ai": r["ai"]})

    pdir = os.path.join(OSSF, "projects")
    for p in (sorted(os.listdir(pdir)) if tier2 else []):
        y = os.path.join(pdir, p, "project.yaml")
        if p in t1_ossfuzz or p in T1_PARTS or SKIP.search(p) or not os.path.isfile(y):
            continue
        text = open(y, errors="replace").read()
        url = yaml_field(text, "main_repo")
        lang = yaml_field(text, "language").lower()
        rows.append({"tier": "2", "name": p, "area": "oss-fuzz", "parser": "0",
                     "lang": LANG_FIX.get(lang, lang or "?"), "repo": gh_repo(url) or url or "-",
                     "mirror": "0", "ai": "unknown"})

    since = (dt.date.today() - dt.timedelta(days=90)).isoformat()
    repos = sorted({r["repo"] for r in rows if re.fullmatch(r"[\w.-]+/[\w.-]+", r["repo"])})
    stats = {}
    for i in range(0, len(repos), 40):
        batch = repos[i:i + 40]
        parts = []
        for j, rp in enumerate(batch):
            o, n = rp.split("/")
            parts.append(
                f'r{j}: repository(owner:"{o}", name:"{n}") {{ stargazerCount isArchived pushedAt '
                f'primaryLanguage {{ name }} languages(first:3, orderBy:{{field:SIZE, direction:DESC}}) {{ nodes {{ name }} }} '
                f'open: pullRequests(states:OPEN) {{ totalCount }} merged: pullRequests(states:MERGED) {{ totalCount }} }} '
                f's{j}: search(query:"repo:{rp} is:pr is:merged merged:>={since}", type:ISSUE) {{ issueCount }}')
        out = sh("gh", "api", "graphql", "-f", "query={" + " ".join(parts) + "}", check=False)
        data = (json.loads(out or "{}").get("data") or {})
        for j, rp in enumerate(batch):
            d = data.get(f"r{j}")
            if d:
                stats[rp] = {
                    "langs": ",".join(x["name"] for x in d["languages"]["nodes"]),
                    "gh_lang": (d["primaryLanguage"] or {}).get("name", ""),
                    "stars": d["stargazerCount"], "open_prs": d["open"]["totalCount"],
                    "merged_total": d["merged"]["totalCount"],
                    "merged_90d": (data.get(f"s{j}") or {}).get("issueCount", ""),
                    "last_push": (d["pushedAt"] or "")[:10], "archived": int(d["isArchived"])}
        print(f"  github stats {min(i + 40, len(repos))}/{len(repos)}", file=sys.stderr)

    for r in rows:
        s = stats.get(r["repo"], {})
        if r["tier"] == "2" and s.get("gh_lang"):
            r["lang"] = s["gh_lang"]  # real language beats the OSS-Fuzz harness language
        for k in ["langs", "stars", "open_prs", "merged_90d", "merged_total", "last_push", "archived"]:
            r[k] = s.get(k, "")
        r["langs"] = r["langs"] or r["lang"]

    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, COLS, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    t1 = sum(r["tier"] == "1" for r in rows)
    print(f"wrote {OUT}: {t1} tier 1, {len(rows) - t1} tier 2, {len(stats)} with GitHub stats")
    latest = sh("gh", "api", "repos/google/bughunters/commits?path=patch-rewards-program/scope.md&per_page=1",
                "--jq", ".[0].sha[:8]", check=False).strip()
    if latest and latest != TIER1_SHA:
        print(f"WARNING: Tier 1 list changed upstream (now {latest}, tier1.tsv is from {TIER1_SHA}). "
              f"See: gh api repos/google/bughunters/commits/{latest} --jq '.files[].patch'")
    else:
        print(f"tier1.tsv current (scope.md {TIER1_SHA})")


# ---------------------------------------------------------------- query
AVOID_FILE = os.path.join(SKILL, "references", "avoid.txt")


def avoid():
    """name -> reason, from references/avoid.txt."""
    out = {}
    for line in open(AVOID_FILE) if os.path.exists(AVOID_FILE) else []:
        name, _, why = line.partition("#")
        if name.strip():
            out[name.strip().lower().split("/")[-1]] = why.strip()
    return out


def load(keep_avoided=False):
    if not os.path.exists(OUT):
        sys.exit("no data: run `targets.py build` first")
    rows = list(csv.DictReader(open(OUT), delimiter="\t"))
    if keep_avoided:
        return rows
    av = avoid()
    return [r for r in rows if r["name"].lower() not in av and r["repo"].lower().split("/")[-1] not in av]


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return -1.0


def fit(r):
    """Higher = better patch target. Documented in SKILL.md."""
    if r["ai"] == "banned" or r["archived"] == "1":
        return 0
    s = 40 * (r["tier"] == "1") + 15 * (r["parser"] == "1")
    s += min(num(r["merged_90d"]), 50) * 0.6          # maintainers are merging PRs
    s += 10 * (r["mirror"] == "0" and "/" in r["repo"] and "://" not in r["repo"])  # PRs on GitHub
    s += 5 * (r["last_push"] >= (dt.date.today() - dt.timedelta(days=90)).isoformat())
    return round(s, 1)


def match_lang(r, langs):
    have = {x.strip().lower() for x in (r["lang"] + "," + r["langs"]).split(",") if x.strip()}
    return any(l in have for l in langs)


def table(rows, cols):
    print("| # | " + " | ".join(cols) + " |")
    print("|---|" + "---|" * len(cols))
    for i, r in enumerate(rows, 1):
        print(f"| {i} | " + " | ".join(str(r.get(c, "")) or "-" for c in cols) + " |")


def cmd_list(a):
    rows = load()
    for r in rows:
        r["fit"] = fit(r)
    if a.tier:
        rows = [r for r in rows if r["tier"] == a.tier]
    if a.lang:
        langs = [l.strip().lower() for l in a.lang.split(",")]
        rows = [r for r in rows if (match_lang(r, langs) if a.any_lang else r["lang"].lower() in langs)]
    if a.area:
        rows = [r for r in rows if r["area"] == a.area]
    if a.parser:
        rows = [r for r in rows if r["parser"] == "1"]
    if a.github:
        rows = [r for r in rows if r["stars"] != ""]
    if a.active:
        cut = (dt.date.today() - dt.timedelta(days=a.active)).isoformat()
        rows = [r for r in rows if r["last_push"] >= cut]
    if a.hide_banned:
        rows = [r for r in rows if r["ai"] != "banned"]
    if a.name:
        rows = [r for r in rows if a.name.lower() in r["name"].lower()]
    key = a.sort
    rows.sort(key=lambda r: r[key].lower() if key in ("name", "lang", "area", "last_push")
              else (num(r[key]), num(r["merged_90d"])), reverse=not a.asc)  # ties -> most merged PRs
    if key == "name" and not a.asc:
        rows.reverse()
    total = len(rows)
    if a.limit:
        rows = rows[:a.limit]
    cols = a.cols.split(",") if a.cols else ["tier", "name", "lang", "area", "repo", "ai",
                                            "merged_90d", "open_prs", "stars", "last_push", "fit"]
    table(rows, cols)
    print(f"\n{len(rows)} of {total} shown (sorted by {key})")


def cmd_langs(a):
    from collections import Counter
    rows = [r for r in load() if not a.tier or r["tier"] == a.tier]
    for t in sorted({r["tier"] for r in rows}):
        c = Counter(r["lang"] for r in rows if r["tier"] == t)
        print(f"Tier {t} ({sum(c.values())}): " + ", ".join(f"{k} {v}" for k, v in c.most_common()))


def cmd_show(a):
    av = avoid().get(a.name.lower())
    if av is not None:
        print(f"AVOID: {a.name} is on references/avoid.txt ({av}). Pick another target.")
    hits = [r for r in load(True) if r["name"].lower() == a.name.lower()] or \
           [r for r in load(True) if a.name.lower() in r["name"].lower()]
    if not hits:
        sys.exit(f"{a.name}: not in Tier 1 or Tier 2 (out of scope)")
    r = hits[0]
    r["fit"] = fit(r)
    for k in COLS + ["fit"]:
        print(f"{k:13} {r.get(k, '')}")
    if len(hits) > 1:
        print("also matches:", ", ".join(h["name"] for h in hits[1:6]))
    if re.fullmatch(r"[\w.-]+/[\w.-]+", r["repo"]):
        print("\nAI-policy hits (README / CONTRIBUTING / AI_POLICY):")
        found = False
        for f in ["README.md", "CONTRIBUTING.md", "AI_POLICY.md", ".github/CONTRIBUTING.md"]:
            txt = sh("gh", "api", f"repos/{r['repo']}/contents/{f}", "-H",
                     "Accept: application/vnd.github.raw", check=False)
            if txt.startswith("{") and '"message"' in txt[:200]:
                continue
            for ln in txt.splitlines():
                if re.search(r"\bLLMs?\b|\bAI\b|generative|AI-generated|Assisted-by|Copilot", ln):
                    print(f"  {f}: {ln.strip()[:160]}")
                    found = True
        if not found:
            print("  none found -> unknown, ask maintainers")
    rew = sh("gh", "api", "repos/google/bughunters/contents/patch-rewards-program/rewarded-patches",
             "--jq", ".[].name", check=False).split()
    key = r["name"].lower().split()[0]
    print("\nPast rewards:", ", ".join(x for x in rew if key in x.lower()) or "none")


def cmd_report(a):
    """Default: full report of every target, grouped by tier and language, sorted by fit."""
    stale = not os.path.exists(OUT) or \
        dt.datetime.now().timestamp() - os.path.getmtime(OUT) > 7 * 86400
    if stale:
        build()
    rows = load()
    for r in rows:
        r["fit"] = fit(r)
    from collections import Counter
    key = lambda r: (r["fit"], num(r["merged_90d"]))
    print(f"# VRP targets (Tier 1 from scope.md {TIER1_SHA}; sorted by fit; ⭐ = parser, ✗ = AI banned)")
    t1 = [r for r in rows if r["tier"] == "1"]
    c1 = Counter(r["lang"] for r in t1)
    print(f"\n## Tier 1 ({len(t1)}): " + ", ".join(f"{k} {v}" for k, v in c1.most_common()))
    for lang, _ in c1.most_common():
        lr = sorted((r for r in t1 if r["lang"] == lang), key=key, reverse=True)
        print(f"- **{lang}:** " + ", ".join(
            r["name"] + ("⭐" if r["parser"] == "1" else "") + ("✗" if r["ai"] == "banned" else "")
            + f" ({r['merged_90d'] or '-'})" for r in lr))
    t2 = [r for r in rows if r["tier"] == "2"]
    if not t2:
        print("\nTier 2: not loaded (TIER2 = False).")
    c2 = Counter(r["lang"] for r in t2)
    if t2:
        print(f"\n## Tier 2 ({len(t2)}): " + ", ".join(f"{k} {v}" for k, v in c2.most_common(10)))
    for lang, _ in c2.most_common(8):
        lr = sorted((r for r in t2 if r["lang"] == lang), key=key, reverse=True)[:8]
        print(f"- **{lang}** top: " + ", ".join(f"{r['name']} ({r['merged_90d'] or '-'})" for r in lr))
    print("\n(n) = PRs merged in last 90 days. More: `list`, `show <name>`.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("build"); p.add_argument("--tier2", action="store_true", help="also fetch OSS-Fuzz (paused by default)")
    sub.add_parser("report")
    p = sub.add_parser("langs"); p.add_argument("--tier", choices=["1", "2"])
    p = sub.add_parser("show"); p.add_argument("name")
    p = sub.add_parser("list")
    p.add_argument("--tier", choices=["1", "2"])
    p.add_argument("--lang", help="comma list, e.g. c,c++,rust (main language)")
    p.add_argument("--any-lang", action="store_true", help="match any of the top-3 languages too")
    p.add_argument("--area", help="parser, server, essential-lib, network, cms, web-framework, kernel, ...")
    p.add_argument("--parser", action="store_true", help="only core data parsers")
    p.add_argument("--github", action="store_true", help="only targets with GitHub stats")
    p.add_argument("--active", type=int, metavar="DAYS", help="pushed within DAYS")
    p.add_argument("--hide-banned", action="store_true", help="drop projects that ban AI patches")
    p.add_argument("--name", help="substring match")
    p.add_argument("--sort", default="fit", choices=["fit", "merged_90d", "open_prs", "merged_total",
                                                     "stars", "last_push", "name", "lang", "area"])
    p.add_argument("--asc", action="store_true")
    p.add_argument("--limit", type=int, default=25, help="0 = all")
    p.add_argument("--cols", help="comma list of columns")
    a = ap.parse_args()
    {"build": lambda a: build(a.tier2 or TIER2), "report": cmd_report, None: cmd_report,
     "langs": cmd_langs, "list": cmd_list, "show": cmd_show}[a.cmd](a)


if __name__ == "__main__":
    main()
