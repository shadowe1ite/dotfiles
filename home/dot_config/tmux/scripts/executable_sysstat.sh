#!/usr/bin/env bash
# CPU and RAM for hosts without a battery (shown next to storage), e.g. " 7%  1.2G/3.8G"
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
echo "$total $busy" > "$cache"

while read -r key val _; do
  case "$key" in
    MemTotal:) mt=$val ;;
    MemAvailable:) ma=$val; break ;;
  esac
done < /proc/meminfo
mu=$(( mt - ma ))

gib() { printf '%d.%dG' $(( $1 / 1048576 )) $(( $1 % 1048576 * 10 / 1048576 )); }

color() {
  local c="$ICON_COLOR"
  (( $1 >= 75 )) && c="#F5C451"
  (( $1 >= 90 )) && c="#FF5F5F"
  printf '%s' "$c"
}

printf '#[fg=%s] #[fg=%s]%d%% #[fg=%s] #[fg=%s]%s/%s ' \
  "$(color "$cpu")" "$TEXT_COLOR" "$cpu" \
  "$(color $(( mu * 100 / mt )))" "$TEXT_COLOR" "$(gib "$mu")" "$(gib "$mt")"
