#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../extensions/dbai-custom-kernel.sh
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
