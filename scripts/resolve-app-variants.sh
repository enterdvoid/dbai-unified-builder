#!/usr/bin/env bash
set -euo pipefail

selection="${1:-none}"
release="${2:-}"
resolver="$(cd "$(dirname "$0")" && pwd)/resolve-app-variant.sh"

if [[ "$selection" == "all" ]]; then
  # Enumerate concrete application builds. Proxmox Both is represented by
  # Community on Bookworm and Official on Trixie to avoid duplicate images.
  candidates=(homeassistant openmediavault casaos hermes-9router lightnvr-go2rtc hermes-9router-lightnvr proxmox-community proxmox-official)
else
  candidates=("$selection")
fi

declare -A seen=()
for candidate in "${candidates[@]}"; do
  resolved="$(bash "$resolver" "$candidate" "$release")"
  [[ -n "$resolved" ]] || continue
  if [[ -z "${seen[$resolved]+x}" ]]; then
    printf '%s\n' "$resolved"
    seen["$resolved"]=1
  fi
done
