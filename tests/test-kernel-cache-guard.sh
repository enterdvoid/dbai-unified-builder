#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
source_file="$tmp/artifact-kernel.sh"

cat > "$source_file" <<'FIXTURE'
function artifact_kernel_build_from_sources() {
  compile_kernel
}
FIXTURE

python3 "$repo_root/scripts/guard-kernel-cache-only.py" "$source_file" "Kernel Official"
grep -q 'DBAI_KERNEL_OFFICIAL_CACHE_ONLY_GUARD' "$source_file"
grep -q 'no reusable official kernel artifact was found' "$source_file"

before="$(sha256sum "$source_file" | awk '{print $1}')"
python3 "$repo_root/scripts/guard-kernel-cache-only.py" "$source_file" "Kernel Official"
after="$(sha256sum "$source_file" | awk '{print $1}')"
[[ "$before" == "$after" ]]

cat > "$tmp/custom-kernel.sh" <<'FIXTURE'
function artifact_kernel_build_from_sources() {
  compile_kernel
}
FIXTURE
python3 "$repo_root/scripts/guard-kernel-cache-only.py" "$tmp/custom-kernel.sh" "Custom Kernel"
grep -q 'DBAI_KERNEL_OFFICIAL_CACHE_ONLY_GUARD' "$tmp/custom-kernel.sh"
grep -q 'compiling kernel from source in Custom Kernel mode is prohibited' "$tmp/custom-kernel.sh"

cat > "$tmp/no-hook.sh" <<'FIXTURE'
function another_artifact() {
  :
}
FIXTURE
if python3 "$repo_root/scripts/guard-kernel-cache-only.py" "$tmp/no-hook.sh" "Kernel Official"; then
  echo "Expected a missing hook to fail closed" >&2
  exit 1
fi

cat > "$tmp/non-official.sh" <<'FIXTURE'
function another_artifact() {
  :
}
FIXTURE
python3 "$repo_root/scripts/guard-kernel-cache-only.py" "$tmp/non-official.sh" "Recompile Kernel Official"
if grep -q 'DBAI_KERNEL_OFFICIAL_CACHE_ONLY_GUARD' "$tmp/non-official.sh"; then
  echo "Non-official kernel mode was unexpectedly patched" >&2
  exit 1
fi

echo "Kernel cache guard tests passed."
