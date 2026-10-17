#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/extensions/dbai-custom-kernel.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Regression: Armbian's SDCARD can be readonly during final-image cleanup.
# Supplying an explicit target root must replace that image's /boot without
# trying to assign to or accidentally write through the readonly SDCARD.
# shellcheck disable=SC1091
source "$repo_root/extensions/dbai-custom-bootfs.sh"
display_alert() { :; }
SRC="$tmp/src"
readonly SDCARD="$tmp/readonly-sdcard"
target_root="$tmp/final-image"
mkdir -p "$SRC/userpatches/platform" "$tmp/boot-payload" "$target_root/boot" "$SDCARD/boot"
printf '%s\n' 'old-default-boot-file' > "$target_root/boot/old-default-file"
printf '%s\n' 'readonly-sdcard-sentinel' > "$SDCARD/boot/should-not-be-touched"
printf '%s\n' 'custom-kernel-boot-payload' > "$tmp/boot-payload/Image-6.1.66-DBAI"
tar -czf "$SRC/userpatches/platform/bootfs_custom_kernel.tar.gz" -C "$tmp/boot-payload" .
dbai_replace_bootfs_files "$target_root"
[[ -f "$target_root/boot/Image-6.1.66-DBAI" ]]
[[ ! -e "$target_root/boot/old-default-file" ]]
[[ -f "$SDCARD/boot/should-not-be-touched" ]]
echo "PASS: custom bootfs replacement accepts an explicit root with readonly SDCARD."
status="$tmp/status"
cat > "$status" <<'STATUS'
Package: linux-image-current-meson64
Status: hold ok installed
Architecture: arm64

Package: linux-dtb-current-meson64
Status: install ok installed
Architecture: arm64

Package: linux-headers-current-meson64
Status: deinstall ok config-files
Architecture: arm64

Package: bash
Status: install ok installed
Architecture: arm64
STATUS
mapfile -t packages < <(dbai_list_installed_distro_kernel_packages "$status")
[[ "${#packages[@]}" -eq 2 ]]
printf '%s\n' "${packages[@]}" | grep -Fxq 'linux-image-current-meson64'
printf '%s\n' "${packages[@]}" | grep -Fxq 'linux-dtb-current-meson64'
if printf '%s\n' "${packages[@]}" | grep -Fxq 'linux-headers-current-meson64'; then
  echo 'FAIL: deinstalled kernel headers were reported as installed.' >&2
  exit 1
fi

root="$tmp/root"
mkdir -p "$root/boot/dtb-6.18.57-current-meson64"
touch "$root/boot/vmlinuz-6.18.57-current-meson64" "$root/boot/initrd.img-6.18.57-current-meson64" "$root/boot/System.map-6.18.57-current-meson64"
touch "$root/boot/Image-6.1.66-DBAI" "$root/boot/uInitrd-6.1.66-DBAI"
dbai_prune_noncustom_boot_artifacts "$root" "6.1.66-DBAI"
[[ ! -e "$root/boot/vmlinuz-6.18.57-current-meson64" ]]
[[ ! -e "$root/boot/initrd.img-6.18.57-current-meson64" ]]
[[ ! -e "$root/boot/System.map-6.18.57-current-meson64" ]]
[[ ! -e "$root/boot/dtb-6.18.57-current-meson64" ]]
[[ -f "$root/boot/Image-6.1.66-DBAI" && -f "$root/boot/uInitrd-6.1.66-DBAI" ]]
echo "PASS: residual package status and old versioned boot-artifact checks."

# The final verifier must reject stale initramfs files even when the custom kernel exists.
mkdir -p "$root/etc"
printf '%s\n' 'custom-kernel-payload' > "$root/boot/Image-6.1.66-DBAI"
printf '%s\n' 'custom-initramfs-payload' > "$root/boot/initrd.img-6.1.66-DBAI"
printf '%s\n' 'custom-u-boot-ramdisk-payload' > "$root/boot/uInitrd"
kernel_sha="$(sha256sum "$root/boot/Image-6.1.66-DBAI" | awk '{print $1}')"
initrd_sha="$(sha256sum "$root/boot/initrd.img-6.1.66-DBAI" | awk '{print $1}')"
ramdisk_sha="$(sha256sum "$root/boot/uInitrd" | awk '{print $1}')"
cat > "$root/etc/dbai-custom-kernel-manifest.txt" <<EOF
Kernel release: 6.1.66-DBAI
Boot kernel SHA-256: $kernel_sha
Initramfs file: initrd.img-6.1.66-DBAI
Initramfs SHA-256: $initrd_sha
Boot ramdisk file: uInitrd
Boot ramdisk SHA-256: $ramdisk_sha
EOF
touch "$root/boot/initrd.img-6.18.57-current-meson64"
if dbai_verify_custom_kernel_boot_payload "$root" >/dev/null 2>&1; then
  echo "FAIL: final boot verifier accepted a distro-kernel ramdisk." >&2
  exit 1
fi
echo "PASS: final boot verifier rejects a stale distro-kernel ramdisk."
dbai_prune_noncustom_boot_artifacts "$root" "6.1.66-DBAI"
dbai_verify_custom_kernel_boot_payload "$root"
echo "PASS: custom initramfs and U-Boot ramdisk match their recorded checksums."

