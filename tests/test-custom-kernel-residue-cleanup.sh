#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/extensions/dbai-custom-kernel.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Regression: Armbian's SDCARD and global version may be readonly.
# shellcheck disable=SC1091
source "$repo_root/extensions/dbai-custom-bootfs.sh"
display_alert() { :; }
SRC="$tmp/src"
readonly SDCARD="$tmp/readonly-sdcard"
# shellcheck disable=SC2034
readonly version="Armbian-global-version"
[[ "$version" == "Armbian-global-version" ]]
target_root="$tmp/final-image"
mkdir -p "$SRC/userpatches/platform" "$tmp/boot-payload" "$target_root/boot" "$SDCARD/boot"
printf '%s\n' 'old-default-boot-file' > "$target_root/boot/old-default-file"
printf '%s\n' 'readonly-sdcard-sentinel' > "$SDCARD/boot/should-not-be-touched"
printf '%s\n' 'boot-script-kernel' > "$tmp/boot-payload/vmlinuz-6.1.66-DBAI"
printf '%s\n' 'original-bundled-u-boot-ramdisk' > "$tmp/boot-payload/uInitrd-6.1.66-DBAI"
tar -czf "$SRC/userpatches/platform/bootfs_custom_kernel.tar.gz" -C "$tmp/boot-payload" .
dbai_replace_bootfs_files "$target_root"
[[ -f "$target_root/boot/vmlinuz-6.1.66-DBAI" ]]
[[ -f "$target_root/boot/uInitrd-6.1.66-DBAI" ]]
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

# Simulate an image after the original kernel and ramdisk have been restored.
root="$tmp/root"
mkdir -p "$root/boot/dtb" "$root/etc"
printf '%s\n' 'unchanged-kernel-content' > "$root/boot/vmlinuz-6.1.66-DBAI"
printf '%s\n' 'unchanged-original-uinitrd-content' > "$root/boot/uInitrd-6.1.66-DBAI"
printf '%s\n' 'custom-dtb' > "$root/boot/dtb/test.dtb"
cat > "$root/boot/uEnv.txt" <<'UENV'
KERNEL=stale-release
LINUX=/Image
INITRD=/uInitrd
APPEND=root=UUID=example rw
UENV
dbai_sync_custom_kernel_uenv "$root/boot/uEnv.txt" "6.1.66-DBAI" "vmlinuz-6.1.66-DBAI" "uInitrd-6.1.66-DBAI"
grep -Fxq 'KERNEL=6.1.66-DBAI' "$root/boot/uEnv.txt"
grep -Fxq 'LINUX=/vmlinuz-6.1.66-DBAI' "$root/boot/uEnv.txt"
grep -Fxq 'INITRD=/uInitrd-6.1.66-DBAI' "$root/boot/uEnv.txt"
grep -Fxq 'APPEND=root=UUID=example rw' "$root/boot/uEnv.txt"
kernel_sha="$(sha256sum "$root/boot/vmlinuz-6.1.66-DBAI" | awk '{print $1}')"
ramdisk_sha="$(sha256sum "$root/boot/uInitrd-6.1.66-DBAI" | awk '{print $1}')"
cat > "$root/etc/dbai-custom-kernel-manifest.txt" <<EOF
Kernel mode: Custom Kernel
Kernel release: 6.1.66-DBAI
Boot kernel file: vmlinuz-6.1.66-DBAI
Boot kernel SHA-256: $kernel_sha
Boot ramdisk file: uInitrd-6.1.66-DBAI
Boot ramdisk SHA-256: $ramdisk_sha
EOF
original_kernel_sha="$kernel_sha"
original_ramdisk_sha="$ramdisk_sha"

printf '%s\n' 'stale-distro-initramfs' > "$root/boot/initrd.img-6.18.57-current-meson64"
if dbai_verify_custom_kernel_boot_payload "$root" >/dev/null 2>&1; then
  echo "FAIL: final boot verifier accepted a stale distro initramfs." >&2
  exit 1
fi
echo "PASS: final boot verifier rejects a stale distro initramfs."
dbai_prune_noncustom_boot_artifacts "$root" "6.1.66-DBAI"
dbai_verify_custom_kernel_boot_payload "$root"
[[ "$(sha256sum "$root/boot/vmlinuz-6.1.66-DBAI" | awk '{print $1}')" == "$original_kernel_sha" ]]
[[ "$(sha256sum "$root/boot/uInitrd-6.1.66-DBAI" | awk '{print $1}')" == "$original_ramdisk_sha" ]]
[[ ! -e "$root/boot/initrd.img-6.18.57-current-meson64" ]]
echo "PASS: original kernel/ramdisk filenames and SHA-256 values survive final verification unchanged."

if declare -F dbai_generate_custom_kernel_initramfs >/dev/null; then
  echo "FAIL: a helper still regenerates the custom initramfs instead of keeping the supplied ramdisk." >&2
  exit 1
fi
if grep -Eq '/usr/sbin/update-initramfs -c -k|dbai_generate_custom_kernel_initramfs' "$repo_root/extensions/dbai-custom-kernel.sh"; then
  echo "FAIL: custom-kernel extension still explicitly regenerates/rewrites the supplied ramdisk." >&2
  exit 1
fi
echo "PASS: custom-kernel finalization does not regenerate or rename the supplied ramdisk."
