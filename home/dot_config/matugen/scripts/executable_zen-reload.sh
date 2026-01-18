#!/usr/bin/env bash
if ! pgrep -x "zen-bin" >/dev/null; then
    exit 0
fi

if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
  hyprctl dispatch sendshortcut "ALT SHIFT, R, class:zen"
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

    # Send Alt+Shift+R
    ydotool key 56:1 42:1 19:1 19:0 42:0 56:0

    # Return to previously focused window
    if [ -n "$ACTIVE_WINDOW" ] && [ "$ACTIVE_WINDOW" != "$ZEN_WINDOW" ]; then
        niri msg action focus-window --id "$ACTIVE_WINDOW"
    fi
fi
