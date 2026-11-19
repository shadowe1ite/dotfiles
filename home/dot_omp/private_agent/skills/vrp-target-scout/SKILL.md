---
name: vrp-target-scout
description: Find, filter, sort and vet targets for Google's Patch Rewards Program (VRP), Tier 1 and Tier 2. Use for "list all targets", "which use <language>", "sort by PRs", "best fit", "is X in scope", "should I target X".
---

# VRP Target Scout

Run from repo root. No repo docs or new scripts. Only:
`python3 -I .skills/vrp-target-scout/scripts/targets.py <command>`

**Data:** `.cache/targets.tsv`: Tier 1 (`references/tier1.tsv`, 95 projects) + Tier 2 (every project in OSS-Fuzz, ~1,340), plus GitHub stats. OSS VRP bug bounty is paused; Patch Rewards is not.
- Missing or older than 7 days → run `build` (~3 min).
- `build` prints a Tier 1 WARNING → show the diff, update changed rows in `tier1.tsv` and `TIER1_SHA`.

## Default (no specific question)
No args → overview: Tier 1 by language, Tier 2 counts and top targets. Never write files.

## Sub-questions
| Need | Command |
|---|---|
| Languages used | `langs` (`--tier 1`/`2`) |
| All targets | `list --limit 0` (`--tier 1`/`2`) |
| By language | `list --lang c,rust` (`--any-lang` also matches secondary languages) |
| Sort | `--sort fit, merged_90d, open_prs, merged_total, stars, last_push, name` (`--asc`) |
| Filter | `--tier`, `--area parser`, `--parser`, `--active 90`, `--github`, `--hide-banned`, `--name x` |
| Columns | `--cols name,lang,repo,merged_90d,fit` |
| One project | `show <name>`: all fields, AI-policy lines, past rewards. Not found → out of scope |

`fit` scoring (default sort): see `references/fit.md`.

## Decisions
- Never pick a project in `references/avoid.txt`. User says avoid X → add a line there.
- Tier 1 before Tier 2, unless the user asks otherwise.
- "Best fit" with no language given → ask which languages the user knows.
- "Should I target X" → `show X`, then decide GO / MAYBE / NO-GO:
  - AI banned → NO-GO
  - no AI rule found → unknown, ask maintainers
  - `mirror=1` → patches go through Gerrit, a mailing list or GitLab, not GitHub PRs
