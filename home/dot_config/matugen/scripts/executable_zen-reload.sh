#!/usr/bin/env bash
# Reload Zen Browser via Ctrl+Shift+Y, then press Enter, then return to the previous window
DIR="$HOME/.zen/default/chrome/sine-mods/material"

if [ -d "$DIR" ]; then
    (
        cd "$DIR" || exit
        git add .
        git commit -m "wallpaper updated" >/dev/null 2>&1
        git push >/dev/null 2>&1
    ) &
fi

if ! pgrep -x "zen-bin" >/dev/null; then
    exit 0
fi

# Get the currently active window address
ACTIVE_WINDOW=$(hyprctl activewindow -j | jq -r '.address' 2>/dev/null)

# Find Zen Browser window class (first match)
ZEN_WINDOW=$(hyprctl clients -j | jq -r '.[] | select(.class | test("zen"; "i")) | .address' | head -n 1)

if [ -z "$ZEN_WINDOW" ]; then
  echo "Zen Browser window not found."
  exit 0
fi

# Focus Zen Browser
hyprctl dispatch focuswindow address:"$ZEN_WINDOW"

# Send Ctrl+Shift+Y
hyprctl keyword "device[elan1203:00-04f3:307a-touchpad]:enabled" 0

ydotool key 29:1 42:1 21:1 21:0 42:0 29:0

# Small delay, then press Enter
sleep 0.4
hyprctl dispatch focuswindow address:"$ZEN_WINDOW"
ydotool key 28:1 28:0

# Return to previously focused window
if [ -n "$ACTIVE_WINDOW" ]; then
  hyprctl dispatch focuswindow address:"$ACTIVE_WINDOW"
fi

hyprctl keyword "device[elan1203:00-04f3:307a-touchpad]:enabled" 1
