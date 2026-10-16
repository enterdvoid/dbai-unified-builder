# Experimental package-based Proxmox/PXVIRT integration for Armbian ARM64.
# Deliberately does not install the proxmox-ve meta-package or replace the Armbian kernel.
# shellcheck shell=bash

function extension_prepare_config__dbai_proxmox() {
	case "${ARCH}" in
		arm64) ;;
		*) exit_with_error "DBAI Proxmox/PXVIRT integration currently requires arm64; got ${ARCH}" ;;
	esac
	case "${DBAI_PROXMOX_MODE:-none}" in
		official)
			[[ "${RELEASE}" == "trixie" ]] || exit_with_error "Proxmox official package mode requires Debian trixie; got ${RELEASE}"
			declare -g DBAI_PROXMOX_EFFECTIVE_MODE="official"
			;;
		community)
			[[ "${RELEASE}" == "bookworm" ]] || exit_with_error "PXVIRT community package mode requires Debian bookworm; got ${RELEASE}"
			declare -g DBAI_PROXMOX_EFFECTIVE_MODE="community"
			;;
		both)
			case "${RELEASE}" in
				bookworm) declare -g DBAI_PROXMOX_EFFECTIVE_MODE="community" ;;
				trixie) declare -g DBAI_PROXMOX_EFFECTIVE_MODE="official" ;;
				*) exit_with_error "Proxmox mode both requires bookworm and trixie builds; got ${RELEASE}" ;;
			esac
			;;
		*) exit_with_error "Invalid DBAI_PROXMOX_MODE=${DBAI_PROXMOX_MODE:-unset}" ;;
	esac
	EXTRA_IMAGE_SUFFIXES+=("-proxmox-${DBAI_PROXMOX_EFFECTIVE_MODE}")
	display_alert "DBAI Proxmox" "Selected ${DBAI_PROXMOX_EFFECTIVE_MODE} package integration on Debian ${RELEASE}; Armbian kernel is retained" "warn"
}

function post_repo_customize_image__dbai_install_proxmox_packages() {
	: "${SDCARD:?Armbian did not set SDCARD for Proxmox package installation}"
	chroot_sdcard_apt_get_install curl ca-certificates gnupg
	cat > "${SDCARD}/tmp/dbai-proxmox-install.sh" <<'PVEINSTALL'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
chmod 1777 /tmp
install -d -m 755 /usr/share/keyrings /etc/apt/sources.list.d
for file in /etc/apt/sources.list.d/*; do
  [[ -f "$file" ]] || continue
  if grep -q 'enterprise.proxmox.com' "$file"; then mv "$file" "$file.disabled"; fi
done
case "${DBAI_PROXMOX_EFFECTIVE_MODE}" in
  official)
    curl --fail --location --silent --show-error --retry 3 https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg -o /usr/share/keyrings/proxmox-archive-keyring.gpg
    gpg --show-keys /usr/share/keyrings/proxmox-archive-keyring.gpg >/dev/null 2>&1
    cat > /etc/apt/sources.list.d/pve-no-subscription.sources <<'EOF'
Types: deb
URIs: https://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Architectures: arm64
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    ;;
  community)
    key_ok=0
    for key_url in https://mirrors.lierfang.com/pxcloud/pxvirt/pveport.gpg https://download.lierfang.com/pxcloud/pxvirt/pveport.gpg https://apt.dedi.zone/pxcloud/pxvirt/pveport.gpg; do
      if curl --fail --location --silent --show-error --retry 2 "$key_url" -o /tmp/pxvirt-key.gpg && gpg --show-keys /tmp/pxvirt-key.gpg >/dev/null 2>&1; then
        install -m 644 /tmp/pxvirt-key.gpg /usr/share/keyrings/pxvirt-archive-keyring.gpg
        key_ok=1
        break
      fi
    done
    [[ "$key_ok" == "1" ]] || { echo "Unable to fetch a valid PXVIRT signing key" >&2; exit 1; }
    repo_ok=0
    for repo_url in https://mirrors.lierfang.com/pxcloud/pxvirt https://us.mirrors.lierfang.com/pxcloud/pxvirt https://apt.dedi.zone/pxcloud/pxvirt; do
      cat > /etc/apt/sources.list.d/pxvirt.sources <<EOF
Types: deb
URIs: $repo_url
Suites: bookworm
Components: main
Architectures: arm64
Signed-By: /usr/share/keyrings/pxvirt-archive-keyring.gpg
EOF
      if apt-get update; then repo_ok=1; break; fi
    done
    [[ "$repo_ok" == "1" ]] || { echo "All configured PXVIRT mirrors failed apt update" >&2; exit 1; }
    ;;
  *) echo "Invalid DBAI_PROXMOX_EFFECTIVE_MODE" >&2; exit 2 ;;
esac
apt-get update
# Do not install the proxmox-ve meta-package: it can pull the Proxmox kernel and replace Armbian kernel/DTB.
apt-get install -y --no-install-recommends pve-manager pve-qemu-kvm qemu-server pve-container pve-ha-manager spiceterm
cat > /root/DBAI-PROXMOX-MODE.txt <<EOF
Package mode: ${DBAI_PROXMOX_EFFECTIVE_MODE}
Debian release: $(. /etc/os-release && echo "$VERSION_CODENAME")
Kernel policy: retain Armbian kernel/DTB; package-based PVE/PXVIRT is experimental.
Management URL: https://<device-ip>:8006
Login: root@pam
EOF
PVEINSTALL
	chmod 755 "${SDCARD}/tmp/dbai-proxmox-install.sh"
	chroot_sdcard "DBAI_PROXMOX_EFFECTIVE_MODE=${DBAI_PROXMOX_EFFECTIVE_MODE} bash /tmp/dbai-proxmox-install.sh"
	rm -f "${SDCARD}/tmp/dbai-proxmox-install.sh"
}
