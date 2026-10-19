#!/usr/bin/env python3
"""Patch Armbian's existing MOTD scripts in place for DBAI branding.

This deliberately preserves the stock Armbian MOTD modules and only changes
its header identity line, vendor wordmark font, and the available command list.
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

printf ' Armbian \\e[0;92mv%s\\e[0m | Linux \\e[0;92m%s\\e[0m | running on \\e[0;96m%s\\e[0m\\n' \\
	"${VERSION}" "${KERNELID}" "${DBAI_BOARD_DISPLAY}"

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
    if 'figlet -f slant " ${VENDOR}"' not in text:
        if 'figlet -f small " ${VENDOR}"' in text:
            text = text.replace('figlet -f small " ${VENDOR}"',
                                'figlet -f slant " ${VENDOR}"', 1)
        elif 'figlet -f ' not in text or '${VENDOR}' not in text:
            raise SystemExit(f"Unrecognized Armbian vendor-logo block: {path}")
    path.write_text(text, encoding="utf-8")


def patch_commands(path: pathlib.Path) -> None:
    text = path.read_text(encoding="utf-8")
    entry = '    "Applications","","dbai-apps","true"'
    if entry not in text:
        anchor = '    "Monitoring","","htop","true"\n)'
        if text.count(anchor) != 1:
            raise SystemExit(f"Unrecognized Armbian command list: {path}")
        text = text.replace(anchor,
                            '    "Monitoring","","htop","true"\n' + entry + '\n)',
                            1)
        path.write_text(text, encoding="utf-8")


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
    print("Patched existing Armbian MOTD header and command list for DBAI.")


if __name__ == "__main__":
    main()
