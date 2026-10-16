#!/usr/bin/env bash
set -euo pipefail

board="${1:-}"
custom_board="${2:-}"
releases="${3:-}"
profiles="${4:-}"
filesystem="${5:-}"
kernel_mode="${6:-official}"
app_profile="${7:-none}"

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
if [[ ",$profiles_compact," == *",application,"* && "$app_profile" == "none" ]]; then
  echo "The application profile requires an app_profile selection." >&2
  exit 2
fi
[[ "$app_profile" =~ ^(none|homeassistant|openmediavault|casaos)$ ]] || { echo "Unsupported app profile: $app_profile" >&2; exit 2; }
echo "Validated: board=$board releases=$releases profiles=$profiles filesystem=$filesystem kernel=$kernel_mode app=$app_profile"
