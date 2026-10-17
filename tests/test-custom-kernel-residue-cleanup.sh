#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/extensions/dbai-custom-kernel.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
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
