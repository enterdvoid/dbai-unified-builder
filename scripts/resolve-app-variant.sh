#!/usr/bin/env bash
set -euo pipefail

app_profile="${1:-}"
release="${2:-}"

case "$app_profile" in
  none)
    printf 'none\n'
    ;;
  proxmox-official)
    [[ "$release" == "trixie" ]] && printf 'proxmox-official\n'
    ;;
  proxmox-community)
    [[ "$release" == "bookworm" ]] && printf 'proxmox-community\n'
    ;;
  proxmox-both)
    case "$release" in
      bookworm) printf 'proxmox-community\n' ;;
      trixie) printf 'proxmox-official\n' ;;
    esac
    ;;
  homeassistant)
    [[ "$release" =~ ^(bullseye|bookworm|trixie)$ ]] && printf 'homeassistant\n'
    ;;
  openmediavault|casaos|hermes-9router|lightnvr-go2rtc|hermes-9router-lightnvr)
    [[ "$release" =~ ^(bookworm|trixie)$ ]] && printf '%s\n' "$app_profile"
    ;;
  *)
    echo "Unsupported application profile: $app_profile" >&2
    exit 2
    ;;
esac
