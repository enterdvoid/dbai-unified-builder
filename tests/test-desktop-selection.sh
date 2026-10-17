#!/usr/bin/env bash
set -euo pipefail

resolver="scripts/resolve-desktop-environments.sh"
[[ -f "$resolver" ]] || { echo "FAIL: resolver is missing: $resolver" >&2; exit 1; }

assert_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\nexpected: <%s>\nactual:   <%s>\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_equals "xfce" "$(bash "$resolver" xfce trixie)" "single environment selection"
assert_equals "openbox" "$(bash "$resolver" openbox bullseye)" "Openbox on Bullseye"
assert_equals "" "$(bash "$resolver" budgie resolute)" "Budgie skipped on Resolute"
assert_equals "" "$(bash "$resolver" lxqt resolute)" "LXQt skipped on Resolute"
assert_equals "$(printf '%s\n' xfce mate gnome cinnamon kde-plasma lxqt i3-wm enlightenment budgie openbox)" "$(bash "$resolver" all bookworm)" "all Bookworm environments"
assert_equals "$(printf '%s\n' xfce mate gnome cinnamon kde-plasma i3-wm enlightenment openbox)" "$(bash "$resolver" all resolute)" "Resolute-compatible environments"

if bash "$resolver" invalid trixie >/dev/null 2>&1; then
  echo "FAIL: invalid desktop selection was accepted." >&2
  exit 1
fi
assert_equals "" "$(bash "$resolver" xfce bullseye)" "XFCE skipped on Bullseye"

echo "PASS: desktop environment selection and release compatibility."
