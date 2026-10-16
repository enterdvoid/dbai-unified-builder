#!/usr/bin/env bash
set -euo pipefail

board="${1:-}"
custom_board="${2:-}"
releases="${3:-}"
profiles="${4:-}"
filesystem="${5:-}"
kernel_mode="${6:-official}"
app_profile="${7:-none}"
proxmox_mode="${8:-none}"

if [[ "$board" == "custom" ]]; then
  board="$custom_board"
fi
[[ "$board" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid board ID: $board" >&2; exit 2; }
[[ -n "$releases" && -n "$profiles" ]] || { echo "Releases and profiles cannot be empty" >&2; exit 2; }
[[ "$filesystem" =~ ^(ext4|btrfs|both)$ ]] || { echo "Filesystem must be ext4, btrfs, or both" >&2; exit 2; }
[[ "$kernel_mode" =~ ^(official|custom-four-part)$ ]] || { echo "Invalid kernel mode" >&2; exit 2; }

IFS=',' read -r -a release_list <<< "$releases"
IFS=',' read -r -a profile_list <<< "$profiles"
for item in "${release_list[@]}"; do
  item="$(xargs <<< "$item")"
  [[ "$item" =~ ^(bullseye|bookworm|trixie|forky)$ ]] || { echo "Unsupported release token: $item" >&2; exit 2; }
done
for item in "${profile_list[@]}"; do
  item="$(xargs <<< "$item")"
  [[ "$item" =~ ^(minimal|server|application|desktop)$ ]] || { echo "Unsupported profile token: $item" >&2; exit 2; }
done
profiles_compact="${profiles//[[:space:]]/}"
[[ "$app_profile" =~ ^(none|homeassistant|openmediavault|casaos|hermes-9router|lightnvr-go2rtc|hermes-9router-lightnvr)$ ]] || { echo "Unsupported app profile: $app_profile" >&2; exit 2; }
[[ "$proxmox_mode" =~ ^(none|official|community|both)$ ]] || { echo "Unsupported Proxmox mode: $proxmox_mode" >&2; exit 2; }
releases_compact="${releases//[[:space:]]/}"
if [[ "$proxmox_mode" != "none" ]]; then
  [[ ",$profiles_compact," == *",application,"* ]] || { echo "Proxmox mode requires the application profile" >&2; exit 2; }
  [[ "$app_profile" == "none" ]] || { echo "Use app_profile=none when Proxmox mode is enabled" >&2; exit 2; }
  case "$proxmox_mode" in
    official) [[ "$releases_compact" == "trixie" ]] || { echo "Proxmox official mode requires releases=trixie" >&2; exit 2; } ;;
    community) [[ "$releases_compact" == "bookworm" ]] || { echo "Proxmox community mode requires releases=bookworm" >&2; exit 2; } ;;
    both)
      [[ "$releases_compact" == "bookworm,trixie" || "$releases_compact" == "trixie,bookworm" ]] || { echo "Proxmox mode both requires releases=bookworm,trixie" >&2; exit 2; }
      ;;
  esac
fi
if [[ ",$profiles_compact," == *",application,"* && "$proxmox_mode" == "none" && "$app_profile" == "none" ]]; then
  echo "The application profile requires an app_profile selection or Proxmox mode." >&2
  exit 2
fi
if [[ ",$profiles_compact," == *",application,"* ]]; then
  for item in "${release_list[@]}"; do
    item="$(xargs <<< "$item")"
    case "$app_profile" in
      homeassistant)
        [[ "$item" =~ ^(bullseye|bookworm|trixie)$ ]] || { echo "Home Assistant application profile does not support $item" >&2; exit 2; }
        ;;
      openmediavault|casaos|hermes-9router|lightnvr-go2rtc|hermes-9router-lightnvr)
        [[ "$item" =~ ^(bookworm|trixie)$ ]] || { echo "$app_profile application profile currently supports bookworm/trixie only; got $item" >&2; exit 2; }
        ;;
    esac
  done
fi
echo "Validated: board=$board releases=$releases profiles=$profiles filesystem=$filesystem kernel=$kernel_mode app=$app_profile"
