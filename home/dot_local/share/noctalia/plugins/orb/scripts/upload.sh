#!/bin/sh
# Copy a file you attached to the server's ~/orb-inbox over SSH, for Hermes to read with its
# own tools (its API only takes images). Prints the path it landed at.
#
#   upload.sh <user@host> <local file> <name>
#
# The name travels over stdin ahead of the file, never into the remote command line.
# Exit: 0 ok, 2 bad arguments, 3 copy failed

target=$1
src=$2
name=$3
case "$target" in
  "" | -*) exit 2 ;;
esac
case "$name" in
  "" | */* | .*) exit 2 ;;
esac
[ -f "$src" ] || exit 2

{
  printf '%s\n' "$name"
  cat -- "$src"
} | ssh -o BatchMode=yes -o ConnectTimeout=10 -- "$target" \
  'IFS= read -r n; mkdir -p "$HOME/orb-inbox" && f="$HOME/orb-inbox/$n" && cat > "$f" && printf "%s\n" "$f"' \
  || exit 3
