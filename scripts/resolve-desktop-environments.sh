#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <all|xfce|mate|gnome|cinnamon|kde-plasma|lxqt|i3-wm|enlightenment|budgie|openbox> <release>" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
selection="$1"
release="$2"

case "$release" in
  bullseye|bookworm|trixie|forky|jammy|noble|resolute) ;;
  *) echo "Unsupported release codename: $release" >&2; exit 2 ;;
esac

desktop_list_for_release() {
  case "$1" in
    # Debian Bullseye has no current Armbian configng desktop definitions;
    # the standalone DBAI Openbox extension supports it independently.
    bullseye)
      printf '%s\n' openbox
      ;;
    bookworm|trixie|noble)
      printf '%s\n' xfce mate gnome cinnamon kde-plasma lxqt i3-wm enlightenment budgie openbox
      ;;
    forky)
      printf '%s\n' xfce mate gnome cinnamon kde-plasma lxqt i3-wm enlightenment openbox
      ;;
    jammy)
      printf '%s\n' xfce mate gnome cinnamon kde-plasma lxqt i3-wm enlightenment openbox
      ;;
    resolute)
      printf '%s\n' xfce mate gnome cinnamon kde-plasma i3-wm enlightenment openbox
      ;;
  esac
}

case "$selection" in
  all)
    desktop_list_for_release "$release"
    ;;
  xfce|mate|gnome|cinnamon|kde-plasma|lxqt|i3-wm|enlightenment|budgie|openbox)
    available="$(desktop_list_for_release "$release")"
    if grep -Fxq "$selection" <<< "$available"; then
      printf '%s\n' "$selection"
    fi
    ;;
  *)
    echo "Unknown desktop environment selection: $selection" >&2
    exit 2
    ;;
esac
