#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-inputs.sh"

bash "$VALIDATOR" "orangepi5" "" "bookworm,trixie" "minimal,server" "both" "official" "none"
bash "$VALIDATOR" "custom" "my-custom-board" "bookworm" "application" "ext4" "official" "casaos"

if bash "$VALIDATOR" "../bad" "" "bookworm" "server" "ext4" "official" "none"; then
  echo "Expected invalid board ID to fail" >&2
  exit 1
fi
if bash "$VALIDATOR" "orangepi5" "" "bookworm" "application" "ext4" "official" "none"; then
  echo "Expected application profile without an app to fail" >&2
  exit 1
fi
if bash "$VALIDATOR" "orangepi5" "" "bookworm" "unknown" "ext4" "official" "none"; then
  echo "Expected unknown profile to fail" >&2
  exit 1
fi
echo "All validator tests passed."
