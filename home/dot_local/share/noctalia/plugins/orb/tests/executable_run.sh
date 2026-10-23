#!/bin/sh
# Unit tests for the pure modules (lib/motion, lib/life, lib/face helpers).
# Needs the standalone Luau CLI: pacman -S luau
cd "$(dirname "$0")" || exit 1
for t in *_test.luau; do
  echo "== $t"
  luau "$t" || exit 1
done
