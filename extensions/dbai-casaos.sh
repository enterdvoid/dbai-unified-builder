# Experimental CasaOS first-boot installer extension.
# The install runs on the actual target hardware so architecture detection is not taken from the build runner.
# shellcheck shell=bash

function extension_prepare_config__dbai_casaos() {
	case "${RELEASE}" in
		bookworm|trixie)
			display_alert "DBAI CasaOS" "Will install CasaOS on first boot for Debian ${RELEASE}" "info"
			;;
		*)
			exit_with_error "DBAI CasaOS extension currently allows bookworm and trixie only; got ${RELEASE}"
			;;
	esac
	case "${ARCH}" in
		arm64|amd64)
			;;
		*)
			exit_with_error "DBAI CasaOS extension requires arm64 or amd64; got ${ARCH}"
			;;
	esac
	EXTRA_IMAGE_SUFFIXES+=("-casaos")
}

function pre_customize_image__dbai_stage_casaos_firstboot() {
	: "${SDCARD:?Armbian did not set SDCARD for CasaOS first-boot staging}"
	chroot_sdcard_apt_get_install curl ca-certificates
	mkdir -p "${SDCARD}/usr/local/sbin" "${SDCARD}/etc/systemd/system/multi-user.target.wants" "${SDCARD}/var/lib/dbai"

	cat > "${SDCARD}/usr/local/sbin/dbai-casaos-firstboot.sh" <<'CASAOS'
#!/usr/bin/env bash
set -euo pipefail
exec >> /var/log/dbai-casaos-firstboot.log 2>&1
mkdir -p /var/lib/dbai
if [[ -f /var/lib/dbai/casaos-install-complete ]]; then
  exit 0
fi
echo "Installing CasaOS on the target device. This requires internet access and can take several minutes."
curl --fail --location --silent --show-error https://get.casaos.io -o /tmp/dbai-casaos-install.sh
bash /tmp/dbai-casaos-install.sh
touch /var/lib/dbai/casaos-install-complete
systemctl disable dbai-casaos-firstboot.service || true
CASAOS
	chmod 755 "${SDCARD}/usr/local/sbin/dbai-casaos-firstboot.sh"

	cat > "${SDCARD}/etc/systemd/system/dbai-casaos-firstboot.service" <<'UNIT'
[Unit]
Description=Install CasaOS on first boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/dbai/casaos-install-complete

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/dbai-casaos-firstboot.sh
Restart=on-failure
RestartSec=60
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT
	ln -sf ../dbai-casaos-firstboot.service "${SDCARD}/etc/systemd/system/multi-user.target.wants/dbai-casaos-firstboot.service"
	display_alert "DBAI CasaOS" "CasaOS will install at first boot on the target hardware; validate network and runtime after flashing" "warn"
}
