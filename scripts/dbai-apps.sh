#!/usr/bin/env bash
# DBAI Application Manager v1.0
# Show live status, interactive install with OS guardrails, service controller, and upgrade manager.
# Uses local package, systemd, process and Docker state; no network access during status check.
set -o pipefail

DBAI_APPS_VERSION="1.0"
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

detect_portainer() {
  local state
  state="$(container_state dbai-portainer)"
  [[ "$state" == absent ]] && state="$(container_state portainer)"
  if [[ "$state" == absent ]]; then
    set_result 'Portainer CE' 'not installed' 'Portainer container (dbai-portainer) was not found.'
  elif [[ "$state" == running ]]; then
    set_result 'Portainer CE' 'running' 'Portainer CE container is active on port 9000/9443.'
  else
    set_result 'Portainer CE' 'stopped' 'Portainer container exists but is not running.'
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

detect_tailscale() {
  local installed=no running=no
  package_installed tailscale && installed=yes
  file_executable /usr/bin/tailscale /usr/local/bin/tailscale && installed=yes
  unit_exists tailscaled.service && installed=yes
  unit_active tailscaled.service && running=yes
  if [[ "$installed" == no ]]; then
    set_result 'Tailscale' 'not installed' 'Package tailscale or binary was not found.'
  elif [[ "$running" == yes ]]; then
    set_result 'Tailscale' 'running' 'tailscaled.service daemon is active.'
  else
    set_result 'Tailscale' 'stopped' 'Tailscale is installed, but tailscaled service is inactive.'
  fi
}

detect_cloudflared() {
  local installed=no running=no
  file_executable /usr/local/bin/cloudflared /usr/bin/cloudflared && installed=yes
  package_installed cloudflared && installed=yes
  unit_exists cloudflared.service && installed=yes
  unit_active cloudflared.service && running=yes
  process_active cloudflared && running=yes
  if [[ "$installed" == no ]]; then
    set_result 'Cloudflare Tunnel' 'not installed' 'cloudflared binary or service was not found.'
  elif [[ "$running" == yes ]]; then
    set_result 'Cloudflare Tunnel' 'running' 'cloudflared tunnel service/process is active.'
  else
    set_result 'Cloudflare Tunnel' 'stopped' 'cloudflared binary is installed, but no tunnel is currently active.'
  fi
}

detect_app() {
  local app="${1,,}"
  case "$app" in
    pve|proxmox|proxmox-ve) detect_proxmox ;;
    docker|docker-ce) detect_docker ;;
    portainer|portainer-ce) detect_portainer ;;
    homeassistant|home-assistant|ha) detect_homeassistant ;;
    openmediavault|omv) detect_omv ;;
    casaos|casa-os) detect_casaos ;;
    hermes|hermes-agent) detect_hermes ;;
    9router|router9) detect_9router ;;
    lightnvr|light-nvr) detect_lightnvr ;;
    go2rtc) detect_go2rtc ;;
    tailscale) detect_tailscale ;;
    cloudflare|cloudflared) detect_cloudflared ;;
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
      printf 'Valid names: proxmox, docker, portainer, homeassistant, openmediavault, casaos, hermes, 9router, lightnvr, go2rtc, tailscale, cloudflared\n' >&2
      return 2
      ;;
  esac
}

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
  printf '%s%-26s %-15s%s\n' "$C_DIM" 'APPLICATION' 'STATUS' "$C_RESET"
  for app in proxmox docker portainer homeassistant openmediavault casaos hermes 9router lightnvr go2rtc tailscale cloudflared; do
    detect_app "$app" || continue
    case "$RESULT_STATUS" in
      running) color="$C_GREEN" ;;
      stopped) color="$C_YELLOW" ;;
      *) color="$C_DIM" ;;
    esac
    printf '%-26s %s%-15s%s\n' "$RESULT_NAME" "$color" "$RESULT_STATUS" "$C_RESET"
  done
  printf '\nUse: dbai-apps <name>  (example: dbai-apps proxmox)\n'
}

# --- Color Definitions ---
if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == dumb ]]; then
  C_RESET='' C_GREEN='' C_YELLOW='' C_DIM='' C_CYAN='' C_RED=''
else
  C_RESET=$'\033[0m' C_GREEN=$'\033[0;32m' C_YELLOW=$'\033[0;33m' C_DIM=$'\033[0;90m'
  C_CYAN=$'\033[0;36m' C_RED=$'\033[0;31m'
fi

# --- OS Release Detection & Compatibility Matrix ---
CURRENT_OS_ID="debian"
CURRENT_OS_CODENAME="bookworm"
CURRENT_OS_PRETTY="Debian 12 (bookworm)"
CURRENT_ARCH="aarch64"
CURRENT_KERNEL="6.1.66"

detect_system_os() {
  local os_file="/etc/os-release"
  [[ -n "$ROOT" && -r "${ROOT}/etc/os-release" ]] && os_file="${ROOT}/etc/os-release"

  CURRENT_OS_ID="debian"
  CURRENT_OS_CODENAME="bookworm"
  local ver_id=""

  if [[ -r "$os_file" ]]; then
    CURRENT_OS_ID="$(sed -n 's/^ID=//p' "$os_file" | head -n1 | tr -d '"')"
    CURRENT_OS_CODENAME="$(sed -n 's/^VERSION_CODENAME=//p' "$os_file" | head -n1 | tr -d '"')"
    ver_id="$(sed -n 's/^VERSION_ID=//p' "$os_file" | head -n1 | tr -d '"')"
  fi

  [[ -z "$CURRENT_OS_ID" ]] && CURRENT_OS_ID="debian"
  [[ -z "$CURRENT_OS_CODENAME" ]] && CURRENT_OS_CODENAME="bookworm"

  if [[ -n "$ver_id" ]]; then
    CURRENT_OS_PRETTY="${CURRENT_OS_ID^} ${ver_id} (${CURRENT_OS_CODENAME})"
  else
    CURRENT_OS_PRETTY="${CURRENT_OS_ID^} (${CURRENT_OS_CODENAME})"
  fi

  if command -v uname >/dev/null 2>&1; then
    CURRENT_ARCH="$(uname -m 2>/dev/null || echo 'aarch64')"
    local k
    k="$(uname -r 2>/dev/null || echo '6.1.66')"
    CURRENT_KERNEL="${k%%-*}"
  fi
}

SUPPORT_STATUS="compatible"
SUPPORT_REASON="✓ Compatible    "
SUPPORT_COLOR="$C_GREEN"

check_app_support() {
  local app="$1"
  SUPPORT_STATUS="compatible"
  SUPPORT_REASON="✓ Compatible    "
  SUPPORT_COLOR="$C_GREEN"

  case "$app" in
    proxmox_community|proxmox-community)
      if [[ "$CURRENT_OS_ID" != "debian" ]]; then
        SUPPORT_STATUS="incompatible"
        SUPPORT_REASON="✗ Debian Only   "
        SUPPORT_COLOR="$C_RED"
      elif [[ "$CURRENT_OS_CODENAME" != "trixie" && "$CURRENT_OS_CODENAME" != "bookworm" ]]; then
        SUPPORT_STATUS="incompatible"
        SUPPORT_REASON="✗ Requires Trix "
        SUPPORT_COLOR="$C_RED"
      fi
      ;;
    proxmox_official|proxmox-official)
      if [[ "$CURRENT_OS_ID" != "debian" ]]; then
        SUPPORT_STATUS="incompatible"
        SUPPORT_REASON="✗ Debian Only   "
        SUPPORT_COLOR="$C_RED"
      elif [[ "$CURRENT_OS_CODENAME" != "bookworm" ]]; then
        SUPPORT_STATUS="incompatible"
        SUPPORT_REASON="✗ Requires Book "
        SUPPORT_COLOR="$C_RED"
      fi
      ;;
    openmediavault|omv)
      if [[ "$CURRENT_OS_ID" == "ubuntu" ]]; then
        SUPPORT_STATUS="incompatible"
        if [[ "$CURRENT_OS_CODENAME" == "resolute" ]]; then
          SUPPORT_REASON="✗ Resolute Blkd "
        else
          SUPPORT_REASON="✗ Debian Only   "
        fi
        SUPPORT_COLOR="$C_RED"
      elif [[ "$CURRENT_OS_ID" != "debian" ]]; then
        SUPPORT_STATUS="incompatible"
        SUPPORT_REASON="✗ Debian Only   "
        SUPPORT_COLOR="$C_RED"
      fi
      ;;
    *)
      SUPPORT_STATUS="compatible"
      SUPPORT_REASON="✓ Compatible    "
      SUPPORT_COLOR="$C_GREEN"
      ;;
  esac
}

execute_install() {
  local app="$1"
  detect_system_os
  check_app_support "$app"

  if [[ "$SUPPORT_STATUS" == "incompatible" ]]; then
    printf '\n%s[PERINGATAN KOMPATIBILITAS OS]%s\n' "$C_RED" "$C_RESET"
    printf 'Instalasi dibatalkan: Aplikasi %s tidak kompatibel dengan OS host saat ini (%s - %s).\n' "$app" "$CURRENT_OS_ID" "$CURRENT_OS_CODENAME"
    case "$app" in
      openmediavault|omv)
        printf 'Alasan teknis: OpenMediaVault sangat terikat pada stack Debian networking/PAM standard dan tidak kompatibel dengan Netplan / versi PAM Ubuntu modern (%s).\n' "$CURRENT_OS_CODENAME"
        ;;
      proxmox*|pve*)
        printf 'Alasan teknis: Paket Proxmox VE memerlukan kernel dan repositori Debian resmi (%s), tidak didukung pada Ubuntu.\n' "$CURRENT_OS_CODENAME"
        ;;
      *)
        printf 'Alasan teknis: %s\n' "$SUPPORT_REASON"
        ;;
    esac
    printf 'Untuk menjaga stabilitas sistem operasi, instalasi tidak dapat dilanjutkan.\n\n'
    return 1
  fi

  printf '\n%s[MEMULAI INSTALASI]%s %s pada %s (%s)...\n' "$C_GREEN" "$C_RESET" "$app" "$CURRENT_OS_ID" "$CURRENT_OS_CODENAME"
  case "$app" in
    docker)
      apt-get update
      if ! apt-get install -y docker-ce docker-ce-cli containerd.io; then
        apt-get install -y docker.io
      fi
      systemctl enable --now docker
      ;;
    portainer)
      docker run -d -p 9000:9000 -p 9443:9443 --name dbai-portainer --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
      ;;
    tailscale)
      if command -v tailscale >/dev/null 2>&1; then
        tailscale up
      else
        curl -fsSL https://tailscale.com/install.sh | sh
        systemctl enable --now tailscaled
        tailscale up
      fi
      ;;
    cloudflared)
      if [[ ! -x /usr/local/bin/cloudflared ]]; then
        local cf_arch="arm64"
        [[ "$(uname -m)" == "x86_64" ]] && cf_arch="amd64"
        curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}" -o /usr/local/bin/cloudflared
        chmod 755 /usr/local/bin/cloudflared
      fi
      printf 'cloudflared siap. Jalankan: cloudflared tunnel login\n'
      ;;
    *)
      printf 'Instalasi %s siap dieksekusi melalui profil DBAI.\n' "$app"
      ;;
  esac
  printf '%sInstalasi selesai.%s\n\n' "$C_GREEN" "$C_RESET"
}

# --- 12 Applications List for TUI Menu ---
APP_KEYS=(
  "docker"
  "portainer"
  "9router"
  "lightnvr"
  "proxmox-community"
  "proxmox-official"
  "openmediavault"
  "casaos"
  "homeassistant"
  "hermes"
  "tailscale"
  "cloudflared"
)

APP_TITLES=(
  "Docker Engine"
  "Portainer CE"
  "9router AI Proxy"
  "LightNVR + go2rtc"
  "Proxmox Community (PXVIRT)"
  "Proxmox VE Official"
  "OpenMediaVault (OMV)"
  "CasaOS Dashboard"
  "Home Assistant Supervised"
  "Hermes AI Agent"
  "Tailscale Mesh VPN"
  "Cloudflare Tunnel"
)

APP_TYPES=(
  "System"
  "Container"
  "Container"
  "Container"
  "System"
  "System"
  "System"
  "Service"
  "Service"
  "CLI/Serv"
  "Network"
  "Network"
)

# --- Submenus ---
menu_install() {
  while true; do
    detect_system_os
    clear 2>/dev/null || true
    local top="╔════════════════════════════════════════════════════════════════════════════╗"
    local div="╠════════════════════════════════════════════════════════════════════════════╣"
    local bot="╚════════════════════════════════════════════════════════════════════════════╝"

    printf "%s%s%s\n" "$C_CYAN" "$top" "$C_RESET"
    printf "%s║%s                     MENU PENGINSTALAN APLIKASI                             %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s       Host OS: %-15s | Arch: %-8s                         %s║%s\n" "$C_CYAN" "$C_RESET" "$CURRENT_OS_PRETTY" "$CURRENT_ARCH" "$C_CYAN" "$C_RESET"
    printf "%s%s%s\n" "$C_CYAN" "$div" "$C_RESET"
    printf "%s║%s   #   APLIKASI                  TIPE       OS SUPPORT                      %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s  ───  ────────────────────────  ─────────  ──────────────                  %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"

    local i
    for i in {0..11}; do
      local k="${APP_KEYS[$i]}"
      local t="${APP_TITLES[$i]}"
      local ty="${APP_TYPES[$i]}"
      check_app_support "$k"
      printf "%s║%s  %2d   %-26s%-11s%b%b               %s║%s\n" \
        "$C_CYAN" "$C_RESET" \
        "$((i+1))" "$t" "$ty" \
        "$SUPPORT_COLOR" "$SUPPORT_REASON" \
        "$C_CYAN" "$C_RESET"
    done

    printf "%s║%s                                                                            %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s%s%s\n" "$C_CYAN" "$div" "$C_RESET"
    printf "%s║%s  Masukkan nomor [1-12] untuk memasang, atau [0] untuk kembali:              %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s%s%s\n" "$C_CYAN" "$bot" "$C_RESET"
    read -r -p "Pilihan Anda: " inst_choice

    if [[ "$inst_choice" == "0" || -z "$inst_choice" ]]; then
      return 0
    fi

    if [[ "$inst_choice" =~ ^[1-9]$|^1[0-2]$ ]]; then
      local idx=$((inst_choice - 1))
      local sel_key="${APP_KEYS[$idx]}"
      execute_install "$sel_key" || true
      read -r -p "Tekan [Enter] untuk melanjutkan..."
    else
      printf "Pilihan tidak valid.\n"
      sleep 1
    fi
  done
}

menu_upgrade() {
  clear 2>/dev/null || true
  local top="╔════════════════════════════════════════════════════════════════════════════╗"
  local div="╠════════════════════════════════════════════════════════════════════════════╣"
  local bot="╚════════════════════════════════════════════════════════════════════════════╝"

  printf "%s%s%s\n" "$C_CYAN" "$top" "$C_RESET"
  printf "%s║%s                   MENU PEMBARUAN / UPGRADE APLIKASI                        %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
  printf "%s%s%s\n" "$C_CYAN" "$div" "$C_RESET"
  printf "  Memeriksa container & status paket sistem...\n\n"

  if command -v docker >/dev/null 2>&1; then
    printf "  [Container Docker Aktif]:\n"
    for c in dbai-portainer dbai-9router dbai-lightnvr; do
      local st
      st="$(container_state "$c")"
      if [[ "$st" != "absent" ]]; then
        printf "    • %-18s : Status (%s)\n" "$c" "$st"
      fi
    done
    printf "\n"
  fi

  printf "  Pilihan Tindakan Upgrade:\n"
  printf "   [1] Perbarui image container Docker (docker compose pull & restart)\n"
  printf "   [2] Perbarui paket sistem (apt-get update && apt-get upgrade)\n"
  printf "   [0] Kembali ke Menu Utama\n"
  printf "%s%s%s\n" "$C_CYAN" "$bot" "$C_RESET"
  read -r -p "Pilihan Anda: " up_opt
  case "$up_opt" in
    1)
      if [[ -f /opt/dbai/apps/docker-compose.yml ]]; then
        docker compose -f /opt/dbai/apps/docker-compose.yml pull && docker compose -f /opt/dbai/apps/docker-compose.yml up -d
      else
        echo "File compose /opt/dbai/apps/docker-compose.yml tidak ditemukan."
      fi
      read -r -p "Tekan [Enter] untuk melanjutkan..."
      ;;
    2)
      apt-get update && apt-get upgrade -y
      read -r -p "Tekan [Enter] untuk melanjutkan..."
      ;;
    *) return 0 ;;
  esac
}

menu_services() {
  while true; do
    clear 2>/dev/null || true
    local top="╔════════════════════════════════════════════════════════════════════════════╗"
    local div="╠════════════════════════════════════════════════════════════════════════════╣"
    local bot="╚════════════════════════════════════════════════════════════════════════════╝"

    printf "%s%s%s\n" "$C_CYAN" "$top" "$C_RESET"
    printf "%s║%s              SERVICE CONTROLLER (Start / Stop / Restart)                   %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s%s%s\n" "$C_CYAN" "$div" "$C_RESET"

    printf "  Layanan & Container yang Terdeteksi:\n\n"
    local svc_names=("docker" "dbai-portainer" "dbai-9router" "dbai-lightnvr" "tailscaled" "cloudflared" "casaos")
    local svc_types=("service" "container" "container" "container" "service" "service" "service")
    local available_indices=()
    local num=1

    for s_idx in "${!svc_names[@]}"; do
      local s="${svc_names[$s_idx]}"
      local stype="${svc_types[$s_idx]}"
      local state="not installed"

      if [[ "$stype" == "container" ]]; then
        state="$(container_state "$s")"
      else
        if unit_active "${s}.service" || unit_active "$s"; then
          state="running"
        elif unit_exists "${s}.service" || unit_exists "$s"; then
          state="stopped"
        fi
      fi

      if [[ "$state" != "not installed" && "$state" != "absent" ]]; then
        local col="$C_YELLOW"
        [[ "$state" == "running" ]] && col="$C_GREEN"
        printf "   [%d] %-18s (%-9s) : %b%s%b\n" "$num" "$s" "$stype" "$col" "$state" "$C_RESET"
        available_indices+=("$s|$stype")
        ((num++))
      fi
    done

    if [[ ${#available_indices[@]} -eq 0 ]]; then
      printf "   Tidak ada service atau container aktif yang ditemukan untuk dikontrol.\n\n"
      printf "%s%s%s\n" "$C_CYAN" "$bot" "$C_RESET"
      read -r -p "Tekan [Enter] untuk kembali..."
      return 0
    fi

    printf "\n   [0] Kembali ke Menu Utama\n"
    printf "%s%s%s\n" "$C_CYAN" "$bot" "$C_RESET"
    read -r -p "Pilih nomor layanan [0-$((num-1))]: " sel_svc
    if [[ "$sel_svc" == "0" || -z "$sel_svc" ]]; then return 0; fi

    if [[ "$sel_svc" =~ ^[0-9]+$ ]] && (( sel_svc >= 1 && sel_svc < num )); then
      local entry="${available_indices[$((sel_svc-1))]}"
      local tgt_name="${entry%%|*}"
      local tgt_type="${entry##*|}"

      printf "\nPilih Aksi untuk %s:\n" "$tgt_name"
      printf " [1] Start\n"
      printf " [2] Stop\n"
      printf " [3] Restart\n"
      printf " [0] Batal\n"
      read -r -p "Pilihan Anda: " act
      case "$act" in
        1)
          if [[ "$tgt_type" == "container" ]]; then docker start "$tgt_name"; else systemctl start "$tgt_name"; fi
          ;;
        2)
          if [[ "$tgt_type" == "container" ]]; then docker stop "$tgt_name"; else systemctl stop "$tgt_name"; fi
          ;;
        3)
          if [[ "$tgt_type" == "container" ]]; then docker restart "$tgt_name"; else systemctl restart "$tgt_name"; fi
          ;;
        *) ;;
      esac
      read -r -p "Aksi selesai. Tekan [Enter] untuk melanjutkan..."
    fi
  done
}

menu_tunnels() {
  clear 2>/dev/null || true
  local top="╔════════════════════════════════════════════════════════════════════════════╗"
  local div="╠════════════════════════════════════════════════════════════════════════════╣"
  local bot="╚════════════════════════════════════════════════════════════════════════════╝"

  printf "%s%s%s\n" "$C_CYAN" "$top" "$C_RESET"
  printf "%s║%s            REMOTE TUNNEL SETUP (Tailscale & Cloudflare Auth)              %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
  printf "%s%s%s\n" "$C_CYAN" "$div" "$C_RESET"
  printf "  Menu Pengaturan Remote Tunnel:\n\n"
  printf "   [1] Cek Status Tailscale (tailscale status)\n"
  printf "   [2] Login / Hubungkan Tailscale (tailscale up)\n"
  printf "   [3] Cek Status Cloudflare Tunnel (cloudflared status)\n"
  printf "   [4] Otentikasi Cloudflare Tunnel (cloudflared tunnel login)\n"
  printf "   [0] Kembali ke Menu Utama\n\n"
  printf "%s%s%s\n" "$C_CYAN" "$bot" "$C_RESET"
  read -r -p "Pilihan Anda [0-4]: " tun_choice

  case "$tun_choice" in
    1)
      if command -v tailscale >/dev/null 2>&1; then tailscale status; else echo "Tailscale belum terpasang."; fi
      read -r -p "Tekan [Enter] untuk melanjutkan..."
      ;;
    2)
      if command -v tailscale >/dev/null 2>&1; then tailscale up; else echo "Tailscale belum terpasang."; fi
      read -r -p "Tekan [Enter] untuk melanjutkan..."
      ;;
    3)
      if command -v cloudflared >/dev/null 2>&1; then cloudflared --version; else echo "cloudflared belum terpasang."; fi
      read -r -p "Tekan [Enter] untuk melanjutkan..."
      ;;
    4)
      if command -v cloudflared >/dev/null 2>&1; then cloudflared tunnel login; else echo "cloudflared belum terpasang."; fi
      read -r -p "Tekan [Enter] untuk melanjutkan..."
      ;;
    *) return 0 ;;
  esac
}

# --- Interactive Main Menu ---
interactive_main_menu() {
  while true; do
    detect_system_os
    clear 2>/dev/null || true

    local top="╔════════════════════════════════════════════════════════════════════════════╗"
    local div="╠════════════════════════════════════════════════════════════════════════════╣"
    local bot="╚════════════════════════════════════════════════════════════════════════════╝"

    # Top border
    printf "%s%s%s\n" "$C_CYAN" "$top" "$C_RESET"

    # Title line centered in 76 chars
    local title="DBAI APPLICATION MANAGER v${DBAI_APPS_VERSION}"
    local p_left=$(( (76 - ${#title}) / 2 ))
    local p_right=$(( 76 - ${#title} - p_left ))
    printf "%s║%s%*s%s%*s%s║%s\n" "$C_CYAN" "$C_RESET" "$p_left" "" "$title" "$p_right" "" "$C_CYAN" "$C_RESET"

    # Host info line centered in 76 chars
    local host_line="Host OS: ${CURRENT_OS_PRETTY} | Arch: ${CURRENT_ARCH} | Kernel: ${CURRENT_KERNEL}"
    if (( ${#host_line} > 74 )); then
      host_line="${host_line:0:71}..."
    fi
    p_left=$(( (76 - ${#host_line}) / 2 ))
    p_right=$(( 76 - ${#host_line} - p_left ))
    printf "%s║%s%*s%s%*s%s║%s\n" "$C_CYAN" "$C_RESET" "$p_left" "" "$host_line" "$p_right" "" "$C_CYAN" "$C_RESET"

    # Divider
    printf "%s%s%s\n" "$C_CYAN" "$div" "$C_RESET"

    # Counters
    local count_active=0 count_stopped=0 count_uninstalled=0

    # Scan all 12 apps
    local app_states=()
    local app_reasons=()
    local app_supp_cols=()

    local i
    for i in {0..11}; do
      local k="${APP_KEYS[$i]}"
      detect_app "$k" >/dev/null 2>&1 || true
      app_states+=("$RESULT_STATUS")

      case "$RESULT_STATUS" in
        running) ((count_active++)) ;;
        stopped) ((count_stopped++)) ;;
        *) ((count_uninstalled++)) ;;
      esac

      check_app_support "$k"
      app_reasons+=("$SUPPORT_REASON")
      app_supp_cols+=("$SUPPORT_COLOR")
    done

    # Status summary line (exact 76 chars inner)
    local sum_plain="  Status Ringkas: [● Active: ${count_active}]   [■ Stopped: ${count_stopped}]   [○ Not Installed: ${count_uninstalled}]"
    local pad_end=$(( 76 - ${#sum_plain} ))
    printf "%s║%s  Status Ringkas: [%b● Active: %s%b]   [%b■ Stopped: %s%b]   [%b○ Not Installed: %s%b]%*s%s║%s\n" \
      "$C_CYAN" "$C_RESET" \
      "$C_GREEN" "$count_active" "$C_RESET" \
      "$C_YELLOW" "$count_stopped" "$C_RESET" \
      "$C_DIM" "$count_uninstalled" "$C_RESET" \
      "$pad_end" "" \
      "$C_CYAN" "$C_RESET"

    # Divider
    printf "%s%s%s\n" "$C_CYAN" "$div" "$C_RESET"

    # Empty line
    printf "%s║%s                                                                            %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"

    # Header and divider rows
    printf "%s║%s   #   APLIKASI                  TIPE       STATUS          OS SUPPORT      %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s  ───  ────────────────────────  ─────────  ──────────────  ──────────────  %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"

    # Data rows
    for i in {0..11}; do
      local idx=$((i + 1))
      local t="${APP_TITLES[$i]}"
      local ty="${APP_TYPES[$i]}"
      local st="${app_states[$i]}"
      local supp="${app_reasons[$i]}"
      local supp_col="${app_supp_cols[$i]}"

      local stat_sym="○" stat_str="NOT INSTALLED" stat_col="$C_DIM"
      case "$st" in
        running) stat_sym="●"; stat_str="RUNNING"; stat_col="$C_GREEN" ;;
        stopped) stat_sym="■"; stat_str="STOPPED"; stat_col="$C_YELLOW" ;;
      esac

      local stat_plain="${stat_sym} ${stat_str}"
      local stat_pad=$(( 16 - ${#stat_plain} ))
      local supp_pad=$(( 16 - ${#supp} ))

      printf "%s║%s  %2d   %-26s%-11s%b%b%s║%s\n" \
        "$C_CYAN" "$C_RESET" \
        "$idx" "$t" "$ty" \
        "${stat_col}${stat_plain}$(printf '%*s' "$stat_pad" '')${C_RESET}" \
        "${supp_col}${supp}$(printf '%*s' "$supp_pad" '')${C_RESET}" \
        "$C_CYAN" "$C_RESET"
    done

    # Empty line
    printf "%s║%s                                                                            %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"

    # Divider
    printf "%s%s%s\n" "$C_CYAN" "$div" "$C_RESET"

    # Menu Tindakan
    printf "%s║%s  Menu Tindakan:                                                            %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s                                                                            %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s   [1] 📦 Menu Penginstalan Aplikasi                                        %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s   [2] 🚀 Menu Pembaruan / Upgrade Aplikasi                                 %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s   [3] ⚡ Service Controller (Start / Stop / Restart)                       %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s   [4] 🌐 Remote Tunnel Setup (Tailscale & Cloudflare Auth)                 %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s   [0] 🚪 Keluar                                                            %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf "%s║%s                                                                            %s║%s\n" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"

    # Bottom border
    printf "%s%s%s\n" "$C_CYAN" "$bot" "$C_RESET"

    read -r -p "Masukkan pilihan [0-4]: " opt
    case "$opt" in
      1) menu_install ;;
      2) menu_upgrade ;;
      3) menu_services ;;
      4) menu_tunnels ;;
      0|q|exit) clear 2>/dev/null || true; exit 0 ;;
      *) ;;
    esac
  done
}

case "${1:-}" in
  list|--list|-l) print_list ;;
  menu|--menu|-m) interactive_main_menu ;;
  install)
    if [[ -z "${2:-}" ]]; then
      echo "Gunakan: dbai-apps install <nama-aplikasi>"
      exit 1
    fi
    execute_install "$2"
    ;;
  --help|-h|help)
    printf 'Usage: dbai-apps [list|menu|install <name>|proxmox|docker|portainer|homeassistant|openmediavault|casaos|hermes|9router|lightnvr|go2rtc|tailscale|cloudflared]\n'
    printf 'Checks local package/service/process/container state; provides interactive TUI.\n'
    ;;
  "")
    if [[ -t 0 ]]; then
      interactive_main_menu
    else
      print_list
    fi
    ;;
  *) print_one "$1" ;;
esac
