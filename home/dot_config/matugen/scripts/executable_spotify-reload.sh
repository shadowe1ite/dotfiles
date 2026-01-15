#!/usr/bin/env bash
PREFS="$HOME/.config/spotify/prefs"

[[ -f "$PREFS" ]] || exit 0

# Reload Spotify via Ctrl+Shift+R, then return to the previous window

theme=$(spicetify config current_theme)
scheme=$(spicetify config color_scheme)

# If the matugen theme is not applied
if [[ "$theme" != "Comfy" || "$scheme" != "Comfy" ]]; then
    spicetify config current_theme Comfy color_scheme Comfy
    spicetify apply enable-devtools
else
    # Only refresh and reload if the theme is already correct
    spicetify refresh -s

    if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
        hyprctl dispatch sendshortcut "CTRL SHIFT, R, class:Spotify"

    elif [ "$XDG_CURRENT_DESKTOP" = "Niri" ] || [ "$XDG_CURRENT_DESKTOP" = "niri" ]; then
        # Get the currently active window ID
        ACTIVE_WINDOW=$(niri msg -j windows | jq -r '.[] | select(.is_focused == true) | .id')

        # Find Spotify window ID (first match)
        # Note: Checks app_id first. If Spotify is XWayland, app_id might be null, so ensure your niri config handles XWayland properly or use a broad search.
        SPOTIFY_WINDOW=$(niri msg -j windows | jq -r '.[] | select((.app_id // "") | test("Spotify"; "i")) | .id' | head -n 1)

        if [ -z "$SPOTIFY_WINDOW" ]; then
            echo "Spotify window not found."
            exit 0
        fi

        # Focus Spotify
        niri msg action focus-window --id "$SPOTIFY_WINDOW"

        # Send Ctrl+Shift+R to Spotify
        ydotool key 29:1 42:1 19:1 19:0 42:0 29:0

        # Small delay to ensure input registers before switching back
        sleep 0.2

        # Return to previously focused window
        if [ -n "$ACTIVE_WINDOW" ] && [ "$ACTIVE_WINDOW" != "$SPOTIFY_WINDOW" ]; then
            niri msg action focus-window --id "$ACTIVE_WINDOW"
        fi
    fi
fi
