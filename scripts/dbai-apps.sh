#!/usr/bin/env bash
# Show the live status of DBAI-managed applications.
# Uses only local package, systemd, process and Docker state; no network access.
set -o pipefail

ROOT="${DBAI_APPS_ROOT:-}"
target_path() { printf '%s%s' "${ROOT%/}" "$1"; }
file_exists() { [[ -e "$(target_path "$1")" || -L "$(target_path "$1")" ]]; }

package_installed() {
  local package="$1" fixture
  if [[ -n "$ROOT" ]]; then
    fixture="$(target_path /var/lib/dbai/apps-installed-packages)"
    [[ -r "$fixture" ]] && grep -Fxq -- "$package" "$fixture"
    return
  fi
  command -v dpkg-query >/dev/null 2>&1 || return 1
  dpkg-query -W -f='${db:Status-Status}\n' "$package" 2>/dev/null | grep -qx 'installed'
}

package_version() {
  local package="$1"
  if [[ -n "$ROOT" ]]; then
    return 0
  fi
  dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true
}

unit_exists() {
  local unit="$1"
  file_exists "/etc/systemd/system/$unit" ||
    file_exists "/lib/systemd/system/$unit" ||
    file_exists "/usr/lib/systemd/system/$unit"
}

unit_active() {
  local unit="$1" fixture
  if [[ -n "$ROOT" ]]; then
    fixture="$(target_path /var/lib/dbai/apps-active-units)"
    [[ -r "$fixture" ]] && grep -Fxq -- "$unit" "$fixture"
    return
  fi
  command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$unit" 2>/dev/null
}

process_active() {
  local process="$1" fixture
  if [[ -n "$ROOT" ]]; then
    fixture="$(target_path /var/lib/dbai/apps-processes)"
    [[ -r "$fixture" ]] && grep -Fxq -- "$process" "$fixture"
    return
  fi
  command -v pgrep >/dev/null 2>&1 && pgrep -x "$process" >/dev/null 2>&1
}

compose_profiles() {
  local file
  file="$(target_path /etc/dbai-apps.env)"
  [[ -r "$file" ]] || return 0
  sed -n 's/^DBAI_COMPOSE_PROFILE=//p' "$file" | head -n 1 | sed -e 's/^"//' -e 's/"$//' -e 's/,/ /g'
}

profile_selected() {
  local wanted="$1" profiles
  profiles="$(compose_profiles)"
  [[ " ${profiles//,/ } " == *" $wanted "* ]]
}

DOCKER_SNAPSHOT=''
DOCKER_SNAPSHOT_LOADED=0
load_docker_snapshot() {
  (( DOCKER_SNAPSHOT_LOADED == 0 )) || return 0
  DOCKER_SNAPSHOT_LOADED=1
  if [[ -n "$ROOT" ]]; then
    local fixture
    fixture="$(target_path /var/lib/dbai/apps-containers)"
    [[ -r "$fixture" ]] && DOCKER_SNAPSHOT="$(cat "$fixture")"
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    DOCKER_SNAPSHOT="$(timeout 3s docker ps -a --format '{{.Names}}|{{.Status}}' 2>/dev/null || true)"
  fi
}

container_state() {
  local wanted="$1" row name status
  load_docker_snapshot
  while IFS= read -r row; do
    [[ "$row" == *'|'* ]] || continue
    name="${row%%|*}"
    status="${row#*|}"
    if [[ "$name" == "$wanted" ]]; then
      if [[ "$status" == Up* ]]; then printf 'running'; else printf 'stopped'; fi
      return 0
    fi
  done <<< "$DOCKER_SNAPSHOT"
  printf 'absent'
}

file_executable() {
  local path
  for path in "$@"; do
    file_exists "$path" && [[ -x "$(target_path "$path")" ]] && return 0
    if [[ -z "$ROOT" && -x "$path" ]]; then return 0; fi
  done
  return 1
}

profile_has_container() {
  local profile="$1" container="$2" state
  state="$(container_state "$container")"
  [[ "$state" != absent ]] || profile_selected "$profile"
}

RESULT_NAME=''
RESULT_STATUS='not installed'
RESULT_DETAIL=''

set_result() {
  RESULT_NAME="$1"
  RESULT_STATUS="$2"
  RESULT_DETAIL="$3"
}

detect_proxmox() {
  local mode='Proxmox VE' pveproxy=no pvedaemon=no version=''
  if ! package_installed pve-manager; then
    set_result 'Proxmox VE' 'not installed' 'Package pve-manager was not found.'
    return
  fi
  if file_exists /etc/apt/sources.list.d/pxvirt-sources.list; then
    mode='Proxmox Community (PXVIRT)'
  elif file_exists /etc/apt/sources.list.d/pve-install-repo.sources; then
    mode='Proxmox VE Official'
  fi
  unit_active pveproxy.service && pveproxy=yes
  unit_active pvedaemon.service && pvedaemon=yes
  version="$(package_version pve-manager)"
  if [[ "$pveproxy" == yes && "$pvedaemon" == yes ]]; then
    set_result "$mode" 'running' "pve-manager ${version:-installed}; pveproxy and pvedaemon are active."
  else
    set_result "$mode" 'stopped' "pve-manager ${version:-installed}; pveproxy=$pveproxy, pvedaemon=$pvedaemon."
  fi
}

detect_docker() {
  local installed=no
  package_installed docker-ce && installed=yes
  package_installed docker.io && installed=yes
  package_installed docker-ce-cli && installed=yes
  unit_exists docker.service && installed=yes
  file_exists /usr/bin/docker && installed=yes
  if [[ "$installed" == no ]]; then
    set_result 'Docker' 'not installed' 'Docker packages and docker.service were not found.'
  elif unit_active docker.service; then
    set_result 'Docker' 'running' 'docker.service is active.'
  else
    set_result 'Docker' 'stopped' 'Docker is installed, but docker.service is not active.'
  fi
}

detect_homeassistant() {
  local installed=no running=no state
  package_installed homeassistant-supervised && installed=yes
  for unit in hassio-supervisor.service home-assistant@homeassistant.service home-assistant.service; do
    unit_exists "$unit" && installed=yes
    unit_active "$unit" && running=yes
  done
  for container in homeassistant home-assistant hassio_supervisor; do
    state="$(container_state "$container")"
    [[ "$state" != absent ]] && installed=yes
    [[ "$state" == running ]] && running=yes
  done
  if [[ "$installed" == no ]]; then
    set_result 'Home Assistant' 'not installed' 'Home Assistant Supervised service/package or a Home Assistant container was not found.'
  elif [[ "$running" == yes ]]; then
    set_result 'Home Assistant' 'running' 'A Home Assistant/Supervisor service or container is active.'
  else
    set_result 'Home Assistant' 'stopped' 'Home Assistant is installed, but no core service/container is running.'
  fi
}

detect_omv() {
  local installed=no running=no
  package_installed openmediavault && installed=yes
  for unit in openmediavault-engined.service omv-engined.service; do
    unit_exists "$unit" && installed=yes
    unit_active "$unit" && running=yes
  done
  if [[ "$installed" == no ]]; then
    set_result 'OpenMediaVault' 'not installed' 'Package openmediavault and its engine service were not found.'
  elif [[ "$running" == yes ]]; then
    set_result 'OpenMediaVault' 'running' 'The OMV management engine is active.'
  else
    set_result 'OpenMediaVault' 'stopped' 'OpenMediaVault is installed, but its management engine is not active.'
  fi
}

detect_casaos() {
  local installed=no running=no
  package_installed casaos && installed=yes
  file_executable /usr/bin/casaos /usr/local/bin/casaos && installed=yes
  for unit in casaos.service casaos-gateway.service; do
    unit_exists "$unit" && installed=yes
    unit_active "$unit" && running=yes
  done
  if [[ "$installed" == no ]]; then
    if unit_exists dbai-casaos-firstboot.service; then
      set_result 'CasaOS' 'not installed' 'The DBAI first-boot installer is staged; CasaOS itself is not installed yet.'
    else
      set_result 'CasaOS' 'not installed' 'CasaOS binary, package and services were not found.'
    fi
  elif [[ "$running" == yes ]]; then
    set_result 'CasaOS' 'running' 'A CasaOS core service is active.'
  else
    set_result 'CasaOS' 'stopped' 'CasaOS is installed, but its core services are not active.'
  fi
}

detect_hermes() {
  local installed=no running=no path
  package_installed hermes-agent && installed=yes
  file_executable /usr/bin/hermes /usr/local/bin/hermes /root/.local/bin/hermes && installed=yes
  if [[ -z "$ROOT" ]]; then
    command -v hermes >/dev/null 2>&1 && installed=yes
    for path in /home/*/.local/bin/hermes; do [[ -x "$path" ]] && installed=yes; done
  else
    for path in "$(target_path /home)"/*/.local/bin/hermes; do [[ -x "$path" ]] && installed=yes; done
  fi
  unit_exists hermes.service && installed=yes
  unit_active hermes.service && running=yes
  process_active hermes && running=yes
  if [[ "$installed" == no ]]; then
    if unit_exists dbai-hermes-firstboot.service; then
      set_result 'Hermes Agent' 'not installed' 'The first-boot installer is staged; Hermes has not been installed yet.'
    else
      set_result 'Hermes Agent' 'not installed' 'Hermes executable was not found.'
    fi
  elif [[ "$running" == yes ]]; then
    set_result 'Hermes Agent' 'running' 'A hermes process/service is active.'
  else
    set_result 'Hermes Agent' 'stopped' 'Hermes is installed but no hermes process/service is active; its CLI is not a daemon by default.'
  fi
}

detect_9router() {
  local state configured=no
  profile_selected hermes-9router && configured=yes
  state="$(container_state dbai-9router)"
  [[ "$state" != absent ]] && configured=yes
  if [[ "$configured" == no ]]; then
    set_result '9router' 'not installed' 'The Hermes/9router profile and dbai-9router container were not found.'
  elif [[ "$state" == running ]]; then
    set_result '9router' 'running' 'Docker container dbai-9router is running.'
  else
    set_result '9router' 'stopped' 'The 9router profile is configured, but dbai-9router is not running.'
  fi
}

detect_lightnvr() {
  local state configured=no
  profile_selected lightnvr-go2rtc && configured=yes
  state="$(container_state dbai-lightnvr)"
  [[ "$state" != absent ]] && configured=yes
  if [[ "$configured" == no ]]; then
    set_result 'LightNVR' 'not installed' 'The LightNVR/go2rtc profile and dbai-lightnvr container were not found.'
  elif [[ "$state" == running ]]; then
    set_result 'LightNVR' 'running' 'Docker container dbai-lightnvr is running.'
  else
    set_result 'LightNVR' 'stopped' 'The LightNVR profile is configured, but dbai-lightnvr is not running.'
  fi
}

detect_go2rtc() {
  local state configured=no
  profile_selected lightnvr-go2rtc && configured=yes
  state="$(container_state dbai-lightnvr)"
  if [[ "$state" != absent ]]; then configured=yes; fi
  if unit_exists go2rtc.service || file_executable /usr/bin/go2rtc /usr/local/bin/go2rtc; then configured=yes; fi
  local standalone=no
  unit_active go2rtc.service && standalone=yes
  process_active go2rtc && standalone=yes
  if [[ "$configured" == no ]]; then
    set_result 'go2rtc' 'not installed' 'No go2rtc service/binary or LightNVR profile was found.'
  elif [[ "$standalone" == yes || ( "$state" == running && "$state" != absent ) ]]; then
    if [[ "$state" == running && "$standalone" != yes ]]; then
      set_result 'go2rtc' 'running' 'go2rtc is bundled inside the running dbai-lightnvr container.'
    else
      set_result 'go2rtc' 'running' 'A go2rtc process/service or its bundled LightNVR container is active.'
    fi
  else
    set_result 'go2rtc' 'stopped' 'go2rtc is configured/installed, but no go2rtc service or LightNVR container is running.'
  fi
}

detect_app() {
  local app="${1,,}"
  case "$app" in
    pve|proxmox|proxmox-ve) detect_proxmox ;;
    docker|docker-ce) detect_docker ;;
    homeassistant|home-assistant|ha) detect_homeassistant ;;
    openmediavault|omv) detect_omv ;;
    casaos|casa-os) detect_casaos ;;
    hermes|hermes-agent) detect_hermes ;;
    9router|router9) detect_9router ;;
    lightnvr|light-nvr) detect_lightnvr ;;
    go2rtc) detect_go2rtc ;;
    proxmox-official)
      detect_proxmox
      if [[ "$RESULT_STATUS" != 'not installed' && "$RESULT_NAME" != 'Proxmox VE Official' ]]; then
        set_result 'Proxmox VE Official' 'not installed' 'The Official Proxmox repository marker was not found on this image.'
      fi
      ;;
    proxmox-community|pxvirt)
      detect_proxmox
      if [[ "$RESULT_STATUS" != 'not installed' && "$RESULT_NAME" != 'Proxmox Community (PXVIRT)' ]]; then
        set_result 'Proxmox Community (PXVIRT)' 'not installed' 'The PXVIRT repository marker was not found on this image.'
      fi
      ;;
    *)
      printf 'Unknown application: %s\n' "$1" >&2
      printf 'Valid names: proxmox, docker, homeassistant, openmediavault, casaos, hermes, 9router, lightnvr, go2rtc\n' >&2
      return 2
      ;;
  esac
}

if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == dumb ]]; then
  C_RESET='' C_GREEN='' C_YELLOW='' C_DIM='' C_CYAN=''
else
  C_RESET=$'\033[0m' C_GREEN=$'\033[0;32m' C_YELLOW=$'\033[0;33m' C_DIM=$'\033[0;90m' C_CYAN=$'\033[0;36m'
fi

print_one() {
  local app="$1" color
  detect_app "$app" || return $?
  case "$RESULT_STATUS" in
    running) color="$C_GREEN" ;;
    stopped) color="$C_YELLOW" ;;
    *) color="$C_DIM" ;;
  esac
  printf 'Application: %s%s%s\n' "$C_CYAN" "$RESULT_NAME" "$C_RESET"
  printf 'Status:      %s%s%s\n' "$color" "$RESULT_STATUS" "$C_RESET"
  printf 'Details:     %s\n' "$RESULT_DETAIL"
}

print_list() {
  local app color
  printf 'DBAI application status (local system check)\n'
  printf '%s%-22s %-15s%s\n' "$C_DIM" 'APPLICATION' 'STATUS' "$C_RESET"
  for app in proxmox docker homeassistant openmediavault casaos hermes 9router lightnvr go2rtc; do
    detect_app "$app" || continue
    case "$RESULT_STATUS" in
      running) color="$C_GREEN" ;;
      stopped) color="$C_YELLOW" ;;
      *) color="$C_DIM" ;;
    esac
    printf '%-22s %s%-15s%s\n' "$RESULT_NAME" "$color" "$RESULT_STATUS" "$C_RESET"
  done
  printf '\nUse: dbai-apps <name>  (example: dbai-apps proxmox)\n'
}

case "${1:-list}" in
  list|--list|-l) print_list ;;
  --help|-h|help)
    printf 'Usage: dbai-apps [list|proxmox|docker|homeassistant|openmediavault|casaos|hermes|9router|lightnvr|go2rtc]\n'
    printf 'Checks local package/service/process/container state; no network requests are made.\n'
    ;;
  *) print_one "$1" ;;
esac
