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


# Exercise the production staging/installation helper against both supported
# module archive layouts. The image root must never receive /<kernel-release>.
for layout in release-root target-root; do
  input_root="$tmp/${layout}-input"
  target_root="$tmp/${layout}-image"
  release="6.1.66-DBAI"
  if [[ "$layout" == "release-root" ]]; then
    module_tree="$input_root/$release"
  else
    module_tree="$input_root/lib/modules/$release"
  fi
  mkdir -p "$module_tree/kernel/drivers/test"
  printf 'test module dependency map\n' > "$module_tree/modules.dep"
  printf 'test kernel module\n' > "$module_tree/kernel/drivers/test/test.ko"
  mkdir -p "$target_root"
  tar -czf "$tmp/${layout}-modules.tar.gz" -C "$input_root" .
  if ! dbai_install_kernel_modules_archive "$tmp/${layout}-modules.tar.gz" "$layout" "$release" "$tmp/${layout}-stage" "$target_root"; then
    echo "FAIL: ${layout} module archive could not be staged and installed" >&2
    exit 1
  fi
  [[ -f "$target_root/lib/modules/$release/modules.dep" ]] || { echo "FAIL: ${layout} modules.dep missing at canonical destination" >&2; exit 1; }
  [[ -f "$target_root/lib/modules/$release/kernel/drivers/test/test.ko" ]] || { echo "FAIL: ${layout} .ko file missing at canonical destination" >&2; exit 1; }
  [[ ! -e "$target_root/$release" && ! -L "$target_root/$release" ]] || { echo "FAIL: ${layout} archive created a root-level /$release directory" >&2; exit 1; }
  [[ ! -e "$tmp/${layout}-stage" ]] || { echo "FAIL: ${layout} staging directory was not cleaned up" >&2; exit 1; }
  echo "PASS: ${layout} module archive installs only into /lib/modules/$release"
done

# A target-root archive containing a second kernel release must fail closed
# before it can contaminate the image.
bad_root="$tmp/multi-release-input"
mkdir -p "$bad_root/lib/modules/6.1.66-DBAI/kernel" "$bad_root/lib/modules/6.1.66-DBAI" \
  "$bad_root/lib/modules/6.18.57-current-meson64/kernel"
printf 'dep\n' > "$bad_root/lib/modules/6.1.66-DBAI/modules.dep"
printf 'module\n' > "$bad_root/lib/modules/6.1.66-DBAI/kernel/test.ko"
printf 'dep\n' > "$bad_root/lib/modules/6.18.57-current-meson64/modules.dep"
printf 'module\n' > "$bad_root/lib/modules/6.18.57-current-meson64/kernel/other.ko"
tar -czf "$tmp/multi-release-modules.tar.gz" -C "$bad_root" .
bad_target="$tmp/multi-release-image"
mkdir -p "$bad_target"
if dbai_install_kernel_modules_archive "$tmp/multi-release-modules.tar.gz" target-root "6.1.66-DBAI" "$tmp/multi-release-stage" "$bad_target" >/dev/null 2>&1; then
  echo "FAIL: multi-release module archive should have been rejected" >&2
  exit 1
fi
[[ ! -e "$bad_target/lib/modules/6.1.66-DBAI" && ! -e "$bad_target/6.1.66-DBAI" ]] || {
  echo "FAIL: invalid module archive changed the target image" >&2
  exit 1
}
echo "PASS: multi-release module archive is rejected before target-image mutation"


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
  "$fixture/usr/lib/modules/6.18.57-current-meson64" "$fixture/usr/lib/linux-image-6.18.57-current-meson64" \
  "$fixture/usr/src/linux-uapi-headers-6.1.66-DBAI" "$fixture/usr/src/linux-headers-6.18.57-current-meson64" \
  "$fixture/6.1.66-DBAI"
touch "$fixture/lib/modules/6.1.66-DBAI/modules.dep"
touch "$fixture/lib/modules/6.18.57-current-meson64/modules.dep"
touch "$fixture/usr/lib/modules/6.18.57-current-meson64/modules.dep"
touch "$fixture/usr/src/linux-uapi-headers-6.1.66-DBAI/include-placeholder"
touch "$fixture/usr/src/linux-headers-6.18.57-current-meson64/Makefile"
# Armbian's finalizer must finish generating initramfs before this hook deletes
# the distro module tree that IMAGE_INSTALLED_KERNEL_VERSION still references.
display_alert() { :; }
exit_with_error() { echo "ERROR: $*" >&2; return 1; }
# Stub image-assembly-only steps; this unit fixture exercises the kernel-tree cleanup hook.
dbai_purge_installed_distro_kernel_packages() { :; }
dbai_restore_custom_kernel_boot_payload() { :; }
dbai_prune_noncustom_boot_artifacts() { :; }
dbai_generate_custom_kernel_initramfs() { :; }
dbai_verify_custom_kernel_boot_payload() { :; }
MOUNT="$fixture"
DBAI_KERNEL_MODE="Custom Kernel"
DBAI_CUSTOM_KERNEL_RELEASE="6.1.66-DBAI"
if ! pre_umount_final_image__dbai_prune_noncustom_kernel_artifacts; then
  echo "FAIL: final-image custom-kernel cleanup hook returned failure" >&2
  exit 1
fi
[[ -f "$fixture/lib/modules/6.1.66-DBAI/modules.dep" ]] || { echo "FAIL: custom modules were removed" >&2; exit 1; }
[[ ! -e "$fixture/lib/modules/6.18.57-current-meson64" ]] || { echo "FAIL: official modules remain" >&2; exit 1; }
[[ ! -e "$fixture/usr/lib/modules/6.18.57-current-meson64" ]] || { echo "FAIL: official modules in /usr/lib/modules remain" >&2; exit 1; }
[[ ! -e "$fixture/usr/lib/linux-image-6.18.57-current-meson64" ]] || { echo "FAIL: official linux-image payload remains" >&2; exit 1; }
[[ -d "$fixture/usr/src/linux-uapi-headers-6.1.66-DBAI" ]] || { echo "FAIL: custom UAPI headers were removed" >&2; exit 1; }
[[ ! -e "$fixture/usr/src/linux-headers-6.18.57-current-meson64" ]] || { echo "FAIL: official kernel headers remain" >&2; exit 1; }
[[ ! -e "$fixture/6.1.66-DBAI" ]] || { echo "FAIL: empty root-level release directory remains" >&2; exit 1; }
echo "PASS: custom-kernel cleanup removes official residue and empty root-level release directory"

mkdir -p "$fixture/6.1.66-DBAI"
touch "$fixture/6.1.66-DBAI/unexpected-file"
if dbai_prune_noncustom_kernel_artifacts "$fixture" "6.1.66-DBAI" >/dev/null 2>&1; then
  echo "FAIL: non-empty root-level release directory should be rejected" >&2
  exit 1
fi
echo "PASS: non-empty root-level release directory is rejected"
