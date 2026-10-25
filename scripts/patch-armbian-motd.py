#!/usr/bin/env python3
"""Patch Armbian's existing MOTD scripts in place for DBAI branding.

This updates Armbian MOTD modules with TrueColor gradient harmony (Neon Pink,
Purple, Sky Cyan, Mint Emerald), selection badge subtitle, a 3x2 swapped
performance grid, and a 2-column commands menu.
"""
from __future__ import annotations

import pathlib
import re
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
case "${DBAI_DEVICE_COMPATIBLE,,} ${DBAI_BOARD_MODEL,,}" in
	*s905x4*) DBAI_SOC="S905X4" ;;
	*s905y4*) DBAI_SOC="S905Y4" ;;
	*s905d4*) DBAI_SOC="S905D4" ;;
	*s905w2*) DBAI_SOC="S905W2" ;;
	*s905x3*) DBAI_SOC="S905X3" ;;
	*s905y3*) DBAI_SOC="S905Y3" ;;
	*s905d3*) DBAI_SOC="S905D3" ;;
	*s905x2*|*b860h-v5*) DBAI_SOC="S905X2" ;;
	*s905y2*) DBAI_SOC="S905Y2" ;;
	*s905d2*) DBAI_SOC="S905D2" ;;
	*p212*|*b860h*|*hg680*|*s905x*) DBAI_SOC="S905X" ;;
	*s905w*) DBAI_SOC="S905W" ;;
	*s905y*) DBAI_SOC="S905Y" ;;
	*s905d*) DBAI_SOC="S905D" ;;
	*p201*|*p200*|*s905*) DBAI_SOC="S905" ;;
	*s912*|*gxm*) DBAI_SOC="S912" ;;
	*a311d2*) DBAI_SOC="A311D2" ;;
	*a311d*) DBAI_SOC="A311D" ;;
	*s922x*) DBAI_SOC="S922X" ;;
	*t962x*) DBAI_SOC="T962X" ;;
	*s805x2*) DBAI_SOC="S805X2" ;;
	*s805x*) DBAI_SOC="S805X" ;;
	*rk3588*) DBAI_SOC="RK3588" ;;
	*rk3576*) DBAI_SOC="RK3576" ;;
	*rk3568*) DBAI_SOC="RK3568" ;;
	*rk3566*) DBAI_SOC="RK3566" ;;
	*rk3399*) DBAI_SOC="RK3399" ;;
	*rk3328*) DBAI_SOC="RK3328" ;;
	*sun50i-h618*|*h618*) DBAI_SOC="H618" ;;
	*sun50i-h616*|*h616*) DBAI_SOC="H616" ;;
	*sun50i-h313*|*h313*) DBAI_SOC="H313" ;;
	*sun50i-a64*|*a64*) DBAI_SOC="A64" ;;
	*sun8i-h3*|*h3*) DBAI_SOC="H3" ;;
	*mt6890*) DBAI_SOC="MT6890" ;;
esac

# Dynamic fallback: if not in explicit list, extract vendor chip name (e.g. amlogic,a311d2 -> A311D2)
if [[ -z "$DBAI_SOC" && -n "$DBAI_DEVICE_COMPATIBLE" ]]; then
	if [[ "$DBAI_DEVICE_COMPATIBLE" =~ (amlogic|rockchip|allwinner),([a-zA-Z0-9_-]+) ]]; then
		raw_soc="${BASH_REMATCH[2]}"
		raw_soc="${raw_soc#meson-}"
		raw_soc="${raw_soc#sun50i-}"
		raw_soc="${raw_soc#sun8i-}"
		DBAI_SOC="${raw_soc^^}"
	fi
fi

DBAI_DEVICE_LABEL="${DBAI_BOARD_MODEL}"
if [[ -n "${DBAI_SOC}" && "${DBAI_DEVICE_LABEL,,}" != *"${DBAI_SOC,,}"* ]]; then
	DBAI_DEVICE_LABEL="${DBAI_BOARD_MODEL} ${DBAI_SOC}"
fi

# Preserve Armbian VERSION; if it ends with "trunk", show "rolling".
if [[ "${VERSION:-}" == *trunk* ]]; then
	VERSION="$(printf '%s' "${VERSION}" | cut -d'.' -f1-2)"
	VERSION="${VERSION} rolling"
fi

# Two-tone badge subtitle matching terminal selection styling
printf ' \e[48;2;226;232;240m\e[1;38;2;15;23;42m Armbian \e[48;2;52;211;153m\e[1;38;2;15;23;42m v%s \e[0m \e[38;2;100;116;139m|\e[0m \e[48;2;226;232;240m\e[1;38;2;15;23;42m Linux \e[48;2;168;85;247m\e[1;38;2;15;23;42m %s \e[0m \e[38;2;100;116;139m|\e[0m \e[48;2;255;42;133m\e[1;38;2;15;23;42m %s \e[0m\n\n' \
	"${VERSION}" "${KERNELID}" "${DBAI_DEVICE_LABEL}"
"""

TWO_COLUMN_COMMANDS = r"""#!/bin/bash
# Armbian MOTD: Commands (2 Parallel Columns with TrueColor Harmony)

THIS_SCRIPT="commands"
MOTD_DISABLE=""

safe_source() { [[ -f "$1" ]] && . "$1"; }
safe_source /etc/default/armbian-motd
for f in ${MOTD_DISABLE}; do
	[[ "${f}" == "${THIS_SCRIPT}" ]] && exit 0
done

# Sembunyikan jika masih dalam proses setup awal first-login
[[ -f /root/.not_logged_in_yet ]] && exit 0


# Colors matching ASCII Art TrueColor palette (Sky Blue, Neon Pink, Purple, Mint, Slate)
R="\e[0m"
C_DOT="\e[1;38;2;255;42;133m"      # Neon Pink #ff2a85
C_TITLE="\e[1;38;2;56;189;248m"    # Sky Blue #38bdf8
C_LABEL="\e[38;2;148;163;184m"     # Muted Slate #94a3b8
C_CMD="\e[1;38;2;56;189;248m"      # Sky Blue #38bdf8
C_SEP="\e[38;2;168;85;247m"        # Purple #a855f7

# Kolom 1 (Kiri)
col1_names=("Configuration" "Resize rootfs" "Install to eMMC" "Monitoring")
col1_cmds=("armbian-config" "armbian-tf" "armbian-install" "btop")

# Kolom 2 (Kanan)
col2_names=("Benchmark" "Nokia Utility" "Applications" "Full dump eMMC")
col2_cmds=("imba" "dbai-nokia" "dbai-apps" "dbai-regression")

echo ""
printf " ${C_DOT}●${R} ${C_TITLE}Commands:${R}\n\n"

for i in {0..3}; do
	name1="${col1_names[$i]}"
	cmd1="${col1_cmds[$i]}"
	name2="${col2_names[$i]}"
	cmd2="${col2_cmds[$i]}"

	# Kolom 1: Awali dengan 1 spasi agar presisi sejajar vertikal
	printf " ${C_LABEL}%-16s${R} ${C_SEP}:${R} ${C_CMD}%-16s${R}   " "$name1" "$cmd1"
	# Kolom 2: Sejajar vertikal
	printf "${C_LABEL}%-16s${R} ${C_SEP}:${R} ${C_CMD}%s${R}\n" "$name2" "$cmd2"
done
echo ""

exit 0
"""

SWAPPED_SYSINFO = r"""#!/bin/bash
# Armbian MOTD: System Info (Swapped Performance Grid with TrueColor Harmony)

set -o pipefail
export LC_ALL=C
THIS_SCRIPT="sysinfo"
MOTD_DISABLE=""

safe_source() { [[ -f "$1" ]] && . "$1"; }
safe_source /etc/default/armbian-motd
for f in ${MOTD_DISABLE}; do
	[[ "${f}" == "${THIS_SCRIPT}" ]] && exit 0
done

# Sembunyikan jika masih dalam proses setup awal first-login
[[ -f /root/.not_logged_in_yet ]] && exit 0


# Colors matching ASCII Art TrueColor palette
R="\e[0m"
C_DOT="\e[1;38;2;255;42;133m"      # Neon Pink #ff2a85
C_TITLE="\e[1;38;2;56;189;248m"    # Sky Blue #38bdf8
C_LABEL="\e[38;2;148;163;184m"     # Muted Slate #94a3b8
C_OK="\e[1;38;2;52;211;153m"       # Mint Emerald #34d399
C_FREQ="\e[1;38;2;168;85;247m"     # Purple #a855f7
C_WARN="\e[1;38;2;251;191;36m"     # Warm Amber #fbbf24
C_CRIT="\e[1;38;2;248;113;113m"    # Coral Red #f87171
C_SUB="\e[38;2;100;116;139m"       # Dim Slate #64748b

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
printf " ${C_DOT}●${R} ${C_TITLE}Performance:${R}\n\n"

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
	printf "\n"
}

# SWAPPED LAYOUT:
# Left column is CPU cluster (Load, Clock Freq, Temp)
# Right column is System resources (Uptime, Memory, Disk root)
print_row "Load:" "${load_val}%" "" "$load_col" "Uptime:" "$uptime_str" "" "$C_OK"
print_row "CPU freq:" "$cpu_freq_val" "$cpu_freq_extra" "$C_FREQ" "Memory usage:" "${mem_usage_val}%" "of ${memory_total}" "$mem_col"
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
    else:
        # Replace existing DBAI header block with updated SoC detection and colors
        start = text.index(HEADER_MARKER)
        end = text.index(HEADER_END, start)
        text = text[:start] + DBAI_HEADER + text[end:]

    # Vendor banner block: support /etc/armbian-banner with figlet slant fallback
    banner_logic = r'''# --- Vendor banner ---
if [[ -f /etc/armbian-banner ]]; then
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

    # Source /etc/os-release if not present to ensure UBUNTU_CODENAME / VERSION_CODENAME are available
    if '[[ -f /etc/os-release ]] && . /etc/os-release' not in text:
        if '[[ -f /etc/armbian-release ]] && . /etc/armbian-release' in text:
            text = text.replace(
                '[[ -f /etc/armbian-release ]] && . /etc/armbian-release',
                '[[ -f /etc/os-release ]] && . /etc/os-release\n[[ -f /etc/armbian-release ]] && . /etc/armbian-release'
            )

    # Ensure distribution status is "stable" for all releases (bullseye, bookworm, trixie, focal, jammy, noble, resolute)
    if '# --- Distribution status line ---' in text:
        distro_block = """# --- Distribution status line ---
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-${DISTRIBUTION_CODENAME:-}}}"
case "${CODENAME,,}" in
	sid|unstable|testing) DISTRO_STATUS=$'\\e[0;93mrolling\\e[0m' ;;
	*)                    DISTRO_STATUS=$'\\e[0;92mstable\\e[0m' ;;
esac
[[ -n "${CODENAME}" ]] && DISTRO_STATUS+=" (${CODENAME})"
"""
        text = re.sub(
            r'# --- Distribution status line ---.*?(?=\n# --- Updates status ---|\Z)',
            distro_block.rstrip(),
            text,
            flags=re.DOTALL
        )

    # Highlight distribution name in Sky Blue and clean up distro name (e.g. Debian GNU/Linux -> Debian)
    if "printf ' Packages:     %s %b\\n'" in text:
        text = text.replace(
            "printf ' Packages:     %s %b\\n' \"${DISTRIBUTION_ID^}\" \"${DISTRO_STATUS}\"",
            "RAW_DISTRO=\"${ID:-${DISTRIBUTION_ID:-${NAME:-Linux}}}\"; DISTRO_NAME=\"${RAW_DISTRO%% *}\"; printf ' Packages:     \\e[1;38;2;56;189;248m%s\\e[0m %b\\n' \"${DISTRO_NAME^}\" \"${DISTRO_STATUS}\""
        )

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
        # Replace prefixes and tags with TrueColor palette
        text = re.sub(r'local prefix4="[^"]+"', r'local prefix4=" \\e[1;38;2;255;42;133mIPv4:\\e[0m        "', text)
        text = re.sub(r'local prefix6="[^"]+"', r'local prefix6=" \\e[1;38;2;255;42;133mIPv6:\\e[0m        "', text)
        text = re.sub(
            r'\[\[ -n "\$ipv4s" \]\] && line\+=[^\n]+',
            r'[[ -n "$ipv4s" ]] && line+=" \\e[38;2;168;85;247m(LAN)\\e[0m \\e[1;38;2;52;211;153m${ipv4s// /, }\\e[0m"',
            text
        )
        text = re.sub(
            r'\[\[ -n "\$wan4"  \]\] && line\+=[^\n]+',
            r'[[ -n "$wan4"  ]] && line+=" \\e[38;2;168;85;247m(WAN)\\e[0m \\e[1;38;2;56;189;248m${wan4}\\e[0m"',
            text
        )
        text = re.sub(
            r'\[\[ -n "\$ipv6s" \]\] && line\+=[^\n]+',
            r'[[ -n "$ipv6s" ]] && line+=" \\e[38;2;168;85;247m(LAN)\\e[0m \\e[1;38;2;52;211;153m${ipv6s// /, }\\e[0m"',
            text
        )
        text = re.sub(
            r'\[\[ -n "\$wan6"  \]\] && line\+=[^\n]+',
            r'[[ -n "$wan6"  ]] && line+=" \\e[38;2;168;85;247m(WAN)\\e[0m \\e[1;38;2;56;189;248m${wan6}\\e[0m"',
            text
        )
        ip_info.write_text(text, encoding="utf-8")

    quotes = motd_dir / "quotes.txt"
    if quotes.is_file():
        quotes.write_text("", encoding="utf-8")

    tips = motd_dir / "35-armbian-tips"
    if tips.is_file():
        tips.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
        try:
            tips.chmod(0o755)
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
