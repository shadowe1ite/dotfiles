# Habits

Screen-time style tracking for groups of apps on niri. Time is credited to a habit while a window whose
app id or title contains one of its patterns as a whole word (`gf` matches `gf xss`, not `gfx`) is focused.

- Focus comes from `niri msg --json event-stream` (event-driven, no polling).
- Data: `habits.json` in the plugin data dir, 14 days kept.
- Edit habits in **Settings → Plugins → Habits**: habit name -> `icon | pattern, pattern, ...`.

## Terminal tools

`gdb`, `httpx`, `curl` are matched through the terminal title, so the shell must put the running
command in the title. For zsh, add after your plugin manager / prompt setup in `~/.zshrc`:

```zsh
_habits_title_preexec() {
  local cmd=${1//[[:cntrl:]]/ }
  print -rn -- $'\e]0;'"${cmd[1,80]}"$'\a'
}
[[ $TERM != dumb ]] && { autoload -Uz add-zsh-hook; add-zsh-hook preexec _habits_title_preexec }
```

Your prompt's own title hook (e.g. zim `termtitle`) restores the title when the command ends.

## Pause while locked

```toml
[hooks]
session_locked   = "noctalia msg plugin shadow/habits:tracker all pause"
session_unlocked = "noctalia msg plugin shadow/habits:tracker all resume"
```

IPC events: `pause`, `resume`, `reset`.
