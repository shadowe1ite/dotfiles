#!/usr/bin/env bash
# CPU or RAM (`sysstat.sh cpu|ram`) for hosts without a battery, around storage: "󰻠 7%  󰋊 3.2G/40G  󰍛 21%"
# Pure bash builtins: no awk/sed/free/top, no sleep. CPU% is the delta since tmux's last refresh.

for p in /sys/class/power_supply/BAT*/capacity; do [[ -r "$p" ]] && exit 0; done

ICON_COLOR="#00D98D"
TEXT_COLOR="#CEE9DC"

read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
busy=$(( total - idle - iowait ))

cache="${XDG_RUNTIME_DIR:-/tmp}/tmux-cpu"
cpu=0
if [[ -r "$cache" ]]; then
  read -r ptotal pbusy < "$cache"
  dt=$(( total - ptotal ))
  (( dt > 0 )) && cpu=$(( (busy - pbusy) * 100 / dt ))
fi
[[ "${1:-}" == cpu ]] && echo "$total $busy" > "$cache"

while read -r key val _; do
  case "$key" in
    MemTotal:) mt=$val ;;
    MemAvailable:) ma=$val; break ;;
  esac
done < /proc/meminfo
mu=$(( mt - ma ))


color() {
  local c="$ICON_COLOR"
  (( $1 >= 75 )) && c="#F5C451"
  (( $1 >= 90 )) && c="#FF5F5F"
  printf '%s' "$c"
}

case "${1:-}" in
  cpu) printf '#[fg=%s]󰻠#[fg=%s] %d%%  ' "$(color "$cpu")" "$TEXT_COLOR" "$cpu" ;;
  ram) ram=$(( mu * 100 / mt )); printf '  #[fg=%s]󰍛#[fg=%s] %d%%' "$(color "$ram")" "$TEXT_COLOR" "$ram" ;;
esac
