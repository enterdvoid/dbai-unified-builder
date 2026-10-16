#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-inputs.sh"

bash "$VALIDATOR" "orangepi5" "" "bookworm,trixie" "minimal,server" "both" "Kernel Official" "none"
bash "$VALIDATOR" "aml-s9xx-box" "" "trixie" "server" "ext4" "Recompile Kernel Official" "none"
bash "$VALIDATOR" "custom" "my-custom-board" "bookworm" "application" "ext4" "Kernel Official" "casaos"
bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm,trixie,jammy,noble,resolute" "minimal,server,application,desktop" "both" "Kernel Official" "casaos"
bash "$VALIDATOR" "aml-s9xx-box" "" "bullseye,bookworm,trixie,forky" "minimal,server" "ext4" "Kernel Official" "none"
bash "$VALIDATOR" "aml-s9xx-box" "" "jammy,noble,resolute" "minimal,server" "ext4" "Kernel Official" "none"
bash "$VALIDATOR" "aml-s9xx-box" "" "trixie,resolute" "minimal,server,application" "ext4" "Custom Kernel" "casaos"
bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm,trixie" "application" "both" "Kernel Official" "all"
bash "$VALIDATOR" "aml-s9xx-box" "" "trixie,resolute" "minimal,server" "ext4" "Recompile Custom Kernel" "none"
bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm,trixie" "application" "ext4" "Kernel Official" "proxmox-both"

if bash "$VALIDATOR" "../bad" "" "bookworm" "server" "ext4" "Kernel Official" "none"; then
  echo "Expected invalid board ID to fail" >&2; exit 1
fi
# Compatibility mismatches are allowed at validation time; the matrix resolver skips only those app rows.
bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm" "minimal,server,application" "ext4" "Kernel Official" "proxmox-official"
bash "$VALIDATOR" "aml-s9xx-box" "" "trixie" "minimal,server,application" "ext4" "Kernel Official" "proxmox-community"

PROFILE_RESOLVER="$ROOT/scripts/resolve-selected-profiles.sh"
[[ "$(bash "$PROFILE_RESOLVER" true true true true)" == "minimal,server,application,desktop" ]]
[[ "$(bash "$PROFILE_RESOLVER" false true false true)" == "server,desktop" ]]
[[ "$(bash "$PROFILE_RESOLVER" false false true false)" == "application" ]]
if bash "$PROFILE_RESOLVER" false false false false; then
  echo "Expected no selected image types to fail" >&2; exit 1
fi
if bash "$PROFILE_RESOLVER" true yes false true; then
  echo "Expected invalid checkbox boolean to fail" >&2; exit 1
fi

ALL_RESOLVER="$ROOT/scripts/resolve-app-variants.sh"
[[ "$(bash "$ALL_RESOLVER" all bookworm | sort | tr '\n' ',')" == "casaos,hermes-9router,hermes-9router-lightnvr,homeassistant,lightnvr-go2rtc,openmediavault,proxmox-community," ]]
[[ "$(bash "$ALL_RESOLVER" all trixie | sort | tr '\n' ',')" == "casaos,hermes-9router,hermes-9router-lightnvr,homeassistant,lightnvr-go2rtc,openmediavault,proxmox-official," ]]
[[ "$(bash "$ALL_RESOLVER" all bullseye)" == "homeassistant" ]]
[[ "$(bash "$ALL_RESOLVER" none resolute)" == "none" ]]

RESOLVER="$ROOT/scripts/resolve-app-variant.sh"
[[ "$(bash "$RESOLVER" proxmox-community bookworm)" == "proxmox-community" ]]
[[ -z "$(bash "$RESOLVER" proxmox-community trixie)" ]]
[[ "$(bash "$RESOLVER" proxmox-official trixie)" == "proxmox-official" ]]
[[ -z "$(bash "$RESOLVER" proxmox-official bookworm)" ]]
[[ "$(bash "$RESOLVER" proxmox-both bookworm)" == "proxmox-community" ]]
[[ "$(bash "$RESOLVER" proxmox-both trixie)" == "proxmox-official" ]]
[[ -z "$(bash "$RESOLVER" proxmox-both jammy)" ]]
[[ "$(bash "$RESOLVER" openmediavault bookworm)" == "openmediavault" ]]
[[ "$(bash "$RESOLVER" openmediavault trixie)" == "openmediavault" ]]
[[ -z "$(bash "$RESOLVER" openmediavault jammy)" ]]
[[ "$(bash "$RESOLVER" homeassistant bullseye)" == "homeassistant" ]]
[[ -z "$(bash "$RESOLVER" homeassistant forky)" ]]
[[ "$(bash "$RESOLVER" casaos trixie)" == "casaos" ]]
[[ -z "$(bash "$RESOLVER" casaos noble)" ]]
[[ "$(bash "$RESOLVER" none resolute)" == "none" ]]
if bash "$VALIDATOR" "orangepi5" "" "bookworm" "unknown" "ext4" "Kernel Official" "none"; then
  echo "Expected unknown profile to fail" >&2; exit 1
fi
if bash "$VALIDATOR" "aml-s9xx-box" "" "sid" "server" "ext4" "Kernel Official" "none"; then
  echo "Expected unsupported release to fail" >&2; exit 1
fi
# Canonical filename drops the app token accidentally appended to the parsed kernel version.
normalize_kernel_version() {
  local kernel="$1"
  local app="$2"
  app_suffix="-${app}"
  printf '%s\n' "${kernel%"$app_suffix"}"
}
[[ "$(normalize_kernel_version "6.18.57-proxmox-official" "proxmox-official")" == "6.18.57" ]]

# Canonical filename removes an application suffix appended to the parsed kernel version.
app="proxmox-official"
kernel_version="6.18.57-${app}"
asset_kernel_version="$(normalize_kernel_version "$kernel_version" "$app")"
safe_base="DBAI2K26-Armbian_26.11.0-aml-s9xx-trixie-k${asset_kernel_version}-${app}-ext4.img.xz"
[[ "$safe_base" == "DBAI2K26-Armbian_26.11.0-aml-s9xx-trixie-k6.18.57-proxmox-official-ext4.img.xz" ]]

# The bootfs archive non-empty check must use awk's exit status, not empty stdout.
bootfs_test_dir="$(mktemp -d)"
mkdir -p "$bootfs_test_dir/boot"
printf 'test-kernel-file\n' > "$bootfs_test_dir/boot/Image"
tar -czf "$bootfs_test_dir/bootfs.tar.gz" -C "$bootfs_test_dir" boot
if ! tar -tzf "$bootfs_test_dir/bootfs.tar.gz" | awk 'NF && $0 !~ /^\.\/?$/ { found=1 } END { exit !found }' >/dev/null; then
  echo "Non-empty bootfs archive was incorrectly detected as empty" >&2
  exit 1
fi
rm -rf "$bootfs_test_dir"

# Custom kernel boot archives may use either target-root paths (boot/Image)
# or boot-partition-root paths (Image); both forms must pass validation.
kernel_boot_test_dir="$(mktemp -d)"
mkdir -p "$kernel_boot_test_dir/prefixed/boot" "$kernel_boot_test_dir/rooted"
printf 'kernel-image\n' > "$kernel_boot_test_dir/prefixed/boot/Image"
printf 'kernel-image\n' > "$kernel_boot_test_dir/rooted/Image"
tar -czf "$kernel_boot_test_dir/prefixed.tar.gz" -C "$kernel_boot_test_dir/prefixed" boot
tar -czf "$kernel_boot_test_dir/rooted.tar.gz" -C "$kernel_boot_test_dir/rooted" Image
boot_archive_pattern='^(boot/.*|(\./)?(Image[^/]*|vmlinuz[^/]*|uImage|zImage|initrd[^/]*|uInitrd)(/|$))'
tar -tf "$kernel_boot_test_dir/prefixed.tar.gz" | grep -Eq "$boot_archive_pattern"
tar -tf "$kernel_boot_test_dir/rooted.tar.gz" | grep -Eq "$boot_archive_pattern"
rm -rf "$kernel_boot_test_dir"

# Accept DTB archive entries in boot/dtb, dtb/amlogic, amlogic, or archive root layouts.
dtb_test_dir="$(mktemp -d)"
mkdir -p "$dtb_test_dir/boot/dtb/amlogic" "$dtb_test_dir/dtb/amlogic" "$dtb_test_dir/amlogic" "$dtb_test_dir/root"
printf "dtb\n" > "$dtb_test_dir/boot/dtb/amlogic/boot-layout.dtb"
printf "dtb\n" > "$dtb_test_dir/dtb/amlogic/dtb-layout.dtb"
printf "dtb\n" > "$dtb_test_dir/amlogic/amlogic-layout.dtb"
printf "dtb\n" > "$dtb_test_dir/root/root-layout.dtb"
tar -czf "$dtb_test_dir/dtb-layouts.tar.gz" -C "$dtb_test_dir" boot/dtb/amlogic/boot-layout.dtb dtb/amlogic/dtb-layout.dtb amlogic/amlogic-layout.dtb root/root-layout.dtb
tar -tf "$dtb_test_dir/dtb-layouts.tar.gz" | grep -Eq "(^|/)[^/]+[.]dtb"
rm -rf "$dtb_test_dir"

# The branding extension writes the expected vendor in /etc/armbian-release.
brand_tmp="$(mktemp -d)"
trap 'rm -rf "$brand_tmp"' EXIT
mkdir -p "$brand_tmp/etc"
printf 'BOARD="aml-s9xx-box"\nVENDOR="Old name"\n' > "$brand_tmp/etc/armbian-release"
SDCARD="$brand_tmp" bash -c 'source "$1"; post_repo_customize_image__dbai_branding' _ "$ROOT/extensions/dbai-branding.sh"
grep -qx 'VENDOR="DBAI2K26"' "$brand_tmp/etc/armbian-release"
grep -qx 'VENDORPRETTYNAME="DBAI2K26"' "$brand_tmp/etc/armbian-release"

echo "All input, checkbox, naming, and application compatibility tests passed."
