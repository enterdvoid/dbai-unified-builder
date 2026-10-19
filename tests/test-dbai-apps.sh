#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/root"
mkdir -p "$root/var/lib/dbai" "$root/etc/apt/sources.list.d" "$root/etc" \
  "$root/usr/lib/systemd/system"
cat > "$root/var/lib/dbai/apps-installed-packages" <<'PACKAGES'
pve-manager
docker-ce
openmediavault
openbox
PACKAGES
cat > "$root/var/lib/dbai/apps-active-units" <<'UNITS'
pveproxy.service
pvedaemon.service
docker.service
openmediavault-engined.service
UNITS
printf '%s\n' openbox > "$root/var/lib/dbai/apps-processes"
cat > "$root/var/lib/dbai/apps-containers" <<'CONTAINERS'
dbai-9router|Up 5 minutes
dbai-lightnvr|Exited (1) 2 minutes ago
CONTAINERS
cat > "$root/etc/dbai-apps.env" <<'ENV'
DBAI_COMPOSE_PROFILE="hermes-9router lightnvr-go2rtc"
ENV
: > "$root/etc/apt/sources.list.d/pve-install-repo.sources"
: > "$root/usr/lib/systemd/system/dbai-hermes-firstboot.service"
: > "$root/usr/lib/systemd/system/dbai-casaos-firstboot.service"

run_app() {
  DBAI_APPS_ROOT="$root" NO_COLOR=1 bash "$repo_root/scripts/dbai-apps.sh" "$@"
}

proxmox="$(run_app proxmox)"
grep -Fq 'Proxmox VE Official' <<< "$proxmox"
grep -Fq 'Status:      running' <<< "$proxmox"

router="$(run_app 9router)"
grep -Fq 'Status:      running' <<< "$router"

nvr="$(run_app lightnvr)"
grep -Fq 'Status:      stopped' <<< "$nvr"

go2rtc="$(run_app go2rtc)"
grep -Fq 'Status:      stopped' <<< "$go2rtc"

openbox="$(run_app openbox)"
grep -Fq 'Status:      running' <<< "$openbox"

ha="$(run_app homeassistant)"
grep -Fq 'Status:      not installed' <<< "$ha"

hermes="$(run_app hermes)"
grep -Fq 'Status:      not installed' <<< "$hermes"
grep -Fq 'first-boot installer is staged' <<< "$hermes"

casaos="$(run_app casaos)"
grep -Fq 'Status:      not installed' <<< "$casaos"
grep -Fq 'first-boot installer is staged' <<< "$casaos"

list="$(run_app list)"
grep -Fq 'Proxmox VE Official' <<< "$list"
grep -Fq 'LightNVR' <<< "$list"
grep -Fq 'Use: dbai-apps <name>' <<< "$list"

if run_app unknown-app >"$tmp/unknown.out" 2>&1; then
  echo 'FAIL: unknown app name should return a non-zero status.' >&2
  exit 1
fi
grep -Fq 'Unknown application' "$tmp/unknown.out"

echo 'PASS: dbai-apps reports running/stopped/not installed from local package, service, profile, process and container state.'
