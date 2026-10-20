#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
header="$tmp/10-armbian-header"
commands="$tmp/41-commands"

cat > "$header" <<'HEADER'
#!/usr/bin/env bash
if [[ -n "${VENDORCOLOR:-}" ]]; then
  printf '\e[38;2;%sm%s\e[0m\n' "${VENDORCOLOR}" "$(figlet -f small " ${VENDOR}")"
fi

# --- Board name and version line ---
if [[ "${BOARD:-}" == "rpi4b" ]]; then
  BOARD_NAME="$(tr '\0' '\n' < /proc/device-tree/model | sed -E 's/ Rev [0-9.]+$//')"
fi
if [[ "${VERSION:-}" == *trunk* ]]; then
  VERSION="$(printf '%s' "${VERSION}" | cut -d'.' -f1-2)"
  VERSION="${VERSION} rolling"
fi
printf ' v%s for %s running Armbian Linux %s\n' "${VERSION}" "${BOARD_NAME}" "${KERNELID}"

# --- Hardware support status ---
HARDWARE_STATUS=""
HEADER

cat > "$commands" <<'COMMANDS'
list=(
    "Configuration","","armbian-config","true"
    "Upgrade","","armbian-upgrade","true"
    "Monitoring","","htop","true"
)
COMMANDS

python3 "$repo_root/scripts/patch-armbian-motd.py" "$header" "$commands"
bash -n "$header"
grep -Fq 'DBAI board and version line' "$header"
grep -Fq 'running on' "$header"
grep -Fq 'figlet -f slant' "$header"
grep -Fq "dbai-apps" "$commands"
grep -Fq "imba" "$commands"
grep -Fq "btop" "$commands"
grep -Fq '"VENDOR"' "$repo_root/extensions/dbai-branding.sh"

before_header="$(sha256sum "$header" | awk '{print $1}')"
before_commands="$(sha256sum "$commands" | awk '{print $1}')"
python3 "$repo_root/scripts/patch-armbian-motd.py" "$header" "$commands"
after_header="$(sha256sum "$header" | awk '{print $1}')"
after_commands="$(sha256sum "$commands" | awk '{print $1}')"
[[ "$before_header" == "$after_header" ]]
[[ "$before_commands" == "$after_commands" ]]

echo 'PASS: existing Armbian MOTD is patched in place, syntax-valid, and idempotent.'
