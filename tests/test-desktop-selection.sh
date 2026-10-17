#!/usr/bin/env bash
set -euo pipefail

resolver="scripts/resolve-desktop-environments.sh"
[[ -x "$resolver" ]] || { echo "FAIL: resolver is missing or not executable: $resolver" >&2; exit 1; }

assert_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\nexpected: <%s>\nactual:   <%s>\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_equals "xfce" "$("$resolver" xfce trixie)" "single environment selection"
assert_equals "openbox" "$("$resolver" openbox bullseye)" "Openbox on Bullseye"
assert_equals "" "$("$resolver" budgie resolute)" "Budgie skipped on Resolute"
assert_equals "" "$("$resolver" lxqt resolute)" "LXQt skipped on Resolute"
assert_equals "$(printf '%s\n' xfce mate gnome cinnamon kde-plasma lxqt i3-wm enlightenment budgie openbox)" "$("$resolver" all bookworm)" "all Bookworm environments"
assert_equals "$(printf '%s\n' xfce mate gnome cinnamon kde-plasma i3-wm enlightenment openbox)" "$("$resolver" all resolute)" "Resolute-compatible environments"

if "$resolver" invalid trixie >/dev/null 2>&1; then
  echo "FAIL: invalid desktop selection was accepted." >&2
  exit 1
fi
if "$resolver" xfce bullseye >/dev/null 2>&1; then
  echo "FAIL: unsupported specific environment should resolve to no matrix entries, not an error." >&2
  exit 1
fi

echo "PASS: desktop environment selection and release compatibility."
