#!/bin/sh
# Copy one file Hermes made on the server to this machine over SSH: images to show in the
# chat, files you press Save on.
#
#   fetch.sh <user@host> <remote path> <local path>
#
# The remote path travels over stdin, never into the remote command line, so a path in a
# reply cannot run anything. ~/ means the remote home in the remote path and this home in
# the local one. Prints where the file landed.
# Exit: 0 ok, 2 bad arguments, 3 copy failed

target=$1
remote=$2
dest=$3
case "$target" in
  "" | -*) exit 2 ;;
esac
[ -n "$remote" ] && [ -n "$dest" ] || exit 2
case "$dest" in
  "~/"*) dest="$HOME/${dest#"~/"}" ;;
esac
mkdir -p "$(dirname -- "$dest")" || exit 3

printf '%s\n' "$remote" | ssh -o BatchMode=yes -o ConnectTimeout=10 -- "$target" \
  'IFS= read -r p; case "$p" in "~/"*) p="$HOME/${p#"~/"}" ;; esac; exec cat -- "$p"' \
  > "$dest.part" || {
  rm -f "$dest.part"
  exit 3
}
mv -f "$dest.part" "$dest" || exit 3
printf '%s\n' "$dest"
