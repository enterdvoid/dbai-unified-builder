# @description Preinstalls Proxmox VE 9 userspace packages from the official no-subscription repository on Debian Trixie while retaining the Armbian kernel and device tree. Amlogic STB compatibility is experimental; official Proxmox ARM64 platform support does not certify this U-Boot/device-tree board.

function extension_prepare_config__dbai_proxmox_official() {
	case "${RELEASE}" in
		trixie) ;;
		*) exit_with_error "Proxmox VE Official packages require Debian Trixie; got ${RELEASE}" ;;
	esac
	[[ "${ARCH}" == "arm64" ]] || exit_with_error "Proxmox VE Official packages require ARM64; got ${ARCH}"
	display_alert "Target image will include Proxmox VE 9 official userspace packages (Armbian kernel retained)" "${RELEASE}" "info"
	EXTRA_IMAGE_SUFFIXES+=("-proxmox-official")
}

function post_repo_customize_image__dbai_install_proxmox_official() {
	display_alert "Adding official Proxmox VE 9 no-subscription repository" "${EXTENSION}" "info"

	run_host_command_logged install -m 0755 -d "${SDCARD}/usr/share/keyrings" "${SDCARD}/etc/apt/preferences.d"
	run_host_command_logged curl --max-time 60 -4 -fsSL "https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg" -o "${SDCARD}/usr/share/keyrings/proxmox-archive-keyring.gpg"
	run_host_command_logged chmod 0644 "${SDCARD}/usr/share/keyrings/proxmox-archive-keyring.gpg"

	cat > "${SDCARD}/etc/apt/sources.list.d/pve-install-repo.sources" <<'PVE_OFFICIAL_SOURCES'
Types: deb
# Proxmox no-subscription repositories use HTTP; APT still verifies signed metadata/packages via Signed-By.
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
PVE_OFFICIAL_SOURCES

	# Avoid a Proxmox meta-package pulling a kernel unsuitable for this U-Boot/DTB image.
	cat > "${SDCARD}/etc/apt/preferences.d/dbai-proxmox-no-kernel.pref" <<'PVE_OFFICIAL_PIN'
Package: proxmox-ve proxmox-default-kernel proxmox-kernel-* proxmox-headers-* pve-kernel-* pve-headers-*
Pin: release *
Pin-Priority: -1
PVE_OFFICIAL_PIN

	chroot_sdcard_apt_get_update

	# Match Armbian's Proxmox module approach: install the manager stack without the kernel meta-package.
	printf '%s\n' \
		"postfix postfix/main_mailer_type select Local only" \
		"postfix postfix/mailname string dbai-proxmox.local" \
		> "${SDCARD}/tmp/dbai-proxmox-postfix.preseed"
	chroot_sdcard "debconf-set-selections /tmp/dbai-proxmox-postfix.preseed"
	chroot_sdcard_apt_get_install pve-manager postfix open-iscsi chrony
	rm -f "${SDCARD}/tmp/dbai-proxmox-postfix.preseed"

	if [[ -f "${SDCARD}/etc/apt/sources.list.d/pve-enterprise.sources" ]]; then
		# Disable the enterprise source within its existing Deb822 stanza. An empty
		# line before Enabled creates a second malformed stanza (APT: missing Types).
		python3 - "${SDCARD}/etc/apt/sources.list.d/pve-enterprise.sources" <<'PVE_DISABLE_ENTERPRISE'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
while lines and not lines[-1].strip():
    lines.pop()
enabled = [i for i, line in enumerate(lines) if line.startswith("Enabled:")]
if enabled:
    lines[enabled[0]] = "Enabled: no"
    for index in reversed(enabled[1:]):
        del lines[index]
else:
    lines.append("Enabled: no")
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PVE_DISABLE_ENTERPRISE
	fi

	# Shared image-import wizard for local files, URLs, common virtual disk formats and archives.
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
