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
profiles_compact="${profiles//[[:space:]]/}"
releases_compact="${releases//[[:space:]]/}"
[[ "$app_profile" =~ ^(none|homeassistant|openmediavault|casaos|hermes-9router|lightnvr-go2rtc|hermes-9router-lightnvr|proxmox-official|proxmox-community|proxmox-both)$ ]] || { echo "Unsupported application profile: $app_profile" >&2; exit 2; }

if [[ ",$profiles_compact," == *",application,"* ]]; then
  case "$app_profile" in
    proxmox-official)
      [[ ",$releases_compact," == *",trixie,"* ]] || { echo "Proxmox Official is an application variant for Trixie; include trixie in the selected releases" >&2; exit 2; }
      ;;
    proxmox-community)
      [[ ",$releases_compact," == *",bookworm,"* ]] || { echo "Proxmox Community is an application variant for Bookworm; include bookworm in the selected releases" >&2; exit 2; }
      ;;
    proxmox-both)
      [[ ",$releases_compact," == *",bookworm,"* && ",$releases_compact," == *",trixie,"* ]] || { echo "Proxmox Both requires both bookworm and trixie in selected releases" >&2; exit 2; }
      ;;
    homeassistant)
      [[ ",$releases_compact," == *",bullseye,"* || ",$releases_compact," == *",bookworm,"* || ",$releases_compact," == *",trixie,"* ]] || { echo "Home Assistant requires at least one compatible release: bullseye, bookworm, or trixie" >&2; exit 2; }
      ;;
    openmediavault|casaos|hermes-9router|lightnvr-go2rtc|hermes-9router-lightnvr)
      [[ ",$releases_compact," == *",bookworm,"* || ",$releases_compact," == *",trixie,"* ]] || { echo "$app_profile requires at least one compatible release: bookworm or trixie" >&2; exit 2; }
      ;;
  esac
fi

echo "Validated: board=$board releases=$releases profiles=$profiles filesystem=$filesystem kernel=$kernel_mode app=$app_profile"
