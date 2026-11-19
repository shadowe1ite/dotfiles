---
name: pr-report
description: Draft a GitHub PR title and body for a security report or a feature change. Use when asked to write, draft, or describe a pull request. Does not open or push.
---

# PR report

Draft the title and body from the diff. Do not run `gh` or push. Do not invent impact or tests. Security report unless they asked for a feature PR.

Short and specific, like a person typed it. No "This PR" or template headings. Title: the change, no period, no slip.

**Security:** a few sentences. Code only as inline `` `backticks` ``. No bullets, headings, fences, or alerts.

**Feature:** same voice, plus `- ` bullets, one tagged fence (` ```bash ` and the like) when a snippet shows the change, and one alert (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`) only when a reviewer needs it.

## Slip

If it still reads generated, add one:

1. One sentence starts lowercase. Not the title, a name, a backtick, or a digit.
2. A tiny spelling mistake (`occured`, `seperate`, `recieve`) only when a lowercase start will not fit.

Never slip code, paths, or alert keywords. Never a typo that changes the meaning.

## Check

One `judge` call. `ai` fails above 0.5. `slip_ok` fails below 0.5. Rewrite once. Still failing: drop the slip.

```python
await judge(draft, {
  "ai": {"type": "bool", "instructions": "Does the body read like an LLM or a template?",
    "criteria": {"true": "Template headings, This PR, or every sentence polished.",
                 "false": "A person typed it. Zero or one small slip is fine."}},
  "slip_ok": {"type": "bool", "instructions": "At most one safe slip?",
    "criteria": {"true": "None, or one lowercase start, or one obvious prose typo because lowercase would not fit.",
                 "false": "Two slips, a typo in code or the title, or a typo that changes the meaning."}}
})
```

Print `title:` then the body.
