#!/usr/bin/env bash
# Install the compact DBAI MOTD and on-demand application-status CLI.
# shellcheck shell=bash

function extension_prepare_config__dbai_motd() {
	display_alert "DBAI MOTD" "Inline terminal banner and dbai-apps status command will be installed" "info"
}

function post_repo_customize_image__dbai_motd() {
	: "${SDCARD:?Armbian did not set SDCARD for DBAI MOTD}"

	local renderer_source="${SRC}/userpatches/tools/dbai-motd.sh"
	local apps_source="${SRC}/userpatches/tools/dbai-apps.sh"
	local motd_dir="${SDCARD}/etc/update-motd.d"
	local default_file="${SDCARD}/etc/default/armbian-motd"
	local dbai_default_file="${SDCARD}/etc/default/dbai-motd"

	[[ -s "$renderer_source" ]] || exit_with_error "DBAI MOTD renderer not found: $renderer_source"
	[[ -s "$apps_source" ]] || exit_with_error "DBAI application status script not found: $apps_source"

	install -d -m 0755 "$motd_dir" "${SDCARD}/etc/default" "${SDCARD}/usr/local/bin"
	install -m 0755 "$renderer_source" "$motd_dir/05-dbai-motd"
	install -m 0755 "$apps_source" "${SDCARD}/usr/local/bin/dbai-apps"

	# Disable duplicate Armbian sections through its supported MOTD_DISABLE setting.
	# Preserve other settings and keep the operation idempotent across rebuilds.
	touch "$default_file"
	if ! grep -Fq '# DBAI-MOTD-OVERRIDES-BEGIN' "$default_file"; then
		cat >> "$default_file" <<'DBAI_MOTD_CONFIG'
# DBAI-MOTD-OVERRIDES-BEGIN
MOTD_DISABLE="${MOTD_DISABLE:-} header ap-info ip-info containers-info sysinfo tips commands"
# DBAI-MOTD-OVERRIDES-END
DBAI_MOTD_CONFIG
	fi

	chmod 0644 "$default_file"

	# Keep the legacy banner's WAN IP information, but cap concurrent IPv4/IPv6 lookups.
	# Users may set DBAI_MOTD_WAN_CHECK=0 here to avoid any external request at login.
	touch "$dbai_default_file"
	if ! grep -Eq '^[[:space:]]*DBAI_MOTD_WAN_CHECK[[:space:]]*=' "$dbai_default_file"; then
		printf 'DBAI_MOTD_WAN_CHECK=1\\n' >> "$dbai_default_file"
	fi
	chmod 0644 "$dbai_default_file"

	display_alert "DBAI MOTD installed" "Dynamic board/kernel/system details and dbai-apps CLI enabled; duplicate Armbian sections disabled" "info"
}
