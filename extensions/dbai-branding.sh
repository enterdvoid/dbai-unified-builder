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
    "VENDORCOLOR": "56;189;248",
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

	# Install ASCII art banner
	cat > "${SDCARD}/etc/armbian-banner" <<'EOF'
 _____  ______ _______ _______      ______ __  __ ______ ______ 
|     \|   __ \   _   |_     _|    |__    |  |/  |__    |    __|
|  --  |   __ <       |_|   |_     |    __|     <|    __|  __  |
|_____/|______/___|___|_______|    |______|__|\__|______|______|
EOF

	local dbai_motd_patcher="${SRC}/userpatches/tools/patch-armbian-motd.py"
	local dbai_apps_script="${SRC}/userpatches/tools/dbai-apps.sh"
	local dbai_motd_header="${SDCARD}/etc/update-motd.d/10-armbian-header"
	local dbai_motd_commands="${SDCARD}/etc/update-motd.d/41-commands"

	[[ -s "$dbai_motd_patcher" ]] || exit_with_error "DBAI Armbian MOTD patcher not found: $dbai_motd_patcher"
	[[ -s "$dbai_apps_script" ]] || exit_with_error "DBAI app status CLI not found: $dbai_apps_script"
	[[ -f "$dbai_motd_header" && -f "$dbai_motd_commands" ]] || exit_with_error "Required stock Armbian MOTD files were not found in the target image"

	install -d -m 0755 "${SDCARD}/usr/local/bin"
	install -m 0755 "$dbai_apps_script" "${SDCARD}/usr/local/bin/dbai-apps"

	local dbai_imba_script=""
	for cand in \
		"${SRC}/userpatches/tools/imba" \
		"${SRC}/userpatches/extensions/imba" \
		"${SRC}/../scripts/imba" \
		"$(pwd)/scripts/imba" \
		"${GITHUB_WORKSPACE:-}/scripts/imba"; do
		if [[ -s "$cand" ]]; then
			dbai_imba_script="$cand"
			break
		fi
	done

	if [[ -n "$dbai_imba_script" ]]; then
		install -m 0755 "$dbai_imba_script" "${SDCARD}/usr/local/bin/imba"
	fi

	# Install btop monitoring tool if chroot apt helper exists
	if declare -F chroot_sdcard_apt_get_install >/dev/null 2>&1; then
		chroot_sdcard_apt_get_install btop || true
	fi

	# Hold BSP package to show kernel upgrade disabled
	if declare -F chroot_sdcard >/dev/null 2>&1; then
		chroot_sdcard apt-mark hold armbian-bsp-cli-aml-s9xx-box-current 2>/dev/null || true
	fi

	# Truncate sponsor quotes and disable tips
	if [[ -f "${SDCARD}/etc/update-motd.d/quotes.txt" ]]; then
		: > "${SDCARD}/etc/update-motd.d/quotes.txt"
	fi
	if [[ -f "${SDCARD}/etc/update-motd.d/35-armbian-tips" ]]; then
		chmod -x "${SDCARD}/etc/update-motd.d/35-armbian-tips" 2>/dev/null || true
	fi

	python3 "$dbai_motd_patcher" "$dbai_motd_header" "$dbai_motd_commands"
	display_alert "DBAI-2K26 branding" "Patched existing Armbian header/commands; preserved stock IP, performance, tips and login sections" "info"
}
