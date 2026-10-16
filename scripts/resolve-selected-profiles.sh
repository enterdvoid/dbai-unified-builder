#!/usr/bin/env bash
set -euo pipefail

labels=(minimal server application desktop)
flags=("$@")
[[ "${#flags[@]}" -eq 4 ]] || {
  echo "Expected four boolean flags in this order: Minimal Server Application Desktop." >&2
  exit 2
}

selected=()
for i in "${!labels[@]}"; do
  case "${flags[$i]}" in
    true) selected+=("${labels[$i]}") ;;
    false) ;;
    *) echo "Invalid boolean for ${labels[$i]}: ${flags[$i]}" >&2; exit 2 ;;
  esac
done

(("${#selected[@]}" > 0)) || {
  echo "Select at least one image type (Minimal, Server, Application, or Desktop)." >&2
  exit 2
}
IFS=,
printf '%s\n' "${selected[*]}"
