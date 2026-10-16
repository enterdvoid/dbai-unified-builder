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
[[ "$kernel_mode" =~ ^(official|recompile|custom-four-part)$ ]] || { echo "Invalid kernel mode" >&2; exit 2; }

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
  case "$proxmox_mode" in
    official) [[ ",$releases_compact," == *",trixie,"* ]] || { echo "Proxmox official mode requires trixie in releases" >&2; exit 2; } ;;
    community) [[ ",$releases_compact," == *",bookworm,"* ]] || { echo "Proxmox community mode requires bookworm in releases" >&2; exit 2; } ;;
    both)
      [[ ",$releases_compact," == *",bookworm,"* && ",$releases_compact," == *",trixie,"* ]] || { echo "Proxmox mode both requires bookworm and trixie in releases" >&2; exit 2; }
      ;;
  esac
fi
# app_profile=none intentionally builds a generic application image without bundling an app.
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
