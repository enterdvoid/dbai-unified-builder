# @description Preinstalls PXVIRT 8, the community-maintained Proxmox-derived ARM64 virtualization stack, from its Bookworm repository. Retains the Armbian kernel and device tree for U-Boot-based TV boxes; storage bridging and guest configuration remain user tasks.

function extension_prepare_config__dbai_proxmox_community() {
	case "${RELEASE}" in
		bookworm) ;;
		*) exit_with_error "Proxmox Community (PXVIRT 8) requires Debian Bookworm; got ${RELEASE}" ;;
	esac
	[[ "${ARCH}" == "arm64" ]] || exit_with_error "Proxmox Community (PXVIRT 8) requires ARM64; got ${ARCH}"
	display_alert "Target image will include PXVIRT 8 community userspace packages (Armbian kernel retained)" "${RELEASE}" "info"
	EXTRA_IMAGE_SUFFIXES+=("-proxmox-community")
}

function post_repo_customize_image__dbai_install_proxmox_community() {
	display_alert "Adding PXVIRT 8 community repository for Debian Bookworm" "${EXTENSION}" "info"

	run_host_command_logged install -m 0755 -d "${SDCARD}/usr/share/keyrings" "${SDCARD}/etc/apt/preferences.d"
	# APT drops privileges to _apt and requires /tmp to be world-writable with the sticky bit (01777).
	run_host_command_logged install -m 1777 -d "${SDCARD}/tmp"
	run_host_command_logged chmod 1777 "${SDCARD}/tmp"

	# The primary mirror returned HTTP 403 in GitHub Actions. Prefer the documented
	# US mirror, then try the JP and primary mirrors. Use the same mirror for both
	# the signing key and repository so a partial/mismatched mirror cannot be selected.
	local -a pxvirt_mirrors=(
		"https://us.mirrors.lierfang.com/pxcloud/pxvirt"
		"https://jp.mirrors.lierfang.com/pxcloud/pxvirt"
		"https://mirrors.lierfang.com/pxcloud/pxvirt"
	)
	local pxvirt_repo_base=""
	local pxvirt_key_tmp="${SDCARD}/tmp/lierfang.gpg.tmp"
	local pxvirt_release_tmp="${SDCARD}/tmp/pxvirt-InRelease.tmp"
	local candidate
	for candidate in "${pxvirt_mirrors[@]}"; do
		rm -f "$pxvirt_key_tmp" "$pxvirt_release_tmp"
		display_alert "Checking PXVIRT mirror" "$candidate" "info"
		if curl --fail --location --silent --show-error --connect-timeout 15 --max-time 60 --retry 1 -4 "$candidate/pveport.gpg" -o "$pxvirt_key_tmp" \
			&& [[ -s "$pxvirt_key_tmp" ]] \
			&& curl --fail --location --silent --show-error --connect-timeout 15 --max-time 60 --retry 1 -4 "$candidate/dists/bookworm/InRelease" -o "$pxvirt_release_tmp" \
			&& [[ -s "$pxvirt_release_tmp" ]]; then
			# Reject an HTML error page or invalid key if GnuPG is available in the build container.
			if command -v gpg >/dev/null 2>&1 && ! gpg --batch --show-keys "$pxvirt_key_tmp" >/dev/null 2>&1; then
				echo "PXVIRT mirror returned a file that is not a readable OpenPGP key: $candidate" >&2
				continue
			fi
			pxvirt_repo_base="$candidate"
			break
		fi
		echo "PXVIRT mirror failed key/Release preflight; trying the next mirror: $candidate" >&2
	done
	rm -f "$pxvirt_release_tmp"
	if [[ -z "$pxvirt_repo_base" ]]; then
		rm -f "$pxvirt_key_tmp"
		exit_with_error "Could not fetch a valid PXVIRT key and Bookworm InRelease from any documented mirror"
	fi
	mv "$pxvirt_key_tmp" "${SDCARD}/usr/share/keyrings/lierfang.gpg"
	run_host_command_logged chmod 0644 "${SDCARD}/usr/share/keyrings/lierfang.gpg"
	display_alert "Using PXVIRT repository mirror" "$pxvirt_repo_base" "info"

	cat > "${SDCARD}/etc/apt/sources.list.d/pxvirt-sources.list" <<PXVIRT_SOURCES
deb [arch=arm64 signed-by=/usr/share/keyrings/lierfang.gpg] ${pxvirt_repo_base} bookworm main
PXVIRT_SOURCES

	# Do not replace the Armbian kernel/headers needed by the STB's U-Boot and DTB.
	cat > "${SDCARD}/etc/apt/preferences.d/dbai-pxvirt-no-kernel.pref" <<'PXVIRT_PIN'
Package: proxmox-ve proxmox-default-kernel proxmox-kernel-* proxmox-headers-* pve-kernel-* pve-headers-*
Pin: release *
Pin-Priority: -1
PXVIRT_PIN

	chroot_sdcard_apt_get_update
	printf '%s\n' \
		"postfix postfix/main_mailer_type select Local only" \
		"postfix postfix/mailname string dbai-pxvirt.local" \
		> "${SDCARD}/tmp/dbai-pxvirt-postfix.preseed"
	chroot_sdcard "debconf-set-selections /tmp/dbai-pxvirt-postfix.preseed"

	# Install PXVIRT's manager and guest stack, deliberately omitting the kernel meta-package.
	chroot_sdcard_apt_get_install pve-manager pve-qemu-kvm qemu-server pve-cluster pve-container postfix open-iscsi chrony
	rm -f "${SDCARD}/tmp/dbai-pxvirt-postfix.preseed"

	# Keep the same VM image-import workflow on the community Proxmox variant.
	chroot_sdcard_apt_get_install curl wget whiptail unzip xz-utils zstd gzip bzip2 python3
	run_host_command_logged install -m 0755 tools/dbai-vm-import "${SDCARD}/usr/local/sbin/dbai-vm-import"
	dbai_proxmox_add_firstboot_hostname_service
}

function dbai_proxmox_add_firstboot_hostname_service() {
	run_host_command_logged install -m 0755 -d \
		"${SDCARD}/usr/local/sbin" \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants"
	cat > "${SDCARD}/usr/local/sbin/dbai-proxmox-hosts" <<'DBAI_PVE_HOSTS'
#!/bin/sh
set -eu
host="$(hostname -s 2>/dev/null || hostname)"
[ -n "$host" ] || exit 0
ip_addr=""
attempt=0
while [ "$attempt" -lt 30 ]; do
	ip_addr="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i=1; i<=NF; i++) if ($i=="src" && i<NF) { print $(i+1); exit } }')"
	if [ -z "$ip_addr" ]; then
		ip_addr="$(ip -o -4 addr show scope global 2>/dev/null | awk '$2 !~ /^(docker|br-|veth|virbr)/ { split($4,a,"/"); print a[1]; exit }')"
	fi
	[ -n "$ip_addr" ] && break
	attempt=$((attempt + 1))
	sleep 2
done
if [ -z "$ip_addr" ]; then
	logger -t dbai-proxmox-hosts "No non-loopback IPv4 address found; check hostname mapping and network manually."
	exit 0
fi
tmp="$(mktemp)"
awk -v h="$host" -v hf="$host.local" '{
	skip=0
	if ($1 !~ /^#/) {
		for (i=2; i<=NF; i++) if ($i==h || $i==hf) skip=1
	}
	if (!skip) print
}' /etc/hosts > "$tmp"
printf '%s\t%s %s.local\n' "$ip_addr" "$host" "$host" >> "$tmp"
cat "$tmp" > /etc/hosts
rm -f "$tmp"
logger -t dbai-proxmox-hosts "Mapped $host to $ip_addr for Proxmox services."
DBAI_PVE_HOSTS
	run_host_command_logged chmod 0755 "${SDCARD}/usr/local/sbin/dbai-proxmox-hosts"

	cat > "${SDCARD}/etc/systemd/system/dbai-proxmox-hosts.service" <<'DBAI_PVE_SERVICE'
[Unit]
Description=Resolve DBAI Proxmox hostname to the current LAN address
Wants=network-online.target
After=network-online.target
Before=pve-cluster.service pvedaemon.service pveproxy.service pvestatd.service
ConditionPathExists=/usr/bin/pveversion

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/dbai-proxmox-hosts
RemainAfterExit=yes
TimeoutStartSec=90

[Install]
WantedBy=multi-user.target
DBAI_PVE_SERVICE

	ln -sfn ../dbai-proxmox-hosts.service "${SDCARD}/etc/systemd/system/multi-user.target.wants/dbai-proxmox-hosts.service"
	for unit in pve-cluster pvedaemon pveproxy pvestatd; do
		run_host_command_logged install -m 0755 -d "${SDCARD}/etc/systemd/system/${unit}.service.d"
		cat > "${SDCARD}/etc/systemd/system/${unit}.service.d/10-dbai-hostname.conf" <<'DBAI_PVE_DROPIN'
[Unit]
Requires=dbai-proxmox-hosts.service
After=dbai-proxmox-hosts.service
DBAI_PVE_DROPIN
	done
}
