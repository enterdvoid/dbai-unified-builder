#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/root"
bin="$tmp/bin"
mkdir -p "$bin" \
  "$root/etc" "$root/proc/device-tree" "$root/proc" \
  "$root/sys/class/thermal/thermal_zone0" \
  "$root/sys/class/net/eth0" "$root/sys/class/net/wlan0" \
  "$root/var/cache/apt/archives"

cat > "$root/etc/armbian-release" <<'RELEASE'
VERSION="25.05.0"
BOARD="aml-s9xx-box"
BOARD_NAME="Amlogic S9xx TV Box"
RELEASE
cat > "$root/etc/os-release" <<'OS'
ID=ubuntu
VERSION_CODENAME=jammy
PRETTY_NAME="Ubuntu 22.04 LTS"
OS
printf 'ZTE B860H V2\000' > "$root/proc/device-tree/model"
printf 'amlogic,meson-gxl-s905x\000amlogic,meson-gxl\000' > "$root/proc/device-tree/compatible"
printf 'NUM_UPDATES=164\n' > "$root/var/cache/apt/archives/updates.number"
printf '0.24 0.10 0.01 1/123 456\n' > "$root/proc/loadavg"
cat > "$root/proc/cpuinfo" <<'CPU'
processor : 0
processor : 1
processor : 2
processor : 3
CPU
cat > "$root/proc/meminfo" <<'MEM'
MemTotal:        1810432 kB
MemFree:          120000 kB
MemAvailable:    1600000 kB
MEM
printf '180.00 120.00\n' > "$root/proc/uptime"
printf '61000\n' > "$root/sys/class/thermal/thermal_zone0/temp"
printf 'cpu-thermal\n' > "$root/sys/class/thermal/thermal_zone0/type"

cat > "$bin/uname" <<'UNAME'
#!/usr/bin/env bash
[[ "${1:-}" == '-r' ]] && printf '6.1.66-DBAI\n' || /usr/bin/uname "$@"
UNAME
cat > "$bin/ip" <<'IP'
#!/usr/bin/env bash
family="$1"
interface=''
while (($#)); do
  if [[ "$1" == dev ]]; then interface="${2:-}"; break; fi
  shift
done
case "$family:$interface" in
  -4:eth0) printf '%s\n' '2: eth0 inet 192.168.2.206/24 scope global eth0' ;;
  -4:wlan0) printf '%s\n' '3: wlan0 inet 192.168.2.138/24 scope global wlan0' ;;
  -6:eth0) printf '%s\n' '2: eth0 inet6 2001:db8::123/64 scope global eth0' ;;
esac
IP
cat > "$bin/df" <<'DF'
#!/usr/bin/env bash
printf '%s\n' 'Filesystem Size Used Avail Use% Mounted on' '/dev/root 6.5G 2.9G 3.6G 45% /'
DF
cat > "$bin/who" <<'WHO'
#!/usr/bin/env bash
printf '%s\n' 'root pts/0 2026-10-19 10:00' 'admin pts/1 2026-10-19 10:01'
WHO
cat > "$bin/figlet" <<'FIGLET'
#!/usr/bin/env bash
printf '%s\n' '  DBAI-2K26'
FIGLET
for command_name in armbian-config armbian-upgrade htop dbai-apps; do
  cat > "$bin/$command_name" <<'CMD'
#!/usr/bin/env bash
exit 0
CMD
  chmod 0755 "$bin/$command_name"
done
chmod 0755 "$bin/uname" "$bin/ip" "$bin/df" "$bin/who" "$bin/figlet"

output="$tmp/motd.out"
PATH="$bin:$PATH" NO_COLOR=1 COLUMNS=80 DBAI_MOTD_ROOT="$root" \
  bash "$repo_root/scripts/dbai-motd.sh" > "$output"

grep -Fq 'DBAI-2K26' "$output"
grep -Fq 'Armbian v25.05.0 | Linux 6.1.66-DBAI' "$output"
grep -Fq 'running on B860H-V2 (Amlogic S905X)' "$output"
grep -Fq 'OS: Ubuntu jammy | Updates: 164 packages' "$output"
grep -Fq '192.168.2.206' "$output"
grep -Fq '192.168.2.138' "$output"
grep -Fq 'Load: 6%' "$output"
grep -Fq 'CPU: 61°C' "$output"
grep -Fq 'RootFS: 45%/6.5G' "$output"
grep -Fq 'dbai-apps' "$output"

# A small terminal should use the plain-text logo instead of a wide figlet banner.
small="$tmp/small.out"
PATH="$bin:$PATH" NO_COLOR=1 COLUMNS=50 DBAI_MOTD_ROOT="$root" \
  bash "$repo_root/scripts/dbai-motd.sh" > "$small"
grep -Fq 'DBAI-2K26' "$small"

echo 'PASS: MOTD detects board/SoC/kernel dynamically and displays compact local metrics.'
