#!/usr/bin/env bash
# DBAI-2K26 compact, terminal-safe Armbian MOTD.
# No network requests are made during login; only local system state is read.
set -o pipefail

ROOT="${DBAI_MOTD_ROOT:-}"
target_path() { printf '%s%s' "${ROOT%/}" "$1"; }

if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
  C_RESET='' C_RED='' C_GREEN='' C_CYAN='' C_YELLOW='' C_MAGENTA='' C_DIM=''
else
  C_RESET=$'\033[0m'
  C_RED=$'\033[1;31m'
  C_GREEN=$'\033[1;32m'
  C_CYAN=$'\033[0;36m'
  C_YELLOW=$'\033[0;33m'
  C_MAGENTA=$'\033[0;35m'
  C_DIM=$'\033[0;90m'
fi

read_release_value() {
  local key="$1" file
  file="$(target_path /etc/armbian-release)"
  [[ -r "$file" ]] || return 0
  sed -n "s/^${key}=//p" "$file" | head -n 1 | sed -e 's/^"//' -e 's/"$//'
}

trim_text() {
  sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

version="$(read_release_value VERSION)"
version="${version:-unknown}"
version="${version%-trunk}"
kernel="${DBAI_MOTD_KERNEL_RELEASE:-$(uname -r 2>/dev/null || printf unknown)}"
board_code="$(read_release_value BOARD)"
model_file="$(target_path /proc/device-tree/model)"
model=''
if [[ -r "$model_file" ]]; then
  model="$(tr -d '\000\r\n' < "$model_file" | trim_text)"
fi
[[ -n "$model" ]] || model="$(read_release_value BOARD_NAME)"
[[ -n "$model" ]] || model="${board_code:-unknown board}"

# Normalize the common DBAI TV-box model strings while preserving other DT models.
if [[ "${model,,}" =~ b860h[[:space:]_-]*v?([12]) ]]; then
  model="B860H-V${BASH_REMATCH[1]}"
fi

compat_file="$(target_path /proc/device-tree/compatible)"
compatible=''
if [[ -r "$compat_file" ]]; then
  compatible="$(tr '\000' ' ' < "$compat_file" | trim_text)"
fi
soc=''
hardware_text="${compatible,,} ${model,,} ${board_code,,}"
case "$hardware_text" in
  *s905x4*) soc='Amlogic S905X4' ;;
  *s905y4*) soc='Amlogic S905Y4' ;;
  *s905d4*) soc='Amlogic S905D4' ;;
  *s905x3*) soc='Amlogic S905X3' ;;
  *s905y3*) soc='Amlogic S905Y3' ;;
  *s905d3*) soc='Amlogic S905D3' ;;
  *s905x2*) soc='Amlogic S905X2' ;;
  *s905y2*) soc='Amlogic S905Y2' ;;
  *s905d2*) soc='Amlogic S905D2' ;;
  *s905x*) soc='Amlogic S905X' ;;
  *s905y*) soc='Amlogic S905Y' ;;
  *s905d*) soc='Amlogic S905D' ;;
  *s912*) soc='Amlogic S912' ;;
  *rk3588*) soc='Rockchip RK3588' ;;
  *rk3568*) soc='Rockchip RK3568' ;;
  *rk3566*) soc='Rockchip RK3566' ;;
  *rk3399*) soc='Rockchip RK3399' ;;
  *rk3328*) soc='Rockchip RK3328' ;;
  *sun50i-h618*) soc='Allwinner H618' ;;
  *sun50i-h616*) soc='Allwinner H616' ;;
  *sun50i-a64*) soc='Allwinner A64' ;;
  *sun8i-h3*) soc='Allwinner H3' ;;
  *mt6890*) soc='MediaTek MT6890' ;;
esac
board_display="$model"
if [[ -n "$soc" && "${model,,}" != *"${soc,,}"* ]]; then
  board_display+=" ($soc)"
fi

os_file="$(target_path /etc/os-release)"
os_id=''
os_codename=''
os_pretty=''
if [[ -r "$os_file" ]]; then
  os_id="$(sed -n 's/^ID=//p' "$os_file" | head -n 1 | tr -d '"')"
  os_codename="$(sed -n 's/^VERSION_CODENAME=//p' "$os_file" | head -n 1 | tr -d '"')"
  os_pretty="$(sed -n 's/^PRETTY_NAME=//p' "$os_file" | head -n 1 | tr -d '"')"
fi
case "${os_id,,}" in
  ubuntu) os_name='Ubuntu' ;;
  debian) os_name='Debian' ;;
  '') os_name='' ;;
  *) os_name="${os_id^}" ;;
esac
if [[ -n "$os_name" && -n "$os_codename" ]]; then
  os_display="$os_name $os_codename"
elif [[ -n "$os_pretty" ]]; then
  os_display="$os_pretty"
else
  os_display='OS information unavailable'
fi

updates_file="$(target_path /var/cache/apt/archives/updates.number)"
updates='n/a'
if [[ -r "$updates_file" ]]; then
  parsed_updates="$(sed -n 's/^NUM_UPDATES=//p' "$updates_file" | head -n 1 | tr -d '"[:space:]')"
  [[ "$parsed_updates" =~ ^[0-9]+$ ]] && updates="$parsed_updates"
fi

get_addresses() {
  local family="$1" interface iface_path address all=''
  local net_dir
  net_dir="$(target_path /sys/class/net)"
  if command -v ip >/dev/null 2>&1 && [[ -d "$net_dir" ]]; then
    shopt -s nullglob
    for iface_path in "$net_dir"/*; do
      interface="${iface_path##*/}"
      case "$interface" in
        lo|dummy*|docker*|hassio*|br-*|veth*|vnet*|virbr*|tailscale*|wg*) continue ;;
      esac
      while IFS= read -r address; do
        [[ -n "$address" ]] || continue
        [[ " $all " == *" $address "* ]] || all+="${all:+, }$address"
      done < <(ip "-$family" -o addr show dev "$interface" scope global 2>/dev/null \
        | awk -v family="$family" '$3 == (family == 4 ? "inet" : "inet6") {sub(/\/.*/, "", $4); print $4}')
    done
    shopt -u nullglob
  fi
  if [[ -z "$all" && "$family" == 4 ]] && command -v hostname >/dev/null 2>&1; then
    all="$(hostname -I 2>/dev/null | awk '{$1=$1; print}' | sed 's/ /, /g')"
  fi
  printf '%s' "$all"
}

lan4="${DBAI_MOTD_LAN_IPS:-$(get_addresses 4)}"
lan6="${DBAI_MOTD_IPV6_IPS:-$(get_addresses 6)}"

get_wan_addresses() {
  local enabled="${DBAI_MOTD_WAN_CHECK:-}" config tmp ipv4='' ipv6='' pid4='' pid6=''
  if [[ -z "$enabled" ]]; then
    config="$(target_path /etc/default/dbai-motd)"
    if [[ -r "$config" ]]; then
      enabled="$(sed -n 's/^[[:space:]]*DBAI_MOTD_WAN_CHECK[[:space:]]*=[[:space:]]*//p' "$config" | tail -n 1 | tr -d '"[:space:]')"
    fi
  fi
  [[ -n "$enabled" ]] || enabled=1
  [[ "$enabled" == 1 ]] || { printf '|\\n'; return 0; }
  command -v curl >/dev/null 2>&1 || { printf '|\\n'; return 0; }

  # IPv4 and IPv6 run concurrently, each capped at one second, so a missing
  # network cannot stall SSH login for several seconds.
  tmp="$(mktemp -d 2>/dev/null)" || { printf '|\\n'; return 0; }
  curl --connect-timeout 1 --max-time 1 -4 -fsS https://ipv4.whatismyip.akamai.com/ -o "$tmp/ipv4" >/dev/null 2>&1 &
  pid4=$!
  curl --connect-timeout 1 --max-time 1 -6 -fsS https://ipv6.whatismyip.akamai.com/ -o "$tmp/ipv6" >/dev/null 2>&1 &
  pid6=$!
  wait "$pid4" 2>/dev/null || true
  wait "$pid6" 2>/dev/null || true

  [[ -r "$tmp/ipv4" ]] && ipv4="$(tr -d '\\r\\n' < "$tmp/ipv4")"
  [[ -r "$tmp/ipv6" ]] && ipv6="$(tr -d '\\r\\n' < "$tmp/ipv6")"
  [[ "$ipv4" =~ ^([0-9]{1,3}\\.){3}[0-9]{1,3}$ ]] || ipv4=''
  [[ "$ipv6" =~ ^[0-9A-Fa-f:.]+$ && "$ipv6" == *:* ]] || ipv6=''
  rm -rf "$tmp"
  printf '%s|%s\\n' "$ipv4" "$ipv6"
}
IFS='|' read -r wan4 wan6 < <(get_wan_addresses)

load_percent='n/a'
load_file="$(target_path /proc/loadavg)"
cpuinfo_file="$(target_path /proc/cpuinfo)"
if [[ -r "$load_file" ]]; then
  load_1m="$(awk '{print $1; exit}' "$load_file")"
  cpu_count="$(grep -c '^processor' "$cpuinfo_file" 2>/dev/null || true)"
  [[ "$cpu_count" =~ ^[1-9][0-9]*$ ]] || cpu_count=1
  if [[ "$load_1m" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    load_percent="$(awk -v loadavg_value="$load_1m" -v cpus="$cpu_count" 'BEGIN {printf "%d", (loadavg_value/cpus)*100 + 0.5}')"
  fi
fi

memory_percent='n/a'
memory_total='n/a'
meminfo_file="$(target_path /proc/meminfo)"
if [[ -r "$meminfo_file" ]]; then
  read -r mem_total_kb mem_available_kb < <(awk '
    /^MemTotal:/ {total=$2}
    /^MemAvailable:/ {available=$2}
    END {if (total > 0) printf "%d %d\n", total, available}
  ' "$meminfo_file")
  if [[ "${mem_total_kb:-}" =~ ^[1-9][0-9]*$ ]]; then
    [[ "${mem_available_kb:-}" =~ ^[0-9]+$ ]] || mem_available_kb=0
    memory_percent="$(awk -v total="$mem_total_kb" -v available="$mem_available_kb" 'BEGIN {used=total-available; if (used<0) used=0; printf "%d", used/total*100 + 0.5}')"
    memory_total="$(awk -v kb="$mem_total_kb" 'BEGIN {if (kb>=1048576) printf "%.2fG", kb/1048576; else printf "%.0fM", kb/1024}')"
  fi
fi

cpu_temp='n/a'
thermal_dir="$(target_path /sys/class/thermal)"
best_temp=''
shopt -s nullglob
for temp_file in "$thermal_dir"/thermal_zone*/temp; do
  [[ -r "$temp_file" ]] || continue
  raw_temp="$(cat "$temp_file" 2>/dev/null)"
  [[ "$raw_temp" =~ ^-?[0-9]+$ ]] || continue
  if (( raw_temp > 1000 || raw_temp < -1000 )); then
    degrees="$(awk -v raw="$raw_temp" 'BEGIN {printf "%.0f", raw/1000}')"
  else
    degrees="$raw_temp"
  fi
  (( degrees >= -20 && degrees <= 150 )) || continue
  type_file="${temp_file%/temp}/type"
  sensor_type=''
  [[ -r "$type_file" ]] && sensor_type="$(cat "$type_file" 2>/dev/null)"
  if [[ "${sensor_type,,}" =~ (cpu|soc|package|gpu) ]]; then
    best_temp="$degrees"
    break
  fi
  [[ -n "$best_temp" ]] || best_temp="$degrees"
done
shopt -u nullglob
[[ -n "$best_temp" ]] && cpu_temp="${best_temp}°C"

uptime='n/a'
uptime_file="$(target_path /proc/uptime)"
if [[ -r "$uptime_file" ]]; then
  uptime_seconds="$(awk '{print int($1); exit}' "$uptime_file")"
  if [[ "$uptime_seconds" =~ ^[0-9]+$ ]]; then
    days=$((uptime_seconds / 86400))
    hours=$(((uptime_seconds % 86400) / 3600))
    minutes=$(((uptime_seconds % 3600) / 60))
    if (( days > 0 )); then uptime="${days}d ${hours}h"
    elif (( hours > 0 )); then uptime="${hours}h ${minutes}m"
    else uptime="${minutes}m"
    fi
  fi
fi

users="$(who 2>/dev/null | wc -l | tr -d '[:space:]')"
[[ "$users" =~ ^[0-9]+$ ]] || users=0
root_fs='n/a'
root_df="$(df -hP / 2>/dev/null | awk 'NR==2 {print $5 "/" $2; exit}')"
[[ -n "$root_df" ]] && root_fs="$root_df"

columns="${COLUMNS:-}"
if [[ ! "$columns" =~ ^[0-9]+$ ]] && command -v tput >/dev/null 2>&1; then
  columns="$(tput cols 2>/dev/null || true)"
fi
[[ "$columns" =~ ^[0-9]+$ ]] || columns=80
(( columns < 40 )) && columns=40
(( columns > 140 )) && columns=140
separator() {
  printf '%s' "$C_DIM"
  printf '%*s' "$columns" '' | tr ' ' '-'
  printf '%s\n' "$C_RESET"
}

# figlet is optional; do not make the image depend on it.
if command -v figlet >/dev/null 2>&1 && (( columns >= 65 )); then
  logo="$(figlet -f smslant 'DBAI-2K26' 2>/dev/null || true)"
  if [[ -n "$logo" ]]; then
    while IFS= read -r logo_line; do
      printf '%s%s%s\n' "$C_GREEN" "$logo_line" "$C_RESET"
    done <<< "$logo"
  else
    printf '%sDBAI-2K26%s\n' "$C_GREEN" "$C_RESET"
  fi
else
  printf '%sDBAI-2K26%s\n' "$C_GREEN" "$C_RESET"
fi

printf 'Armbian %sv%s%s | Linux %s%s%s\n' "$C_CYAN" "$version" "$C_RESET" "$C_GREEN" "$kernel" "$C_RESET"
printf 'running on %s%s%s\n' "$C_YELLOW" "$board_display" "$C_RESET"
printf '%sOS:%s %s | %sUpdates:%s ' "$C_CYAN" "$C_RESET" "$os_display" "$C_CYAN" "$C_RESET"
if [[ "$updates" =~ ^[0-9]+$ ]]; then
  printf '%s packages\n' "$updates"
else
  printf 'not yet checked\n'
fi

if [[ -n "$lan4" || -n "$lan6" || -n "$wan4" || -n "$wan6" ]]; then
  printf '%sIP:%s ' "$C_CYAN" "$C_RESET"
  first_ip=1
  if [[ -n "$lan4" ]]; then
    printf '%sLAN%s %s%s%s' "$C_YELLOW" "$C_RESET" "$C_GREEN" "$lan4" "$C_RESET"
    first_ip=0
  fi
  if [[ -n "$lan6" ]]; then
    (( first_ip )) || printf ' | '
    printf '%sLAN IPv6%s %s%s%s' "$C_YELLOW" "$C_RESET" "$C_GREEN" "$lan6" "$C_RESET"
    first_ip=0
  fi
  if [[ -n "$wan4" ]]; then
    (( first_ip )) || printf ' | '
    printf '%sWAN%s %s%s%s' "$C_YELLOW" "$C_RESET" "$C_MAGENTA" "$wan4" "$C_RESET"
    first_ip=0
  fi
  if [[ -n "$wan6" ]]; then
    (( first_ip )) || printf ' | '
    printf '%sWAN IPv6%s %s%s%s' "$C_YELLOW" "$C_RESET" "$C_MAGENTA" "$wan6" "$C_RESET"
  fi
  printf '\n'
fi

temp_color="$C_GREEN"
if [[ "$cpu_temp" =~ ^([0-9]+)°C$ ]]; then
  temp_value="${BASH_REMATCH[1]}"
  (( temp_value >= 70 )) && temp_color="$C_RED"
  (( temp_value >= 60 && temp_value < 70 )) && temp_color="$C_YELLOW"
fi

if (( columns >= 118 )); then
  printf 'Load: %s%s%%%s | Memory: %s%s%%%s of %s | CPU: %s%s%s | Uptime: %s%s%s | Users: %s%s%s | RootFS: %s%s%s\n' \
    "$C_GREEN" "$load_percent" "$C_RESET" "$C_GREEN" "$memory_percent" "$C_RESET" "$memory_total" \
    "$temp_color" "$cpu_temp" "$C_RESET" "$C_GREEN" "$uptime" "$C_RESET" "$C_GREEN" "$users" "$C_RESET" "$C_GREEN" "$root_fs" "$C_RESET"
else
  printf 'Load: %s%s%%%s | Memory: %s%s%%%s of %s | CPU: %s%s%s | Up: %s%s%s\n' \
    "$C_GREEN" "$load_percent" "$C_RESET" "$C_GREEN" "$memory_percent" "$C_RESET" "$memory_total" \
    "$temp_color" "$cpu_temp" "$C_RESET" "$C_GREEN" "$uptime" "$C_RESET"
  printf 'Users: %s%s%s | RootFS: %s%s%s\n' "$C_GREEN" "$users" "$C_RESET" "$C_GREEN" "$root_fs" "$C_RESET"
fi

separator
commands=()
for candidate in armbian-config armbian-upgrade htop dbai-apps; do
  if command -v "$candidate" >/dev/null 2>&1; then commands+=("$candidate"); fi
done
printf '%sCommands:%s ' "$C_CYAN" "$C_RESET"
for index in "${!commands[@]}"; do
  (( index > 0 )) && printf ' %s|%s ' "$C_DIM" "$C_RESET"
  if [[ "${commands[$index]}" == 'dbai-apps' ]]; then
    printf '%s%s%s' "$C_MAGENTA" "${commands[$index]}" "$C_RESET"
  else
    printf '%s%s%s' "$C_GREEN" "${commands[$index]}" "$C_RESET"
  fi
done
printf '\n'
printf '%sTip:%s Proxmox on ARM board? https://tinyurl.com/2ecpuzk3\n' "$C_YELLOW" "$C_RESET"
