#!/usr/bin/env python3
"""Patch Armbian's existing MOTD scripts in place for DBAI branding.

This updates Armbian MOTD modules with DBAI-2K26 branding, Sky Cyan & Mint
color harmony, a 3x2 swapped performance grid, and a 2-column commands menu.
"""
from __future__ import annotations

import pathlib
import sys

HEADER_START = "# --- Board name and version line ---"
HEADER_END = "# --- Hardware support status ---"
HEADER_MARKER = "# --- DBAI board and version line ---"

DBAI_HEADER = r"""# --- DBAI board and version line ---
# Prefer the live device-tree model. /etc/armbian-release remains the fallback
# on boards whose DTB has only a generic model string.
DBAI_BOARD_MODEL=""
if [[ -r /proc/device-tree/model ]]; then
	DBAI_BOARD_MODEL="$(tr '\0' '\n' < /proc/device-tree/model | head -n 1 | sed -E 's/ Rev [0-9.]+$//; s/[[:space:]]+$//')"
fi
[[ -n "$DBAI_BOARD_MODEL" ]] || DBAI_BOARD_MODEL="${BOARD_NAME:-${BOARD:-unknown board}}"
if [[ "${DBAI_BOARD_MODEL,,}" =~ b860h[[:space:]_-]*v?([12]) ]]; then
	DBAI_BOARD_MODEL="B860H-V${BASH_REMATCH[1]}"
fi

DBAI_DEVICE_COMPATIBLE=""
if [[ -r /proc/device-tree/compatible ]]; then
	DBAI_DEVICE_COMPATIBLE="$(tr '\0' ' ' < /proc/device-tree/compatible)"
fi
DBAI_SOC=""
case "${DBAI_DEVICE_COMPATIBLE,,}" in
	*s905x4*) DBAI_SOC="Amlogic S905X4" ;;
	*s905y4*) DBAI_SOC="Amlogic S905Y4" ;;
	*s905d4*) DBAI_SOC="Amlogic S905D4" ;;
	*s905x3*) DBAI_SOC="Amlogic S905X3" ;;
	*s905y3*) DBAI_SOC="Amlogic S905Y3" ;;
	*s905d3*) DBAI_SOC="Amlogic S905D3" ;;
	*s905x2*) DBAI_SOC="Amlogic S905X2" ;;
	*s905y2*) DBAI_SOC="Amlogic S905Y2" ;;
	*s905d2*) DBAI_SOC="Amlogic S905D2" ;;
	*s905x*) DBAI_SOC="Amlogic S905X" ;;
	*s905y*) DBAI_SOC="Amlogic S905Y" ;;
	*s905d*) DBAI_SOC="Amlogic S905D" ;;
	*s912*) DBAI_SOC="Amlogic S912" ;;
	*rk3588*) DBAI_SOC="Rockchip RK3588" ;;
	*rk3568*) DBAI_SOC="Rockchip RK3568" ;;
	*rk3566*) DBAI_SOC="Rockchip RK3566" ;;
	*rk3399*) DBAI_SOC="Rockchip RK3399" ;;
	*rk3328*) DBAI_SOC="Rockchip RK3328" ;;
	*sun50i-h618*) DBAI_SOC="Allwinner H618" ;;
	*sun50i-h616*) DBAI_SOC="Allwinner H616" ;;
	*sun50i-a64*) DBAI_SOC="Allwinner A64" ;;
	*sun8i-h3*) DBAI_SOC="Allwinner H3" ;;
	*mt6890*) DBAI_SOC="MediaTek MT6890" ;;
esac

DBAI_BOARD_DISPLAY="$DBAI_BOARD_MODEL"
if [[ -n "$DBAI_SOC" && "${DBAI_BOARD_DISPLAY,,}" != *"${DBAI_SOC,,}"* ]]; then
	DBAI_BOARD_DISPLAY+=" ($DBAI_SOC)"
fi

# Preserve Armbian VERSION; if it ends with "trunk", show "rolling".
if [[ "${VERSION:-}" == *trunk* ]]; then
	VERSION="$(printf '%s' "${VERSION}" | cut -d'.' -f1-2)"
	VERSION="${VERSION} rolling"
fi

printf ' Armbian \e[0;92mv%s\e[0m | Linux \e[0;92m%s\e[0m | running on \e[0;96m%s\e[0m\n' \
	"${VERSION}" "${KERNELID}" "${DBAI_BOARD_DISPLAY}"

"""

TWO_COLUMN_COMMANDS = """#!/bin/bash
# Armbian MOTD: Commands (2 Parallel Columns with Color Harmony)

THIS_SCRIPT="commands"
MOTD_DISABLE=""

safe_source() { [[ -f "$1" ]] && . "$1"; }
safe_source /etc/default/armbian-motd
for f in ${MOTD_DISABLE}; do
	[[ "${f}" == "${THIS_SCRIPT}" ]] && exit 0
done

# Colors
R="\\e[0m"
C_ACCENT="\\e[1;38;2;56;189;248m"   # Sky Blue #38bdf8
C_LABEL="\\e[38;2;148;163;184m"     # Muted Slate #94a3b8

# Kolom 1 (Kiri)
col1_names=("Configuration" "Resize rootfs" "Install to eMMC" "Monitoring")
col1_cmds=("armbian-config" "armbian-tf" "armbian-install" "btop")

# Kolom 2 (Kanan)
col2_names=("Benchmark" "Nokia Utility" "Applications" "Full dump eMMC")
col2_cmds=("imba" "dbai-nokia" "dbai-apps" "dbai-regression")

echo ""
printf " ${C_ACCENT}● Commands:${R}\\n\\n"

for i in {0..3}; do
	name1="${col1_names[$i]}"
	cmd1="${col1_cmds[$i]}"
	name2="${col2_names[$i]}"
	cmd2="${col2_cmds[$i]}"

	# Kolom 1: Awali dengan 1 spasi agar presisi sejajar vertikal dengan Load:, CPU freq:, CPU temp:
	printf " ${C_LABEL}%-16s${R} : ${C_ACCENT}%-16s${R}   " "$name1" "$cmd1"

	# Kolom 2: Sejajar vertikal dengan Uptime:, Memory usage:, Usage of /:
	printf "${C_LABEL}%-16s${R} : ${C_ACCENT}%s${R}\\n" "$name2" "$cmd2"
done
echo ""

exit 0
"""

SWAPPED_SYSINFO = """#!/bin/bash
# Armbian MOTD: System Info (Swapped Performance Grid with Color Harmony)

set -o pipefail
export LC_ALL=C
THIS_SCRIPT="sysinfo"
MOTD_DISABLE=""

safe_source() { [[ -f "$1" ]] && . "$1"; }
safe_source /etc/default/armbian-motd
for f in ${MOTD_DISABLE}; do
	[[ "${f}" == "${THIS_SCRIPT}" ]] && exit 0
done

# Colors - Modern Cyber Sky & Emerald Palette
R="\\e[0m"
C_ACCENT="\\e[1;38;2;56;189;248m"   # Sky Blue #38bdf8
C_LABEL="\\e[38;2;148;163;184m"     # Muted Slate #94a3b8
C_OK="\\e[1;38;2;52;211;153m"       # Mint Emerald #34d399
C_WARN="\\e[1;38;2;251;191;36m"     # Warm Amber #fbbf24
C_CRIT="\\e[1;38;2;248;113;113m"    # Coral Red #f87171
C_SUB="\\e[38;2;100;116;139m"       # Dim Slate #64748b

# 1. Root storage info
rootInfo="$(df -hP /)"
root_usage="$(awk 'NR==2{gsub(/%/,"",$5); print $5}' <<<"$rootInfo")"
root_total="$(awk 'NR==2{print $2}' <<<"$rootInfo")"

# 2. Uptime
format_uptime() {
	local uptime_sec=$(awk '{print int($1)}' /proc/uptime)
	local days=$((uptime_sec / 86400))
	local hours=$(((uptime_sec % 86400) / 3600))
	local minutes=$(((uptime_sec % 3600) / 60))
	local parts=()
	(( days > 0 )) && parts+=("${days}d")
	(( hours > 0 )) && parts+=("${hours}h")
	(( minutes > 0 )) && parts+=("${minutes}m")
	((${#parts[@]} == 0)) && parts=("1m")
	echo "${parts[*]}"
}
uptime_str="$(format_uptime)"

# 3. CPU Load
cpucount="$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)"
read -r load1 _ < /proc/loadavg
[[ "$load1" == 0.0* ]] && load1="0.10"
load_val="$(awk -v l="$load1" -v c="$cpucount" 'BEGIN{printf("%.0f",(l/c)*100)}')"

# 4. Memory info
read -r mem_total_kb _ < <(awk '/MemTotal:/ {print $2" "$3; exit}' /proc/meminfo)
mem_total_mb="$(( mem_total_kb / 1024 ))"
mem_used_kb="$(awk '/MemTotal:/ {t=$2} /MemFree:/ {f=$2} /Buffers:/ {b=$2} /^Cached:/ {c=$2} END{printf("%d", t-f-b-c)}' /proc/meminfo)"
mem_usage_val="$(awk -v u="$mem_used_kb" -v t="$mem_total_kb" 'BEGIN{printf("%.0f", (u/t)*100)}')"
if (( mem_total_mb > 1000 )); then
	memory_total="$(awk -v m="$mem_total_mb" 'BEGIN{printf("%.2fG", m/1024)}')"
else
	memory_total="${mem_total_mb}M"
fi

# 5. CPU Temperature
getboardtemp() {
	board_temp=""
	for s in /sys/class/thermal/thermal_zone*/temp; do
		if [[ -r "$s" ]]; then
			local t=$(cat "$s" 2>/dev/null)
			if [[ -n "$t" && "$t" -gt 0 ]]; then
				board_temp=$(awk -v t="$t" 'BEGIN{printf("%.0f", t/1000)}')
				break
			fi
		fi
	done
}
getboardtemp
cpu_temp_val="${board_temp:-0}"

# 6. CPU Frequency
freq_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq 2>/dev/null)
gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
if [[ -n "$freq_khz" ]]; then
	cpu_freq_val="$(awk -v f="$freq_khz" 'BEGIN{printf("%.2f GHz", f/1000000)}')"
else
	cpu_freq_val="n/a"
fi
[[ -n "$gov" ]] && cpu_freq_extra="(${gov})" || cpu_freq_extra=""

# Dynamic colors
if (( load_val >= 80 )); then load_col="$C_CRIT"; elif (( load_val >= 50 )); then load_col="$C_WARN"; else load_col="$C_OK"; fi
if (( mem_usage_val >= 90 )); then mem_col="$C_CRIT"; elif (( mem_usage_val >= 75 )); then mem_col="$C_WARN"; else mem_col="$C_OK"; fi
if (( cpu_temp_val >= 75 )); then temp_col="$C_CRIT"; elif (( cpu_temp_val >= 60 )); then temp_col="$C_WARN"; else temp_col="$C_OK"; fi
if (( root_usage >= 90 )); then disk_col="$C_CRIT"; elif (( root_usage >= 80 )); then disk_col="$C_WARN"; else disk_col="$C_OK"; fi

# Print Performance Header
echo ""
printf " ${C_ACCENT}● Performance:${R}\\n\\n"

# Helper print cell dengan lebar tepat 38 karakter
print_row() {
	local l1="$1" v1="$2" e1="$3" c1="$4"
	local l2="$5" v2="$6" e2="$7" c2="$8"

	# Col 1
	printf " ${C_LABEL}%-14s${R} ${c1}%s${R}" "$l1" "$v1"
	local v1_clean="${v1//°/*}"
	local len1=$(( 1 + 14 + 1 + ${#v1_clean} ))
	if [[ -n "$e1" ]]; then
		printf " ${C_SUB}%s${R}" "$e1"
		len1=$(( len1 + 1 + ${#e1} ))
	fi
	local pad1=$(( 38 - len1 ))
	(( pad1 < 1 )) && pad1=1
	printf "%*s " "$pad1" ""

	# Col 2
	printf "${C_LABEL}%-14s${R} ${c2}%s${R}" "$l2" "$v2"
	if [[ -n "$e2" ]]; then
		printf " ${C_SUB}%s${R}" "$e2"
	fi
	printf "\\n"
}

# SWAPPED LAYOUT:
# Left column is CPU cluster (Load, Clock Freq, Temp)
# Right column is System resources (Uptime, Memory, Disk root)
print_row "Load:" "${load_val}%" "" "$load_col" "Uptime:" "$uptime_str" "" "$C_OK"
print_row "CPU freq:" "$cpu_freq_val" "$cpu_freq_extra" "$C_ACCENT" "Memory usage:" "${mem_usage_val}%" "of ${memory_total}" "$mem_col"
print_row "CPU temp:" "${cpu_temp_val}°C" "" "$temp_col" "Usage of /:" "${root_usage}%" "of ${root_total}" "$disk_col"
echo ""

exit 0
"""

def patch_header(path: pathlib.Path) -> None:
    text = path.read_text(encoding="utf-8")
    if HEADER_MARKER not in text:
        try:
            start = text.index(HEADER_START)
            end = text.index(HEADER_END, start)
        except ValueError as exc:
            raise SystemExit(f"Unrecognized Armbian header layout: {path}") from exc
        text = text[:start] + DBAI_HEADER + text[end:]

    # Vendor banner block: support /etc/armbian-banner with figlet slant fallback
    banner_logic = r'''# --- Vendor banner ---
if [[ -f /etc/armbian-banner ]]; then
	if [[ -n "${VENDORCOLOR:-}" ]]; then
		printf '\e[38;2;%sm' "${VENDORCOLOR}"
	else
		printf '\e[1;91m'
	fi
	cat /etc/armbian-banner
	printf '\e[0m\n'
elif [[ -n "${VENDORCOLOR:-}" ]]; then
	if command -v figlet >/dev/null 2>&1; then
		printf '\e[38;2;%sm%s\e[0m\n' "${VENDORCOLOR}" "$(figlet -f slant " ${VENDOR}")"
	else
		printf '\e[38;2;%sm### %s ###\e[0m\n' "${VENDORCOLOR}" "${VENDOR}"
	fi
else
	if command -v figlet >/dev/null 2>&1; then
		printf '\e[1;91m%s\e[0m\n' "$(figlet -f slant " ${VENDOR}")"
	else
		printf '\e[1;91m### %s ###\e[0m\n' "${VENDOR}"
	fi
fi
'''
    if 'if [[ -f /etc/armbian-banner ]]' not in text:
        if 'if [[ -n "${VENDORCOLOR:-}" ]]; then' in text:
            start_idx = text.index('if [[ -n "${VENDORCOLOR:-}" ]]; then')
            end_idx = text.index(HEADER_MARKER, start_idx)
            text = text[:start_idx] + banner_logic + "\n" + text[end_idx:]
        elif 'figlet -f ' in text:
            text = text.replace('figlet -f small " ${VENDOR}"', 'figlet -f slant " ${VENDOR}"')

    # Update kernel hold check to detect armbian-bsp package
    if "apt-mark showhold" in text and "armbian-bsp" not in text:
        text = text.replace("grep -q '^linux-image'", "grep -Eq '^linux-image|^armbian-bsp'")
        text = text.replace("grep -q linux-image", "grep -Eq '^linux-image|^armbian-bsp'")

    path.write_text(text, encoding="utf-8")


def patch_commands(path: pathlib.Path) -> None:
    # Completely replace commands file with the clean 2-column layout
    path.write_text(TWO_COLUMN_COMMANDS, encoding="utf-8")
    try:
        path.chmod(0o755)
    except Exception:
        pass


def patch_siblings(motd_dir: pathlib.Path) -> None:
    sysinfo = motd_dir / "30-armbian-sysinfo"
    if sysinfo.is_file():
        sysinfo.write_text(SWAPPED_SYSINFO, encoding="utf-8")
        try:
            sysinfo.chmod(0o755)
        except Exception:
            pass

    ip_info = motd_dir / "20-ip-info"
    if ip_info.is_file():
        text = ip_info.read_text(encoding="utf-8")
        if 'C_LABEL' not in text and 'prefix4=' in text:
            text = text.replace(
                'local prefix4=" IPv4:       "',
                r'local prefix4=" \e[38;2;148;163;184mIPv4:\e[0m        "'
            )
            text = text.replace(
                r'[[ -n "$ipv4s" ]] && line+=" \x1B[93m(LAN)\x1B[0m \x1B[96m${ipv4s// /, }\x1B[0m"',
                r'[[ -n "$ipv4s" ]] && line+=" \e[38;2;100;116;139m(LAN)\e[0m \e[1;38;2;52;211;153m${ipv4s// /, }\x1B[0m"'
            )
            text = text.replace(
                r'[[ -n "$wan4"  ]] && line+=" \x1B[93m(WAN)\x1B[0m \x1B[96m${wan4}\x1B[0m"',
                r'[[ -n "$wan4"  ]] && line+=" \e[38;2;100;116;139m(WAN)\e[0m \e[1;38;2;56;189;248m${wan4}\x1B[0m"'
            )
            ip_info.write_text(text, encoding="utf-8")

    quotes = motd_dir / "quotes.txt"
    if quotes.is_file():
        quotes.write_text("", encoding="utf-8")

    tips = motd_dir / "35-armbian-tips"
    if tips.is_file():
        try:
            tips.chmod(0o644)
        except Exception:
            pass


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: patch-armbian-motd.py /path/to/10-armbian-header /path/to/41-commands")
    header = pathlib.Path(sys.argv[1])
    commands = pathlib.Path(sys.argv[2])
    for path in (header, commands):
        if not path.is_file():
            raise SystemExit(f"Required stock Armbian MOTD script is missing: {path}")
    patch_header(header)
    patch_commands(commands)
    patch_siblings(header.parent)
    print("Patched existing Armbian MOTD header and command list for DBAI.")


if __name__ == "__main__":
    main()
