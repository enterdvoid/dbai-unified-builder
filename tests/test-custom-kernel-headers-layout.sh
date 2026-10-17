#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${repo_root}/extensions/dbai-custom-kernel.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

assert_layout() {
  local name="$1" expected="$2" listing="$3" actual
  if ! actual="$(dbai_detect_kernel_headers_layout "${listing}")"; then
    echo "FAIL: ${name}: detector rejected a valid fixture" >&2
    exit 1
  fi
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${name}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
  echo "PASS: ${name} -> ${actual}"
}

cat > "${tmp}/target-root.txt" <<'EOF'
./
./usr/
./usr/src/
./usr/src/linux-headers-6.1.66-DBAI/
./usr/src/linux-headers-6.1.66-DBAI/Makefile
EOF
assert_layout "target-root headers" "target-root" "${tmp}/target-root.txt"

cat > "${tmp}/header-root.txt" <<'EOF'
./
./Makefile
./include/
./include/linux/
./include/linux/module.h
EOF
assert_layout "rooted build headers" "header-root" "${tmp}/header-root.txt"

cat > "${tmp}/uapi-root.txt" <<'EOF'
./
./include/
./include/linux/
./include/linux/types.h
./include/scsi/
./include/scsi/scsi_bsg_ufs.h
EOF
assert_layout "exported UAPI only" "uapi-root" "${tmp}/uapi-root.txt"

cat > "${tmp}/modules-target-root.txt" <<'EOF'
./
./lib/
./lib/modules/6.1.66-DBAI/
./lib/modules/6.1.66-DBAI/modules.dep
EOF
actual="$(dbai_detect_kernel_modules_release "${tmp}/modules-target-root.txt")"
[[ "${actual}" == "6.1.66-DBAI" ]] || { echo "FAIL: target-root modules release expected 6.1.66-DBAI, got '${actual}'" >&2; exit 1; }
echo "PASS: target-root modules release -> ${actual}"

cat > "${tmp}/modules-release-root.txt" <<'EOF'
./
./6.1.66-DBAI/
./6.1.66-DBAI/modules.dep
./6.1.66-DBAI/kernel/
EOF
actual="$(dbai_detect_kernel_modules_release "${tmp}/modules-release-root.txt")"
[[ "${actual}" == "6.1.66-DBAI" ]] || { echo "FAIL: release-root modules release expected 6.1.66-DBAI, got '${actual}'" >&2; exit 1; }
echo "PASS: release-root modules release -> ${actual}"

cat > "${tmp}/modules-invalid.txt" <<'EOF'
./
./not-a-kernel-tree/
./not-a-kernel-tree/anything
EOF
if dbai_detect_kernel_modules_release "${tmp}/modules-invalid.txt" >/dev/null; then
  echo "FAIL: invalid modules tree was incorrectly accepted" >&2
  exit 1
fi
echo "PASS: invalid modules tree is rejected"

cat > "${tmp}/invalid.txt" <<'EOF'
./
./include/
./scripts/
./include/linux/types.h
EOF
if dbai_detect_kernel_headers_layout "${tmp}/invalid.txt" >/dev/null; then
  echo "FAIL: mixed incomplete tree was incorrectly accepted" >&2
  exit 1
fi
echo "PASS: incomplete mixed tree is rejected"

# Test cleanup of the specific kernel residue reported for Custom Kernel mode.
fixture="${tmp}/image-root"
mkdir -p "$fixture/lib/modules/6.1.66-DBAI" "$fixture/lib/modules/6.18.57-current-meson64" \
  "$fixture/usr/lib/linux-image-6.18.57-current-meson64" "$fixture/6.1.66-DBAI"
touch "$fixture/lib/modules/6.1.66-DBAI/modules.dep"
touch "$fixture/lib/modules/6.18.57-current-meson64/modules.dep"
if ! dbai_prune_noncustom_kernel_artifacts "$fixture" "6.1.66-DBAI"; then
  echo "FAIL: custom-kernel artifact cleanup returned failure" >&2
  exit 1
fi
[[ -f "$fixture/lib/modules/6.1.66-DBAI/modules.dep" ]] || { echo "FAIL: custom modules were removed" >&2; exit 1; }
[[ ! -e "$fixture/lib/modules/6.18.57-current-meson64" ]] || { echo "FAIL: official modules remain" >&2; exit 1; }
[[ ! -e "$fixture/usr/lib/linux-image-6.18.57-current-meson64" ]] || { echo "FAIL: official linux-image payload remains" >&2; exit 1; }
[[ ! -e "$fixture/6.1.66-DBAI" ]] || { echo "FAIL: empty root-level release directory remains" >&2; exit 1; }
echo "PASS: custom-kernel cleanup removes official residue and empty root-level release directory"

mkdir -p "$fixture/6.1.66-DBAI"
touch "$fixture/6.1.66-DBAI/unexpected-file"
if dbai_prune_noncustom_kernel_artifacts "$fixture" "6.1.66-DBAI" >/dev/null 2>&1; then
  echo "FAIL: non-empty root-level release directory should be rejected" >&2
  exit 1
fi
echo "PASS: non-empty root-level release directory is rejected"
