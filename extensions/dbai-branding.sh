#!/usr/bin/env bash
# Apply DBAI-2K26 branding to stock Armbian metadata and MOTD scripts.
# shellcheck shell=bash

function dbai_apply_branding() {
	: "${SDCARD:?Armbian did not set SDCARD for DBAI branding}"
	if [[ -f "${SDCARD}/etc/.dbai_branding_applied" ]]; then
		return 0
	fi
	touch "${SDCARD}/etc/.dbai_branding_applied"

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

	# Install TrueColor PHP2sheel-style gradient ASCII art banner
	base64 -d <<'EOF' > "${SDCARD}/etc/armbian-banner"
IBtbMzg7MjsyNTI7NDM7MTM2bV8bWzM4OzI7MjQ5OzQ0OzE0MG1fG1szODsyOzI0Njs0NjsxNDRt
XxtbMzg7MjsyNDM7NDc7MTQ4bV8bWzM4OzI7MjQwOzQ5OzE1Mm1fICAbWzM4OzI7MjMxOzUzOzE2
M21fG1szODsyOzIyODs1NDsxNjdtXxtbMzg7MjsyMjU7NTY7MTcxbV8bWzM4OzI7MjIyOzU3OzE3
NG1fG1szODsyOzIyMDs1OTsxNzhtXxtbMzg7MjsyMTc7NjA7MTgybV8gG1szODsyOzIxMTs2Mzsx
OTBtXxtbMzg7MjsyMDg7NjU7MTk0bV8bWzM4OzI7MjA1OzY2OzE5N21fG1szODsyOzIwMjs2Nzsy
MDFtXxtbMzg7MjsxOTk7Njk7MjA1bV8bWzM4OzI7MTk2OzcwOzIwOW1fG1szODsyOzE5Mzs3Mjsy
MTNtXyAbWzM4OzI7MTg4Ozc1OzIyMG1fG1szODsyOzE4NTs3NjsyMjRtXxtbMzg7MjsxODI7Nzc7
MjI4bV8bWzM4OzI7MTc5Ozc5OzIzMm1fG1szODsyOzE3Njs4MDsyMzZtXxtbMzg7MjsxNzM7ODI7
MjM5bV8bWzM4OzI7MTcwOzgzOzI0M21fICAgICAgG1szODsyOzEzNDsxMDQ7MjM5bV8bWzM4OzI7
MTI5OzEwODsyMzhtXxtbMzg7MjsxMjM7MTExOzIzN21fG1szODsyOzExODsxMTQ7MjM2bV8bWzM4
OzI7MTEzOzExNzsyMzVtXxtbMzg7MjsxMDc7MTIxOzIzM21fIBtbMzg7Mjs5NjsxMjc7MjMxbV8b
WzM4OzI7OTE7MTMwOzIzMG1fICAbWzM4OzI7NzU7MTQwOzIyNm1fG1szODsyOzY5OzE0MzsyMjVt
XyAbWzM4OzI7NTg7MTUwOzIyM21fG1szODsyOzUzOzE1MzsyMjJtXxtbMzg7Mjs0NzsxNTY7MjIx
bV8bWzM4OzI7NDI7MTYwOzIxOW1fG1szODsyOzM3OzE2MzsyMThtXxtbMzg7MjszMTsxNjY7MjE3
bV8gG1szODsyOzIwOzE3MzsyMTVtXxtbMzg7MjsxNTsxNzY7MjE0bV8bWzM4OzI7OTsxNzk7MjEy
bV8bWzM4OzI7NjsxODI7MjExbV8bWzM4OzI7ODsxODM7MjA5bV8bWzM4OzI7MTA7MTg0OzIwNm1f
IBtbMG0KG1szODsyOzIzNDs1MjsxNjBtfCAgICAgG1szODsyOzIxNjs2MDsxODNtXBtbMzg7Mjsy
MTM7NjI7MTg2bXwgICAbWzM4OzI7MjAyOzY4OzIwMm1fG1szODsyOzE5OTs2OTsyMDVtXyAbWzM4
OzI7MTkzOzcyOzIxM21cICAgG1szODsyOzE4MTs3ODsyMjhtXyAgIBtbMzg7MjsxNzA7ODM7MjQ0
bXwbWzM4OzI7MTY2Ozg1OzI0Nm1fICAgICAbWzM4OzI7MTM0OzEwNTsyMzltXxtbMzg7MjsxMjg7
MTA4OzIzOG18ICAgIBtbMzg7MjsxMDE7MTI0OzIzMm18G1szODsyOzk2OzEyODsyMzFtXxtbMzg7
Mjs5MDsxMzE7MjMwbV8gICAgG1szODsyOzYzOzE0NzsyMjRtfCAgG1szODsyOzQ3OzE1NzsyMjBt
fBtbMzg7Mjs0MTsxNjA7MjE5bS8gIBtbMzg7MjsyNTsxNzA7MjE2bXwbWzM4OzI7MjA7MTczOzIx
NW1fG1szODsyOzE0OzE3NjsyMTNtXyAgICAbWzM4OzI7MTI7MTg1OzIwNG18ICAgIBtbMzg7Mjsy
MTsxOTE7MTkybV8bWzM4OzI7MjI7MTkyOzE5MG1fG1szODsyOzI0OzE5MzsxODhtfBtbMG0KG1sz
ODsyOzIxMzs2MjsxODdtfCAgG1szODsyOzIwNDs2NjsxOThtLRtbMzg7MjsyMDE7Njg7MjAybS0g
IBtbMzg7MjsxOTM7NzI7MjE0bXwgICAbWzM4OzI7MTgxOzc4OzIyOW1fG1szODsyOzE3ODs3OTsy
MzNtXyAbWzM4OzI7MTcyOzgyOzI0MG08ICAgICAgIBtbMzg7MjsxMzM7MTA1OzIzOW18G1szODsy
OzEyODsxMDg7MjM4bV8bWzM4OzI7MTIyOzExMjsyMzdtfCAgIBtbMzg7MjsxMDA7MTI1OzIzMm18
G1szODsyOzk1OzEyODsyMzFtXyAgICAgG1szODsyOzYzOzE0NzsyMjRtfCAgICAbWzM4OzI7MzU7
MTY0OzIxOG1fG1szODsyOzMwOzE2NzsyMTdtXxtbMzg7MjsyNTsxNzA7MjE2bXwgICAgIBtbMzg7
MjsxMDsxODQ7MjA2bTwbWzM4OzI7MTI7MTg1OzIwM218ICAgIBtbMzg7MjsyMTsxOTE7MTkybV8b
WzM4OzI7MjM7MTkyOzE5MG1fG1szODsyOzI0OzE5MzsxODdtfCAgG1szODsyOzMwOzE5NzsxODBt
XxtbMzg7MjszMjsxOTg7MTc4bV8gIBtbMzg7MjszNzsyMDE7MTcxbXwbWzBtChtbMzg7MjsxOTI7
NzI7MjE0bXwbWzM4OzI7MTg5Ozc0OzIxOG1fG1szODsyOzE4Nzs3NTsyMjJtXxtbMzg7MjsxODQ7
Nzc7MjI1bV8bWzM4OzI7MTgxOzc4OzIyOW1fG1szODsyOzE3ODs3OTsyMzNtXxtbMzg7MjsxNzU7
ODE7MjM3bS8bWzM4OzI7MTcyOzgyOzI0MW18G1szODsyOzE2OTs4NDsyNDRtXxtbMzg7MjsxNjU7
ODY7MjQ2bV8bWzM4OzI7MTYwOzg5OzI0NW1fG1szODsyOzE1NDs5MzsyNDRtXxtbMzg7MjsxNDk7
OTY7MjQybV8bWzM4OzI7MTQzOzk5OzI0MW1fG1szODsyOzEzODsxMDI7MjQwbS8bWzM4OzI7MTMy
OzEwNjsyMzltXxtbMzg7MjsxMjc7MTA5OzIzOG1fG1szODsyOzEyMjsxMTI7MjM3bV8bWzM4OzI7
MTE2OzExNTsyMzVtfBtbMzg7MjsxMTE7MTE4OzIzNG1fG1szODsyOzEwNTsxMjI7MjMzbV8bWzM4
OzI7MTAwOzEyNTsyMzJtXxtbMzg7Mjs5NDsxMjg7MjMxbXwbWzM4OzI7ODk7MTMxOzIzMG1fG1sz
ODsyOzg0OzEzNTsyMjhtXxtbMzg7Mjs3ODsxMzg7MjI3bV8bWzM4OzI7NzM7MTQxOzIyNm1fG1sz
ODsyOzY3OzE0NDsyMjVtXxtbMzg7Mjs2MjsxNDg7MjI0bV8bWzM4OzI7NTY7MTUxOzIyM21fG1sz
ODsyOzUxOzE1NDsyMjFtfCAgICAbWzM4OzI7MjQ7MTcwOzIxNW18G1szODsyOzE5OzE3NDsyMTRt
XxtbMzg7MjsxMzsxNzc7MjEzbV8bWzM4OzI7ODsxODA7MjEybV8bWzM4OzI7NzsxODI7MjEwbV8b
WzM4OzI7ODsxODM7MjA4bV8bWzM4OzI7MTA7MTg0OzIwNm1fG1szODsyOzEyOzE4NjsyMDNtfBtb
Mzg7MjsxNDsxODc7MjAxbV8bWzM4OzI7MTY7MTg4OzE5OW1fG1szODsyOzE3OzE4OTsxOTZtfBtb
Mzg7MjsxOTsxOTA7MTk0bVwbWzM4OzI7MjE7MTkxOzE5Mm1fG1szODsyOzIzOzE5MjsxODltXxtb
Mzg7MjsyNTsxOTQ7MTg3bXwbWzM4OzI7MjY7MTk1OzE4NW1fG1szODsyOzI4OzE5NjsxODJtXxtb
Mzg7MjszMDsxOTc7MTgwbV8bWzM4OzI7MzI7MTk4OzE3OG1fG1szODsyOzM0OzE5OTsxNzZtXxtb
Mzg7MjszNTsyMDA7MTczbV8bWzM4OzI7Mzc7MjAxOzE3MW18G1szODsyOzM5OzIwMzsxNjltXxtb
Mzg7Mjs0MTsyMDQ7MTY2bV8bWzM4OzI7NDM7MjA1OzE2NG1fG1szODsyOzQ0OzIwNjsxNjJtXxtb
Mzg7Mjs0NjsyMDc7MTU5bV8bWzM4OzI7NDg7MjA4OzE1N21fG1szODsyOzUwOzIwOTsxNTVtfBtb
MG0K
EOF
	# Ensure issue and issue.net display minimal clean branding without MOTD leaks
	echo -e "\e[1;38;2;56;189;248mDBAI-2K26\e[0m (\\l)\n" > "${SDCARD}/etc/issue"
	echo -e "DBAI-2K26" > "${SDCARD}/etc/issue.net"

	local dbai_motd_patcher=""
	for cand in \
		"${SRC}/userpatches/tools/patch-armbian-motd.py" \
		"${SRC}/tools/patch-armbian-motd.py" \
		"${SRC}/userpatches/extensions/patch-armbian-motd.py" \
		"$(pwd)/scripts/patch-armbian-motd.py" \
		"${GITHUB_WORKSPACE:-}/scripts/patch-armbian-motd.py"; do
		if [[ -s "$cand" ]]; then
			dbai_motd_patcher="$cand"
			break
		fi
	done

	local dbai_apps_script=""
	for cand in \
		"${SRC}/userpatches/tools/dbai-apps.sh" \
		"${SRC}/tools/dbai-apps.sh" \
		"${SRC}/userpatches/extensions/dbai-apps.sh" \
		"$(pwd)/scripts/dbai-apps.sh" \
		"${GITHUB_WORKSPACE:-}/scripts/dbai-apps.sh"; do
		if [[ -s "$cand" ]]; then
			dbai_apps_script="$cand"
			break
		fi
	done

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
		"${SRC}/tools/imba" \
		"${SRC}/userpatches/extensions/imba" \
		"${SRC}/extensions/imba" \
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
	elif [[ -e "${SDCARD}/usr/bin/imba" ]]; then
		ln -sf /usr/bin/imba "${SDCARD}/usr/local/bin/imba"
	fi

	# Install btop monitoring tool on all profiles except Minimal
	local is_minimal="no"
	if [[ "${BUILD_MINIMAL:-no}" == "yes" && "${DESKTOP_OPENBOX:-no}" != "yes" ]]; then
		is_minimal="yes"
	fi

	if [[ "$is_minimal" != "yes" ]]; then
		if declare -F chroot_sdcard_apt_get_install >/dev/null 2>&1; then
			chroot_sdcard_apt_get_install btop || true
		fi
	fi

	# Hold BSP package to show kernel upgrade disabled
	if declare -F chroot_sdcard >/dev/null 2>&1; then
		chroot_sdcard apt-mark hold armbian-bsp-cli-aml-s9xx-box-current 2>/dev/null || true
	fi

	# Truncate sponsor quotes and permanently silence tips MOTD
	if [[ -f "${SDCARD}/etc/update-motd.d/quotes.txt" ]]; then
		: > "${SDCARD}/etc/update-motd.d/quotes.txt"
	fi
	if [[ -f "${SDCARD}/etc/update-motd.d/35-armbian-tips" ]]; then
		cat > "${SDCARD}/etc/update-motd.d/35-armbian-tips" <<'EOF'
#!/bin/bash
exit 0
EOF
		chmod 0755 "${SDCARD}/etc/update-motd.d/35-armbian-tips"
	fi
	# Neutralize background daily quotes updater so it never re-downloads quotes.txt
	if [[ -f "${SDCARD}/etc/cron.daily/armbian-quotes" ]]; then
		cat > "${SDCARD}/etc/cron.daily/armbian-quotes" <<'EOF'
#!/bin/bash
exit 0
EOF
		chmod 0755 "${SDCARD}/etc/cron.daily/armbian-quotes"
	fi

	# Disable automatic rootfs resize on first boot; rely on manual 'armbian-tf'
	mkdir -p "${SDCARD}/root"
	touch "${SDCARD}/root/.no_rootfs_resize"
	mkdir -p "${SDCARD}/etc/systemd/system"
	rm -f "${SDCARD}/etc/systemd/system/multi-user.target.wants/armbian-resize-filesystem.service"
	rm -f "${SDCARD}/etc/systemd/system/basic.target.wants/armbian-resize-filesystem.service"
	ln -sf /dev/null "${SDCARD}/etc/systemd/system/armbian-resize-filesystem.service"

	# Utility placeholders for commands menu: dbai-nokia and dbai-regression
	mkdir -p "${SDCARD}/usr/local/bin"
	if [[ ! -e "${SDCARD}/usr/local/bin/dbai-nokia" ]]; then
		cat > "${SDCARD}/usr/local/bin/dbai-nokia" <<'EOF'
#!/bin/bash
echo -e "\e[1;38;2;56;189;248m[DBAI]\e[0m Utility dbai-nokia sedang dalam tahap penulisan."
exit 0
EOF
		chmod 0755 "${SDCARD}/usr/local/bin/dbai-nokia"
	fi

	if [[ ! -e "${SDCARD}/usr/local/bin/dbai-regression" ]]; then
		if [[ -e "${SDCARD}/usr/sbin/armbian-ddbr" ]]; then
			ln -sf /usr/sbin/armbian-ddbr "${SDCARD}/usr/local/bin/dbai-regression"
		else
			cat > "${SDCARD}/usr/local/bin/dbai-regression" <<'EOF'
#!/bin/bash
echo -e "\e[1;38;2;56;189;248m[DBAI]\e[0m Utility dbai-regression sedang dalam tahap penulisan."
exit 0
EOF
			chmod 0755 "${SDCARD}/usr/local/bin/dbai-regression"
		fi
	fi

	python3 "$dbai_motd_patcher" "$dbai_motd_header" "$dbai_motd_commands"
	display_alert "DBAI-2K26 branding" "Patched existing Armbian header/commands; preserved stock IP, performance, tips and login sections" "info"
}

function pre_customize_image__500_dbai_branding() {
	dbai_apply_branding "$@"
}

function post_repo_customize_image__dbai_branding() {
	dbai_apply_branding "$@"
}

