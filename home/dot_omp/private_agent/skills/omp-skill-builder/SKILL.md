---
name: omp-skill-builder
description: Create or modify omp skills the way this user wants, using the latest omp docs. Use when asked to make, write, change, fix, shrink or review a skill.
---

# omp Skill Builder

Never write or edit a skill before steps 1-3.

1. **Docs:** run `~/.omp/agent/skills/omp-skill-builder/scripts/docs.sh`. It prints the latest omp skills doc (auto-refreshed from GitHub). Follow it over memory.
2. **Preferences:** read `skill://omp-skill-builder/references/preferences.md`.
3. **Ask the user** (use the `ask` tool, one batch, max 4 questions, each with a recommended default):
   - New skill: what it should do, when it triggers, name, user-level or project, which parts can be a script.
   - Modify: read the current skill first, propose 2-4 concrete changes, ask which to apply.
   - Skip a question the user already answered.
4. **Write.** Layout: `<name>/SKILL.md` + optional `scripts/` + `references/`. Deterministic work goes in scripts, not prose.
5. **Check:** run `scripts/lint.sh <skill-dir>`. Fix every warning.
6. **Report:** path, what changed, one line on how to invoke (`/skill:<name>`).

New preference from the user? Append one line to `references/preferences.md`.
