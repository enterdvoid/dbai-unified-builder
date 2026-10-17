#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/dbai-build.yml"
[[ -s "$workflow" ]] || { echo "FAIL: missing $workflow" >&2; exit 1; }

grep -Fq 'DBAI_IMAGE_VERSION: "26.11.0"' "$workflow" || {
  echo "FAIL: workflow does not pin the stable DBAI image version." >&2
  exit 1
}
grep -Fq 'REVISION="$DBAI_IMAGE_VERSION" IMAGE_VERSION="$DBAI_IMAGE_VERSION"' "$workflow" || {
  echo "FAIL: compile command must override upstream VERSION/-trunk metadata." >&2
  exit 1
}
grep -Fq 'DESKTOP_ENVIRONMENT_ARG=("DESKTOP_ENVIRONMENT=xfce")' "$workflow" || {
  echo "FAIL: Desktop profile does not select a non-interactive desktop environment." >&2
  exit 1
}
grep -Fq '"${DESKTOP_ENVIRONMENT_ARG[@]}"' "$workflow" || {
  echo "FAIL: compile command does not pass Desktop environment arguments." >&2
  exit 1
}

echo "PASS: stable DBAI image version overrides upstream -trunk metadata."
echo "PASS: Desktop profile selects XFCE without an interactive dialog."
