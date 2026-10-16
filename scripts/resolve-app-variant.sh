#!/usr/bin/env bash
set -euo pipefail

app_profile="${1:-}"
release="${2:-}"

case "$app_profile" in
  none)
    printf 'none\n'
    ;;
  proxmox-official)
    if [[ "$release" == "trixie" ]]; then printf 'proxmox-official\n'; fi
    ;;
  proxmox-community)
    if [[ "$release" == "bookworm" ]]; then printf 'proxmox-community\n'; fi
    ;;
  proxmox-both)
    case "$release" in
      bookworm) printf 'proxmox-community\n' ;;
      trixie) printf 'proxmox-official\n' ;;
    esac
    ;;
  homeassistant)
    if [[ "$release" =~ ^(bullseye|bookworm|trixie)$ ]]; then printf 'homeassistant\n'; fi
    ;;
  openmediavault|casaos|hermes-9router|lightnvr-go2rtc|hermes-9router-lightnvr)
    if [[ "$release" =~ ^(bookworm|trixie)$ ]]; then printf '%s\n' "$app_profile"; fi
    ;;
  *)
    echo "Unsupported application profile: $app_profile" >&2
    exit 2
    ;;
esac

# Empty stdout with exit status 0 means this application is not compatible
# with the requested release, so the workflow can skip just this matrix row.
exit 0
