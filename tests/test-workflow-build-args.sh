#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/dbai-build.yml"
[[ -s "$workflow" ]] || { echo "FAIL: missing $workflow" >&2; exit 1; }

grep -Fq 'DBAI_IMAGE_VERSION: "26.11.0"' "$workflow" || {
  echo "FAIL: workflow does not pin the stable DBAI image version." >&2
  exit 1
}
# shellcheck disable=SC2016 # Intentionally match literal variable references in the workflow YAML.
stable_version_args='REVISION="$DBAI_IMAGE_VERSION" IMAGE_VERSION="$DBAI_IMAGE_VERSION"'
grep -Fq "$stable_version_args" "$workflow" || {
  echo "FAIL: compile command must override upstream VERSION/-trunk metadata." >&2
  exit 1
}
grep -Fq "DESKTOP_ENVIRONMENT_ARG=(\"DESKTOP_ENVIRONMENT=\$DESKTOP_ENVIRONMENT\")" "$workflow" || {
  echo "FAIL: Desktop profile must pass the selected environment explicitly." >&2
  exit 1
}
grep -Fq "DESKTOP_TIER_ARG=(\"DESKTOP_TIER=\$DESKTOP_TIER\")" "$workflow" || {
  echo "FAIL: Desktop profile must pass the selected package tier explicitly." >&2
  exit 1
}
grep -Fq "\"\${DESKTOP_ENVIRONMENT_ARG[@]}\"" "$workflow" || {
  echo "FAIL: compile command does not pass the selected desktop environment." >&2
  exit 1
}
grep -Fq "\"\${DESKTOP_TIER_ARG[@]}\"" "$workflow" || {
  echo "FAIL: compile command does not pass the selected desktop tier." >&2
  exit 1
}
# shellcheck disable=SC2016 # Match the literal Bash variable references embedded in YAML.
grep -Fq 'scripts/resolve-desktop-environments.sh "$DESKTOP_ENVIRONMENT_INPUT" "$release"' "$workflow" || {
  echo "FAIL: build matrix does not resolve release-compatible Desktop environments." >&2
  exit 1
}
grep -Fq 'DESKTOP_OPENBOX=yes' "$workflow" || {
  echo "FAIL: Openbox must avoid Armbian's standard interactive desktop path." >&2
  exit 1
}
grep -Fq 'EXTENSIONS+=(dbai-openbox)' "$workflow" || {
  echo "FAIL: Openbox profile does not enable the standalone Openbox extension." >&2
  exit 1
}
grep -Fq 'asset_kernel_version="${asset_kernel_version%-openbox}"' "$workflow" || {
  echo "FAIL: Openbox suffix must not be duplicated in the canonical firmware filename." >&2
  exit 1
}
grep -Fq 'matrix.desktop_environment' "$workflow" || {
  echo "FAIL: Desktop environment must be included in the build job identity." >&2
  exit 1
}
grep -Fq 'planned_count > 256' "$workflow" || {
  echo "FAIL: expanded Desktop matrix must be guarded against GitHub's 256-job limit." >&2
  exit 1
}

echo "PASS: stable DBAI image version overrides upstream -trunk metadata."
echo "PASS: all Desktop environments and tiers are explicitly non-interactive."
echo "PASS: Openbox is dispatched through the standalone extension."
