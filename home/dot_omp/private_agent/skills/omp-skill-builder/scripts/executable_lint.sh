#!/usr/bin/env bash
# Usage: lint.sh <skill-dir>
d=$(realpath "${1:?skill dir}"); f=$d/SKILL.md; w=0; warn(){ echo "WARN: $*"; w=1; }
[ -f "$f" ] || { echo "FAIL: no SKILL.md in $d"; exit 1; }
n=$(sed -n '/^---$/,/^---$/p' "$f" | sed -n 's/^name: *//p'); ds=$(sed -n '/^---$/,/^---$/p' "$f" | sed -n 's/^description: *//p')
[ "$n" = "$(basename "$d")" ] || warn "name '$n' != dir '$(basename "$d")'"
echo "$n" | grep -qE '^[a-z0-9][a-z0-9-]{0,63}$' || warn "bad name format"
[ -n "$ds" ] || warn "missing description"; [ ${#ds} -le 300 ] || warn "description ${#ds} chars (keep <=300)"
s=$(wc -c < "$f"); [ "$s" -le 2048 ] || warn "SKILL.md is $s bytes (max 2048); move detail to references/"
head -1 "$f" | grep -q '^---$' || warn "no frontmatter"
for r in $(grep -oE '(scripts|references)/[A-Za-z0-9._/-]+' "$f" | sort -u); do [ -e "$d/$r" ] || warn "referenced $r missing"; done
for x in "$d"/scripts/*; do [ -e "$x" ] && [ ! -x "$x" ] && warn "$x not executable"; done
[ $w = 0 ] && echo "OK: $n ($s bytes)"
