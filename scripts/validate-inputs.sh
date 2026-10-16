#!/usr/bin/env bash
set -euo pipefail

board="${1:-}"
custom_board="${2:-}"
releases="${3:-}"
profiles="${4:-}"
filesystem="${5:-}"
kernel_mode="${6:-Kernel Official}"
app_profile="${7:-none}"

if [[ "$board" == "custom" ]]; then board="$custom_board"; fi
[[ "$board" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid board ID: $board" >&2; exit 2; }
[[ -n "$releases" && -n "$profiles" ]] || { echo "Releases and profiles cannot be empty" >&2; exit 2; }
[[ "$filesystem" =~ ^(ext4|btrfs|both)$ ]] || { echo "Filesystem must be ext4, btrfs, or both" >&2; exit 2; }
[[ "$kernel_mode" =~ ^(Kernel\ Official|Recompile\ Kernel\ Official|Custom\ Kernel|Recompile\ Custom\ Kernel)$ ]] || { echo "Invalid kernel mode: $kernel_mode" >&2; exit 2; }

IFS=',' read -r -a release_list <<< "$releases"
IFS=',' read -r -a profile_list <<< "$profiles"
for item in "${release_list[@]}"; do
  item="$(xargs <<< "$item")"
  [[ "$item" =~ ^(bullseye|bookworm|trixie|forky|jammy|noble|resolute)$ ]] || { echo "Unsupported Armbian release token: $item" >&2; exit 2; }
done
for item in "${profile_list[@]}"; do
  item="$(xargs <<< "$item")"
  [[ "$item" =~ ^(minimal|server|application|desktop)$ ]] || { echo "Unsupported profile token: $item" >&2; exit 2; }
done
[[ "$app_profile" =~ ^(none|homeassistant|openmediavault|casaos|hermes-9router|lightnvr-go2rtc|hermes-9router-lightnvr|proxmox-official|proxmox-community|proxmox-both)$ ]] || { echo "Unsupported application profile: $app_profile" >&2; exit 2; }

# Release compatibility is handled per matrix row by resolve-app-variant.sh.
# This deliberately allows mixed OS batches: incompatible Application rows are skipped,
# while Minimal/Server/Desktop jobs for those releases still run.
echo "Validated: board=$board releases=$releases profiles=$profiles filesystem=$filesystem kernel=$kernel_mode app=$app_profile"
