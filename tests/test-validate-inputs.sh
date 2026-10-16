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
bash "$VALIDATOR" "aml-s9xx-box" "" "trixie,resolute" "minimal,server" "ext4" "Recompile Custom Kernel" "none"
bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm,trixie" "application" "ext4" "Kernel Official" "proxmox-both"

if bash "$VALIDATOR" "../bad" "" "bookworm" "server" "ext4" "Kernel Official" "none"; then
  echo "Expected invalid board ID to fail" >&2; exit 1
fi
if bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm" "application" "ext4" "Kernel Official" "proxmox-official"; then
  echo "Expected Proxmox Official without Trixie to fail" >&2; exit 1
fi
if bash "$VALIDATOR" "aml-s9xx-box" "" "trixie" "application" "ext4" "Kernel Official" "proxmox-community"; then
  echo "Expected Proxmox Community without Bookworm to fail" >&2; exit 1
fi
if bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm" "application" "ext4" "Kernel Official" "proxmox-both"; then
  echo "Expected Proxmox Both without both releases to fail" >&2; exit 1
fi
if bash "$VALIDATOR" "orangepi5" "" "bookworm" "unknown" "ext4" "Kernel Official" "none"; then
  echo "Expected unknown profile to fail" >&2; exit 1
fi
if bash "$VALIDATOR" "aml-s9xx-box" "" "sid" "server" "ext4" "Kernel Official" "none"; then
  echo "Expected unsupported release to fail" >&2; exit 1
fi
echo "All validator tests passed."
