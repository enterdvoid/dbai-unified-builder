#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${repo_root}/extensions/dbai-custom-kernel.sh"

bundle_url="${DBAI_TEST_KERNEL_BUNDLE_URL:-https://github.com/armarchindo/kernel/releases/download/kernel_dbai/6.1.66-DBAI.tar.gz}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

echo "Downloading published custom-kernel bundle for layout integration test."
curl --fail --location --silent --show-error --retry 3 --retry-delay 2 "${bundle_url}" --output "${tmp}/bundle.tar"
tar -tf "${tmp}/bundle.tar" > "${tmp}/outer-list.txt"
if ! awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }' "${tmp}/outer-list.txt"; then
  echo "FAIL: unsafe path in published bundle" >&2
  exit 1
fi
mkdir "${tmp}/bundle"
tar --no-same-owner --no-same-permissions -xf "${tmp}/bundle.tar" -C "${tmp}/bundle"

mapfile -t module_archives < <(find "${tmp}/bundle" -type f \( -name 'modules-*.tar.gz' -o -name 'modules-*.tar.xz' \) -print)
if [[ "${#module_archives[@]}" -ne 1 ]]; then
  echo "FAIL: expected exactly one modules-*.tar.gz/.tar.xz archive, got ${#module_archives[@]}" >&2
  find "${tmp}/bundle" -type f -print | sort >&2
  exit 1
fi
tar -tf "${module_archives[0]}" > "${tmp}/modules-list.txt"
if ! awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }' "${tmp}/modules-list.txt"; then
  echo "FAIL: unsafe path in module archive" >&2
  exit 1
fi
module_release="$(dbai_detect_kernel_modules_release "${tmp}/modules-list.txt")" || {
  echo "FAIL: cannot determine release from the actual published modules archive" >&2
  sed -n '1,80p' "${tmp}/modules-list.txt" >&2
  exit 1
}
echo "Detected actual kernel module release from published bundle: ${module_release}"

mapfile -t boot_archives < <(find "${tmp}/bundle" -type f \( -name 'boot-*.tar.gz' -o -name 'boot-*.tar.xz' \) -print)
if [[ "${#boot_archives[@]}" -ne 1 ]]; then
  echo "FAIL: expected exactly one boot-*.tar.gz/.tar.xz archive, got ${#boot_archives[@]}" >&2
  find "${tmp}/bundle" -type f -print | sort >&2
  exit 1
fi
tar -tf "${boot_archives[0]}" > "${tmp}/boot-list.txt"
if ! awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }' "${tmp}/boot-list.txt"; then
  echo "FAIL: unsafe path in boot archive" >&2
  exit 1
fi
echo "Boot archive kernel/ramdisk candidates (preserve these names as supplied):"
grep -Ei '(^|/)(vmlinuz|Image|zImage|uImage|uInitrd|initrd)' "${tmp}/boot-list.txt" || true

modules_layout="target-root"
if ! grep -Eq '^([.]/)?lib/modules/[^/]+/' "${tmp}/modules-list.txt"; then
  modules_layout="release-root"
fi
module_target="${tmp}/module-target-root"
mkdir -p "${module_target}"
if ! dbai_install_kernel_modules_archive "${module_archives[0]}" "$modules_layout" "$module_release" "${tmp}/module-staging" "$module_target"; then
  echo "FAIL: actual published module archive could not be installed from isolated staging" >&2
  sed -n '1,100p' "${tmp}/modules-list.txt" >&2
  exit 1
fi
[[ -f "${module_target}/lib/modules/${module_release}/modules.dep" ]] || {
  echo "FAIL: actual bundle did not install modules.dep under the canonical module path" >&2
  exit 1
}
[[ ! -e "${module_target}/${module_release}" && ! -L "${module_target}/${module_release}" ]] || {
  echo "FAIL: actual module archive created a root-level kernel-release directory" >&2
  exit 1
}
echo "PASS: actual published module archive installed from staging without root-level residue"

mapfile -t header_archives < <(find "${tmp}/bundle" -type f \( -name 'header-*.tar.gz' -o -name 'header-*.tar.xz' \) -print)
if [[ "${#header_archives[@]}" -ne 1 ]]; then
  echo "FAIL: expected exactly one header-*.tar.gz/.tar.xz archive, got ${#header_archives[@]}" >&2
  find "${tmp}/bundle" -type f -print | sort >&2
  exit 1
fi

tar -tf "${header_archives[0]}" > "${tmp}/headers-list.txt"
if ! awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }' "${tmp}/headers-list.txt"; then
  echo "FAIL: unsafe path in headers archive" >&2
  exit 1
fi

echo "Actual published headers archive top-level paths:"
awk '{
  path=$0
  sub(/^\.\//, "", path)
  if (path=="" || path==".") next
  split(path,parts,"/")
  print parts[1]
}' "${tmp}/headers-list.txt" | sort -u

if ! layout="$(dbai_detect_kernel_headers_layout "${tmp}/headers-list.txt")"; then
  echo "FAIL: published header archive layout is unrecognized; first 100 entries:" >&2
  sed -n '1,100p' "${tmp}/headers-list.txt" >&2
  exit 1
fi
echo "Detected published header archive layout: ${layout}"

stage="${tmp}/target-root"
mkdir "${stage}"
case "${layout}" in
  uapi-root)
    tar --no-same-owner --no-same-permissions --transform='s,^[.]/,,;s,^,usr/src/linux-uapi-headers-test-release/,' -xf "${header_archives[0]}" -C "${stage}"
    find "${stage}/usr/src/linux-uapi-headers-test-release/include" -type f -print -quit | grep -q . || {
      echo "FAIL: UAPI headers were not installed at the isolated destination" >&2
      exit 1
    }
    [[ ! -e "${stage}/usr/src/linux-uapi-headers-test-release/Makefile" ]] || {
      echo "FAIL: test incorrectly classified a Makefile-bearing tree as UAPI-only" >&2
      exit 1
    }
    echo "NOTICE: published bundle provides UAPI-only headers, not a full kernel build-header tree."
    echo "PASS: UAPI headers are isolated and cannot masquerade as build headers."
    ;; header-root)
    tar --no-same-owner --no-same-permissions --transform='s,^[.]/,,;s,^,usr/src/linux-headers-test-release/,' -xf "${header_archives[0]}" -C "${stage}"
    [[ -f "${stage}/usr/src/linux-headers-test-release/Makefile" ]] || {
      echo "FAIL: normalized kernel headers Makefile is missing" >&2
      exit 1
    }
    echo "PASS: complete root-level kernel headers normalize correctly."
    ;;
  target-root)
    tar --no-same-owner --no-same-permissions -xf "${header_archives[0]}" -C "${stage}"
    if ! find "${stage}/usr/src" -type f -name Makefile -print -quit 2>/dev/null | grep -q . &&
       ! find "${stage}/lib/modules" -path '*/build/Makefile' -print -quit 2>/dev/null | grep -q .; then
      echo "FAIL: target-root archive was recognized but contains no build Makefile." >&2
      exit 1
    fi
    echo "PASS: target-root kernel build headers include a Makefile."
    ;;
esac
 "${tmp}/boot-list.txt" || true

modules_layout="target-root"
if ! grep -Eq '^([.]/)?lib/modules/[^/]+/' "${tmp}/modules-list.txt"; then
  modules_layout="release-root"
fi
module_target="${tmp}/module-target-root"
mkdir -p "${module_target}"
if ! dbai_install_kernel_modules_archive "${module_archives[0]}" "$modules_layout" "$module_release" "${tmp}/module-staging" "$module_target"; then
  echo "FAIL: actual published module archive could not be installed from isolated staging" >&2
  sed -n '1,100p' "${tmp}/modules-list.txt" >&2
  exit 1
fi
[[ -f "${module_target}/lib/modules/${module_release}/modules.dep" ]] || {
  echo "FAIL: actual bundle did not install modules.dep under the canonical module path" >&2
  exit 1
}
[[ ! -e "${module_target}/${module_release}" && ! -L "${module_target}/${module_release}" ]] || {
  echo "FAIL: actual module archive created a root-level kernel-release directory" >&2
  exit 1
}
echo "PASS: actual published module archive installed from staging without root-level residue"

mapfile -t header_archives < <(find "${tmp}/bundle" -type f \( -name 'header-*.tar.gz' -o -name 'header-*.tar.xz' \) -print)
if [[ "${#header_archives[@]}" -ne 1 ]]; then
  echo "FAIL: expected exactly one header-*.tar.gz/.tar.xz archive, got ${#header_archives[@]}" >&2
  find "${tmp}/bundle" -type f -print | sort >&2
  exit 1
fi

tar -tf "${header_archives[0]}" > "${tmp}/headers-list.txt"
if ! awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }' "${tmp}/headers-list.txt"; then
  echo "FAIL: unsafe path in headers archive" >&2
  exit 1
fi

echo "Actual published headers archive top-level paths:"
awk '{
  path=$0
  sub(/^\.\//, "", path)
  if (path=="" || path==".") next
  split(path,parts,"/")
  print parts[1]
}' "${tmp}/headers-list.txt" | sort -u

if ! layout="$(dbai_detect_kernel_headers_layout "${tmp}/headers-list.txt")"; then
  echo "FAIL: published header archive layout is unrecognized; first 100 entries:" >&2
  sed -n '1,100p' "${tmp}/headers-list.txt" >&2
  exit 1
fi
echo "Detected published header archive layout: ${layout}"

stage="${tmp}/target-root"
mkdir "${stage}"
case "${layout}" in
  uapi-root)
    tar --no-same-owner --no-same-permissions --transform='s,^[.]/,,;s,^,usr/src/linux-uapi-headers-test-release/,' -xf "${header_archives[0]}" -C "${stage}"
    find "${stage}/usr/src/linux-uapi-headers-test-release/include" -type f -print -quit | grep -q . || {
      echo "FAIL: UAPI headers were not installed at the isolated destination" >&2
      exit 1
    }
    [[ ! -e "${stage}/usr/src/linux-uapi-headers-test-release/Makefile" ]] || {
      echo "FAIL: test incorrectly classified a Makefile-bearing tree as UAPI-only" >&2
      exit 1
    }
    echo "NOTICE: published bundle provides UAPI-only headers, not a full kernel build-header tree."
    echo "PASS: UAPI headers are isolated and cannot masquerade as build headers."
    ;; header-root)
    tar --no-same-owner --no-same-permissions --transform='s,^[.]/,,;s,^,usr/src/linux-headers-test-release/,' -xf "${header_archives[0]}" -C "${stage}"
    [[ -f "${stage}/usr/src/linux-headers-test-release/Makefile" ]] || {
      echo "FAIL: normalized kernel headers Makefile is missing" >&2
      exit 1
    }
    echo "PASS: complete root-level kernel headers normalize correctly."
    ;;
  target-root)
    tar --no-same-owner --no-same-permissions -xf "${header_archives[0]}" -C "${stage}"
    if ! find "${stage}/usr/src" -type f -name Makefile -print -quit 2>/dev/null | grep -q . &&
       ! find "${stage}/lib/modules" -path '*/build/Makefile' -print -quit 2>/dev/null | grep -q .; then
      echo "FAIL: target-root archive was recognized but contains no build Makefile." >&2
      exit 1
    fi
    echo "PASS: target-root kernel build headers include a Makefile."
    ;;
esac
