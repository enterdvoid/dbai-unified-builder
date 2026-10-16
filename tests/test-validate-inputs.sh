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
echo "All input, checkbox, and application compatibility tests passed."
