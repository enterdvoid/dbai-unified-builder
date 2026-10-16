#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-inputs.sh"

bash "$VALIDATOR" "orangepi5" "" "bookworm,trixie" "minimal,server" "both" "Kernel Official" "none"
bash "$VALIDATOR" "aml-s9xx-box" "" "trixie" "server" "ext4" "Recompile Kernel Official" "none"
bash "$VALIDATOR" "custom" "my-custom-board" "bookworm" "application" "ext4" "Kernel Official" "casaos"
bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm,trixie" "minimal,server" "both" "Kernel Official" "casaos" "both"

if bash "$VALIDATOR" "../bad" "" "bookworm" "server" "ext4" "Kernel Official" "none"; then
  echo "Expected invalid board ID to fail" >&2
  exit 1
fi
# A generic application image without bundled apps is a supported option.
bash "$VALIDATOR" "orangepi5" "" "bookworm" "application" "ext4" "Kernel Official" "none"
if bash "$VALIDATOR" "orangepi5" "" "bookworm" "application" "ext4" "Kernel Official" "none" "Kernel Official"; then
  echo "Expected official Proxmox on Bookworm to fail" >&2
  exit 1
fi
if bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm" "server" "ext4" "Kernel Official" "none" "both"; then
  echo "Expected Proxmox both mode without Trixie to fail" >&2
  exit 1
fi
if bash "$VALIDATOR" "orangepi5" "" "bookworm" "unknown" "ext4" "Kernel Official" "none"; then
  echo "Expected unknown profile to fail" >&2
  exit 1
fi
bash "$VALIDATOR" "aml-s9xx-box" "" "trixie" "server" "ext4" "Custom Kernel" "none"
bash "$VALIDATOR" "aml-s9xx-box" "" "trixie" "server" "ext4" "Recompile Custom Kernel" "none"
echo "All validator tests passed."
