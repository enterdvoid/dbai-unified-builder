#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Keep this exact GNU df option combination covered: -P cannot be combined
# with --output, so free space must be queried with -B1 --output=avail.
available_bytes="$(df -B1 --output=avail "$tmp" | awk 'NR==2 {print $1}')"
[[ "$available_bytes" =~ ^[0-9]+$ ]] || {
  echo "FAIL: unable to parse available disk bytes from df output" >&2
  exit 1
}
(( available_bytes > 0 )) || {
  echo "FAIL: df reported no available bytes for the temporary directory" >&2
  exit 1
}
echo "PASS: df available-space probe parsed $available_bytes bytes"
