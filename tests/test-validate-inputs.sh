#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-inputs.sh"

bash "$VALIDATOR" "orangepi5" "" "bookworm,trixie" "minimal,server" "both" "official" "none"
bash "$VALIDATOR" "custom" "my-custom-board" "bookworm" "application" "ext4" "official" "casaos"
bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm,trixie" "minimal,server" "both" "official" "casaos" "both"

if bash "$VALIDATOR" "../bad" "" "bookworm" "server" "ext4" "official" "none"; then
  echo "Expected invalid board ID to fail" >&2
  exit 1
fi
# A generic application image without bundled apps is a supported option.
bash "$VALIDATOR" "orangepi5" "" "bookworm" "application" "ext4" "official" "none"
if bash "$VALIDATOR" "orangepi5" "" "bookworm" "application" "ext4" "official" "none" "official"; then
  echo "Expected official Proxmox on Bookworm to fail" >&2
  exit 1
fi
if bash "$VALIDATOR" "aml-s9xx-box" "" "bookworm" "server" "ext4" "official" "none" "both"; then
  echo "Expected Proxmox both mode without Trixie to fail" >&2
  exit 1
fi
if bash "$VALIDATOR" "orangepi5" "" "bookworm" "unknown" "ext4" "official" "none"; then
  echo "Expected unknown profile to fail" >&2
  exit 1
fi
echo "All validator tests passed."
