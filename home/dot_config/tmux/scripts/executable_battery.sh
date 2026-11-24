#!/usr/bin/env bash
set -euo pipefail

# Icon color only
ICON_COLOR="#00D98D"   # green (hex)
TEXT_COLOR="#CEE9DC"     # percentage text

# Read capacity
cap=""
for p in /sys/class/power_supply/BAT*/capacity /sys/class/power_supply/*/capacity; do
  if [[ -r "$p" ]]; then
    v="$(tr -cd '0-9' < "$p" 2>/dev/null || true)"
    if [[ -n "$v" ]]; then cap="$v"; break; fi
  fi
done

# No battery (VM/server/Pi): show home storage instead, e.g. "󰋊 3.1G/40G"
if [[ -z "$cap" ]]; then
  if [[ -d /persist ]]; then
    # mothership VM: ~ is a virtiofs share of a ZFS dataset; df shows the whole
    # host pool (TBs), not my refquota. Measure with du (cached 5 min) against
    # the tier quota (large = 40G; override with DISK_QUOTA_GB).
    quota_gb="${DISK_QUOTA_GB:-40}"
    cache="${XDG_RUNTIME_DIR:-/tmp}/tmux-home-du"
    if [[ ! -s "$cache" || -n "$(find "$cache" -mmin +5 2>/dev/null)" ]]; then
      (timeout 60 nice du -sxB1 /persist/home 2>/dev/null | awk '{print $1}' > "$cache.tmp" \
        && mv "$cache.tmp" "$cache") >/dev/null 2>&1 &
    fi
    bytes="$(cat "$cache" 2>/dev/null || echo 0)"
    used="$(numfmt --to=iec --suffix= "${bytes:-0}" 2>/dev/null || echo "?")"
    size="${quota_gb}G"
    pct="$(( ${bytes:-0} * 100 / (quota_gb * 1024 * 1024 * 1024) ))%"
  else
    read -r size used pct < <(df -Ph "$HOME/" 2>/dev/null | awk 'NR==2 {print $2, $3, $5}') || true
  fi
  if [[ -n "${pct:-}" ]]; then
    p="${pct%\%}"
    icon_color="$ICON_COLOR"
    (( p >= 75 )) && icon_color="#F5C451"   # yellow
    (( p >= 90 )) && icon_color="#FF5F5F"   # red
    printf '#[fg=%s]󰋊#[fg=%s] %s/%s' "$icon_color" "$TEXT_COLOR" "$used" "$size"
  fi
  exit 0
fi

# Read status
status="Unknown"
for s in /sys/class/power_supply/BAT*/status /sys/class/power_supply/*/status; do
  if [[ -r "$s" ]]; then
    status="$(tr -d '\n\r' < "$s" 2>/dev/null || true)"
    [[ -n "$status" ]] && break
  fi
done

# Icons (Nerd Fonts)
charging_icons=(󰢜 󰂆 󰂇 󰂈 󰢝 󰂉 󰢞 󰂊 󰂋 󰂅)
discharging_icons=(󱃍 󰁺 󰁻 󰁼 󰁽 󰁿 󰁾 󰂀 󰂁 󰂂 󰁹)

if [[ "$status" == "Charging" || ( "$status" == "Full" && "$cap" -ge 100 ) ]]; then
  icons=("${charging_icons[@]}")
else
  icons=("${discharging_icons[@]}")
fi

n="${#icons[@]}"
idx=$(( cap * (n - 1) / 100 ))
(( idx < 0 )) && idx=0
(( idx >= n )) && idx=$((n - 1))
icon="${icons[$idx]}"

# Icon colored, text white. No bold.
printf '#[fg=%s]%s#[fg=%s] %d%%' "$ICON_COLOR" "$icon" "$TEXT_COLOR" "$cap"
