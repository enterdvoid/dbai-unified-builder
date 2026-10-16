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
