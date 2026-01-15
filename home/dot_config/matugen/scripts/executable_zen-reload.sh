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

if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
  hyprctl dispatch sendshortcut "CTRL SHIFT, Y, class:zen"
  sleep 0.4
  hyprctl dispatch sendshortcut ", RETURN, class:zen"
elif [ "$XDG_CURRENT_DESKTOP" = "Niri" ] || [ "$XDG_CURRENT_DESKTOP" = "niri" ]; then
    # Get the currently active window ID
    ACTIVE_WINDOW=$(niri msg -j windows | jq -r '.[] | select(.is_focused == true) | .id')

    # Find Zen Browser window ID (first match)
    ZEN_WINDOW=$(niri msg -j windows | jq -r '.[] | select((.app_id // "") | test("zen"; "i")) | .id' | head -n 1)

    if [ -z "$ZEN_WINDOW" ]; then
        echo "Zen Browser window not found."
        exit 0
    fi

    # Focus Zen Browser
    niri msg action focus-window --id "$ZEN_WINDOW"

    # Send Ctrl+Shift+Y
    ydotool key 29:1 42:1 21:1 21:0 42:0 29:0

    # Small delay, then press Enter
    sleep 0.4
    niri msg action focus-window --id "$ZEN_WINDOW"
    ydotool key 28:1 28:0

    # Return to previously focused window
    if [ -n "$ACTIVE_WINDOW" ] && [ "$ACTIVE_WINDOW" != "$ZEN_WINDOW" ]; then
        niri msg action focus-window --id "$ACTIVE_WINDOW"
    fi
fi
