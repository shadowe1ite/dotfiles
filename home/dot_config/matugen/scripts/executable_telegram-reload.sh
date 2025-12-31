#!/usr/bin/env bash

THEME_DIR="$HOME/.config/telegram-desktop/themes"
COLORS_THEME_FILE="$THEME_DIR/colors.tdesktop-theme"
TILED_BG_FILE="$THEME_DIR/tiled.png"
FINAL_THEME_FILE="$THEME_DIR/meterial.tdesktop-theme"

BG_COLOR=$1

magick -size 256x256 "xc:$BG_COLOR" "$TILED_BG_FILE"

zip -q -j "$FINAL_THEME_FILE" "$COLORS_THEME_FILE" "$TILED_BG_FILE"

rm "$TILED_BG_FILE"
