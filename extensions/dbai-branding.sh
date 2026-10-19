#!/usr/bin/env bash
# Apply DBAI-2K26 branding to stock Armbian metadata and MOTD scripts.
# shellcheck shell=bash

function post_repo_customize_image__dbai_branding() {
	: "${SDCARD:?Armbian did not set SDCARD for DBAI branding}"
	local release_file="${SDCARD}/etc/armbian-release"
	mkdir -p "${SDCARD}/etc"

	python3 - "$release_file" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    lines = path.read_text(encoding="utf-8").splitlines()
except FileNotFoundError:
    lines = []

branding = {
    "VENDOR": "DBAI-2K26",
    "VENDORPRETTYNAME": "DBAI-2K26",
    "VENDORCOLOR": "255;55;55",
}
seen = set()
updated = []
for line in lines:
    key = line.partition("=")[0]
    if key in branding:
        if key not in seen:
            updated.append(f'{key}="{branding[key]}"')
            seen.add(key)
    else:
        updated.append(line)

for key, value in branding.items():
    if key not in seen:
        updated.append(f'{key}="{value}"')

path.write_text("\n".join(updated) + "\n", encoding="utf-8")
print("Set DBAI-2K26 vendor metadata in /etc/armbian-release")
PY

	local dbai_motd_patcher="${SRC}/userpatches/tools/patch-armbian-motd.py"
	local dbai_apps_script="${SRC}/userpatches/tools/dbai-apps.sh"
	local dbai_motd_header="${SDCARD}/etc/update-motd.d/10-armbian-header"
	local dbai_motd_commands="${SDCARD}/etc/update-motd.d/41-commands"

	[[ -s "$dbai_motd_patcher" ]] || exit_with_error "DBAI Armbian MOTD patcher not found: $dbai_motd_patcher"
	[[ -s "$dbai_apps_script" ]] || exit_with_error "DBAI app status CLI not found: $dbai_apps_script"
	[[ -f "$dbai_motd_header" && -f "$dbai_motd_commands" ]] || exit_with_error "Required stock Armbian MOTD files were not found in the target image"

	install -d -m 0755 "${SDCARD}/usr/local/bin"
	install -m 0755 "$dbai_apps_script" "${SDCARD}/usr/local/bin/dbai-apps"
	python3 "$dbai_motd_patcher" "$dbai_motd_header" "$dbai_motd_commands"
	display_alert "DBAI-2K26 branding" "Patched existing Armbian header/commands; preserved stock IP, performance, tips and login sections" "info"
}
