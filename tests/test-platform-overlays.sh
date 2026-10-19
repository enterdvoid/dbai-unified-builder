#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

SRC="$tmp/src"
SDCARD="$tmp/image"
export SRC SDCARD
mkdir -p "$SRC/userpatches/platform" "$SDCARD/boot" "$SDCARD/usr/share/preserved"
mkdir -p "$tmp/fixtures/boot" "$tmp/fixtures/usr/bin" "$tmp/fixtures/usr/sbin"
mkdir -p "$tmp/fixtures/usr/share/alsa/cards" "$tmp/fixtures/usr/share/openvfd/conf"
mkdir -p "$tmp/fixtures/usr/share/openvfd" "$tmp/fixtures/usr/share/ophub/armbian-software"

# Exercise normalization of a u-boot archive that includes a leading boot/ folder.
printf 'boot-config\n' > "$tmp/fixtures/boot/uEnv.txt"
printf 'boot-script\n' > "$tmp/fixtures/boot/boot.scr"
tar -czf "$SRC/userpatches/platform/u-boot.tar.gz" -C "$tmp/fixtures" boot

exe_paths=(
	"bin/ampart" "bin/uuidgen"
	"sbin/armbian-apt" "sbin/armbian-ddbr" "sbin/armbian-docker" "sbin/armbian-fix"
	"sbin/armbian-install" "sbin/armbian-kernel" "sbin/armbian-openvfd" "sbin/armbian-software"
	"sbin/armbian-swap" "sbin/armbian-sync" "sbin/armbian-tf" "sbin/armbian-update" "sbin/balethirq.pl"
	"share/openvfd/vfdservice"
	"share/ophub/armbian-software/201-desktop-chinese-fonts.sh"
	"share/ophub/armbian-software/301-frps.sh"
	"share/ophub/armbian-software/302-frpc.sh"
	"share/ophub/armbian-software/command-desktop.sh"
	"share/ophub/armbian-software/command-docker.sh"
	"share/ophub/armbian-software/command-service.sh"
	"share/ophub/armbian-software/software-command.sh"
)
for rel in "${exe_paths[@]}"; do
	mkdir -p "$tmp/fixtures/usr/$(dirname "$rel")"
	printf '#!/bin/sh\nexit 0\n' > "$tmp/fixtures/usr/$rel"
done
printf 'pcm axg {}\n' > "$tmp/fixtures/usr/share/alsa/cards/axg-sound-card.conf"
printf 'panel=t95z-plus\n' > "$tmp/fixtures/usr/share/openvfd/conf/t95z-plus.conf"
printf 'example=1\n' > "$tmp/fixtures/usr/share/ophub/armbian-software/software-list.conf"
tar -czf "$SRC/userpatches/platform/usr.tar.gz" -C "$tmp/fixtures/usr" .

bash "$repo_root/scripts/validate-platform-archives.sh" "$SRC/userpatches/platform"

printf 'old default boot file\n' > "$SDCARD/boot/old-armbian-file"
printf 'preserve-existing-usr-file\n' > "$SDCARD/usr/share/preserved/keep.txt"

exit_with_error() {
	echo "ERROR: $*" >&2
	exit 1
}
display_alert() { :; }
# shellcheck source=../extensions/dbai-platform-overlays.sh
source "$repo_root/extensions/dbai-platform-overlays.sh"

extension_prepare_config__dbai_platform_overlays
pre_customize_image__100_dbai_platform_overlays

[[ -s "$SDCARD/boot/uEnv.txt" ]] || { echo "FAIL: u-boot payload was not copied to /boot" >&2; exit 1; }
[[ -s "$SDCARD/boot/boot.scr" ]] || { echo "FAIL: boot.scr was not copied to /boot" >&2; exit 1; }
[[ ! -e "$SDCARD/boot/boot/uEnv.txt" ]] || { echo "FAIL: boot/ archive prefix was not normalized" >&2; exit 1; }
[[ ! -e "$SDCARD/boot/old-armbian-file" ]] || { echo "FAIL: default /boot contents were not replaced" >&2; exit 1; }
[[ -s "$SDCARD/usr/share/preserved/keep.txt" ]] || { echo "FAIL: /usr overlay deleted existing files" >&2; exit 1; }

for rel in "${exe_paths[@]}"; do
	[[ -f "$SDCARD/usr/$rel" && -x "$SDCARD/usr/$rel" ]] || {
		echo "FAIL: expected executable mode for /usr/$rel" >&2
		exit 1
	}
done
for rel in \
	"share/alsa/cards/axg-sound-card.conf" \
	"share/openvfd/conf/t95z-plus.conf" \
	"share/ophub/armbian-software/software-list.conf"; do
	[[ -f "$SDCARD/usr/$rel" && ! -x "$SDCARD/usr/$rel" ]] || {
		echo "FAIL: configuration/data file should not be executable: /usr/$rel" >&2
		exit 1
	}
done

echo "PASS: U-Boot payload replaces /boot, usr.tar.gz overlays /usr, and the 23 designated programs/scripts are executable."
