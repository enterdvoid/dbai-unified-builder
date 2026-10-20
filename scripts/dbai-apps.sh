#!/usr/bin/env bash
# DBAI Application Manager v1.0
# Show live status, interactive install with OS guardrails, and upgrade manager.
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
CURRENT_ARCH="arm64"
COMPAT_REASON=""

detect_system_os() {
  if file_exists /etc/os-release; then
    CURRENT_OS_ID="$(awk -F= '/^ID=/{sub(/^"/,"",$2); sub(/"$/,"",$2); print $2}' "$(target_path /etc/os-release)")"
    CURRENT_OS_CODENAME="$(awk -F= '/^VERSION_CODENAME=/{sub(/^"/,"",$2); sub(/"$/,"",$2); print $2}' "$(target_path /etc/os-release)")"
  elif file_exists /etc/lsb-release; then
    CURRENT_OS_ID="$(awk -F= '/^DISTRIB_ID=/{sub(/^"/,"",$2); sub(/"$/,"",$2); print $2}' "$(target_path /etc/lsb-release)")"
    CURRENT_OS_CODENAME="$(awk -F= '/^DISTRIB_CODENAME=/{sub(/^"/,"",$2); sub(/"$/,"",$2); print $2}' "$(target_path /etc/lsb-release)")"
  fi
  [[ -n "$CURRENT_OS_ID" ]] || CURRENT_OS_ID="debian"
  [[ -n "$CURRENT_OS_CODENAME" ]] || CURRENT_OS_CODENAME="bookworm"
  CURRENT_ARCH="$(uname -m 2>/dev/null || echo "arm64")"
}

check_app_compatibility() {
  local app="$1"
  detect_system_os
  local os="${CURRENT_OS_ID,,}"
  local rel="${CURRENT_OS_CODENAME,,}"
  COMPAT_REASON=""

  case "$app" in
    proxmox-official)
      if [[ "$os" == "debian" && "$rel" == "trixie" ]]; then return 0; fi
      COMPAT_REASON="Proxmox VE Official hanya didukung resmi pada Debian 13 (trixie) ARM64. OS saat ini: $os ($rel)."
      return 1
      ;;
    proxmox-community|pxvirt)
      if [[ "$os" == "debian" && "$rel" == "bookworm" ]]; then return 0; fi
      COMPAT_REASON="Proxmox Community (PXVIRT) hanya didukung pada Debian 12 (bookworm) ARM64. OS saat ini: $os ($rel)."
      return 1
      ;;
    proxmox|proxmox-ve)
      if [[ "$os" == "debian" && ( "$rel" == "bookworm" || "$rel" == "trixie" ) ]]; then return 0; fi
      COMPAT_REASON="Proxmox VE memerlukan Debian base murni (Bookworm untuk PXVIRT atau Trixie untuk Official)."
      return 1
      ;;
    openmediavault|omv)
      if [[ "$os" == "debian" && ( "$rel" == "bookworm" || "$rel" == "trixie" ) ]]; then return 0; fi
      COMPAT_REASON="OpenMediaVault (OMV) hanya kompatibel dengan Debian 12/13 murni. Dilarang dipasang pada Ubuntu ($rel) karena berkonflik keras dengan netplan & pam."
      return 1
      ;;
    homeassistant|ha)
      if [[ "$os" == "debian" && "$rel" =~ ^(bullseye|bookworm|trixie)$ ]]; then return 0; fi
      COMPAT_REASON="Home Assistant Supervised hanya didukung resmi pada Debian (bullseye/bookworm/trixie). OS saat ini: $os ($rel)."
      return 1
      ;;
    casaos)
      if [[ ( "$os" == "debian" && ( "$rel" == "bookworm" || "$rel" == "trixie" ) ) || ( "$os" == "ubuntu" && "$rel" == "jammy" ) ]]; then return 0; fi
      COMPAT_REASON="CasaOS saat ini mendukung Debian 12/13 dan Ubuntu 22.04 (jammy). Belum stabil untuk Ubuntu $rel."
      return 1
      ;;
    docker|portainer|9router|lightnvr|go2rtc|hermes|tailscale|cloudflared)
      return 0
      ;;
    *)
      COMPAT_REASON="Aplikasi tidak dikenal dalam matriks kompatibilitas."
      return 1
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

# --- Action Handlers ---
execute_install() {
  local app="$1"
  detect_system_os
  echo ""
  echo ">>> Memeriksa kompatibilitas sistem untuk '$app'..."
  if ! check_app_compatibility "$app"; then
    echo ""
    printf "%s========================================================================%s\n" "$C_RED" "$C_RESET"
    printf "%s[!] DBAI COMPATIBILITY GUARD: INSTALASI DICEGAH%s\n" "$C_RED" "$C_RESET"
    printf "%s========================================================================%s\n" "$C_RED" "$C_RESET"
    printf "  Aplikasi   : %s\n" "$app"
    printf "  Host OS    : %s (%s) %s\n" "$CURRENT_OS_ID" "$CURRENT_OS_CODENAME" "$CURRENT_ARCH"
    printf "  Penyebab   : %s\n\n" "$COMPAT_REASON"
    printf "Tindakan instalasi dibatalkan otomatis demi menjaga stabilitas sistem.\n"
    printf "%s========================================================================%s\n" "$C_RED" "$C_RESET"
    read -r -p "Tekan [Enter] untuk kembali..."
    return 1
  fi

  echo "✓ Kompatibilitas terverifikasi: $CURRENT_OS_ID ($CURRENT_OS_CODENAME)"
  read -r -p "Apakah Anda yakin ingin memasang $app? (y/N): " confirm
  [[ "${confirm,,}" == "y" ]] || { echo "Instalasi dibatalkan."; return 0; }

  case "$app" in
    tailscale)
      echo "[1/3] Menambahkan repository resmi Tailscale..."
      curl -fsSL "https://pkgs.tailscale.com/stable/debian/${CURRENT_OS_CODENAME}.noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null 2>&1 || true
      printf 'deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian %s main\n' "${CURRENT_OS_CODENAME}" | tee /etc/apt/sources.list.d/tailscale.list >/dev/null
      echo "[2/3] Memperbarui indeks paket dan menginstal tailscale..."
      apt-get update && apt-get install -y tailscale
      echo "[3/3] Mengaktifkan tailscaled.service daemon..."
      systemctl enable --now tailscaled || true
      echo "✓ Tailscale berhasil dipasang! Jalankan 'tailscale up' untuk login."
      ;;
    cloudflared)
      echo "[1/2] Mengunduh binary resmi Cloudflare Tunnel..."
      local arch="arm64"
      case "$CURRENT_ARCH" in aarch64|arm64) arch="arm64" ;; x86_64|amd64) arch="amd64" ;; arm*) arch="arm" ;; esac
      curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o /usr/local/bin/cloudflared
      chmod 755 /usr/local/bin/cloudflared
      echo "[2/2] Verifikasi binary..."
      /usr/local/bin/cloudflared --version || true
      echo "✓ Cloudflare Tunnel terpasang di /usr/local/bin/cloudflared"
      ;;
    portainer)
      if ! command -v docker >/dev/null 2>&1; then
        echo "Docker belum terpasang. Memasang Docker Engine terlebih dahulu..."
        apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      fi
      echo "Menjalankan Portainer CE container..."
      docker run -d -p 9000:9000 -p 9443:9443 --name dbai-portainer --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock -v portainer-data:/data portainer/portainer-ce:latest
      echo "✓ Portainer CE aktif di http://$(hostname -I | awk '{print $1}'):9000"
      ;;
    casaos)
      echo "Menjalankan installer resmi CasaOS..."
      curl -fsSL https://get.casaos.io | bash
      ;;
    proxmox-community|pxvirt)
      echo "Menyiapkan repository Proxmox Community PXVIRT..."
      curl -fsSL https://mirrors.apqa.cn/proxmox/debian/pveport.gpg | tee /etc/apt/trusted.gpg.d/pveport.gpg >/dev/null
      echo "deb [arch=arm64] https://mirrors.apqa.cn/proxmox/debian/pve bookworm port" > /etc/apt/sources.list.d/pxvirt-sources.list
      apt-get update && apt-get install -y pve-manager postfix chrony
      echo "✓ Proxmox Community (PXVIRT) berhasil dipasang!"
      ;;
    proxmox-official)
      echo "Menyiapkan repository Proxmox VE Official untuk Debian Trixie..."
      mkdir -p /etc/apt/sources.list.d
      echo "deb [arch=arm64] https://enterprise.proxmox.com/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
      apt-get update && apt-get install -y pve-manager postfix chrony
      echo "✓ Proxmox VE Official berhasil dipasang!"
      ;;
    *)
      echo "Installer otomatis untuk '$app' belum dikonfigurasi."
      ;;
  esac
  read -r -p "Tekan [Enter] untuk melanjutkan..."
}

# --- Interactive TUI Menu ---
menu_install() {
  while true; do
    detect_system_os
    clear
    printf "%s╔════════════════════════════════════════════════════════════════════════╗%s\n" "$C_CYAN" "$C_RESET"
    printf "%s║                  MENU PENGINSTALAN APLIKASI DBAI                       ║%s\n" "$C_CYAN" "$C_RESET"
    printf "%s║       Host OS: %-15s | Arch: %-8s                         ║%s\n" "$C_CYAN" "$CURRENT_OS_ID ($CURRENT_OS_CODENAME)" "$CURRENT_ARCH" "$C_RESET"
    printf "%s╠════════════════════════════════════════════════════════════════════════╣%s\n" "$C_CYAN" "$C_RESET"
    printf "  Pilih aplikasi yang ingin dipasang:\n\n"

    local -a apps=(
      "proxmox-official"
      "proxmox-community"
      "openmediavault"
      "casaos"
      "portainer"
      "tailscale"
      "cloudflared"
      "homeassistant"
      "hermes"
    )

    local idx=1
    for app in "${apps[@]}"; do
      local label="$app" compat_badge=""
      if check_app_compatibility "$app" >/dev/null 2>&1; then
        compat_badge="${C_GREEN}[✓ Kompatibel]${C_RESET}"
      else
        compat_badge="${C_RED}[✗ Tidak Kompatibel]${C_RESET}"
      fi
      printf "   [%d] %-24s %b\n" "$idx" "$label" "$compat_badge"
      ((idx++))
    done
    printf "\n   [0] Kembali ke Menu Utama\n"
    printf "%s╚════════════════════════════════════════════════════════════════════════╝%s\n" "$C_CYAN" "$C_RESET"
    read -r -p "Pilih nomor aplikasi [0-${#apps[@]}]: " choice
    [[ "$choice" == "0" || -z "$choice" ]] && return 0
    if (( choice >= 1 && choice <= ${#apps[@]} )); then
      local selected="${apps[$((choice - 1))]}"
      execute_install "$selected"
    fi
  done
}

menu_upgrade() {
  clear
  printf "%s╔════════════════════════════════════════════════════════════════════════╗%s\n" "$C_CYAN" "$C_RESET"
  printf "%s║                   MENU PEMBARUAN / UPGRADE APLIKASI                    ║%s\n" "$C_CYAN" "$C_RESET"
  printf "%s╠════════════════════════════════════════════════════════════════════════╣%s\n" "$C_CYAN" "$C_RESET"
  printf "  Memeriksa pembaruan aplikasi...\n\n"
  
  if command -v docker >/dev/null 2>&1; then
    printf "  [Docker Containers]\n"
    for c in dbai-portainer dbai-9router dbai-lightnvr; do
      local st
      st="$(container_state "$c")"
      if [[ "$st" != "absent" ]]; then
        printf "    • %-18s : Terpasang (%s)\n" "$c" "$st"
      fi
    done
  fi
  printf "\n  Pilihan Tindakan Upgrade:\n"
  printf "   [1] Perbarui image container Docker (docker compose pull & restart)\n"
  printf "   [2] Perbarui paket sistem (apt-get update && apt-get upgrade)\n"
  printf "   [0] Kembali ke Menu Utama\n"
  printf "%s╚════════════════════════════════════════════════════════════════════════╝%s\n" "$C_CYAN" "$C_RESET"
  read -r -p "Pilihan Anda: " up_opt
  case "$up_opt" in
    1)
      if [[ -f /opt/dbai/apps/docker-compose.yml ]]; then
        docker compose -f /opt/dbai/apps/docker-compose.yml pull && docker compose -f /opt/dbai/apps/docker-compose.yml up -d
      else
        echo "Docker compose file tidak ditemukan."
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

interactive_main_menu() {
  while true; do
    detect_system_os
    clear
    printf "%s╔════════════════════════════════════════════════════════════════════════╗%s\n" "$C_CYAN" "$C_RESET"
    printf "%s║                  DBAI APPLICATION MANAGER v%s                         ║%s\n" "$C_CYAN" "$DBAI_APPS_VERSION" "$C_RESET"
    printf "%s║       Host OS: %-15s | Arch: %-8s                         ║%s\n" "$C_CYAN" "$CURRENT_OS_ID ($CURRENT_OS_CODENAME)" "$CURRENT_ARCH" "$C_RESET"
    printf "%s╠════════════════════════════════════════════════════════════════════════╣%s\n" "$C_CYAN" "$C_RESET"
    printf "   %-24s %-12s %-15s\n" "APLIKASI" "TIPE" "STATUS"
    printf "   %-24s %-12s %-15s\n" "────────" "────" "──────"

    local app
    for app in proxmox docker portainer openmediavault casaos homeassistant hermes 9router lightnvr tailscale cloudflared; do
      detect_app "$app" >/dev/null 2>&1 || continue
      local col="$C_DIM"
      case "$RESULT_STATUS" in
        running) col="$C_GREEN" ;;
        stopped) col="$C_YELLOW" ;;
      esac
      printf "   %-24s %-12s %b%-15s%b\n" "$RESULT_NAME" "Service" "$col" "$RESULT_STATUS" "$C_RESET"
    done

    printf "%s╠════════════════════════════════════════════════════════════════════════╣%s\n" "$C_CYAN" "$C_RESET"
    printf "  Pilihan Tindakan:\n\n"
    printf "   [1] 📦 Menu Penginstalan Aplikasi (dengan OS Guardrail)\n"
    printf "   [2] 🚀 Menu Pembaruan / Upgrade Aplikasi\n"
    printf "   [3] 🔍 Tampilkan Status Lengkap (dbai-apps list)\n"
    printf "   [0] 🚪 Keluar\n"
    printf "%s╚════════════════════════════════════════════════════════════════════════╝%s\n" "$C_CYAN" "$C_RESET"
    read -r -p "Masukkan pilihan [0-3]: " opt
    case "$opt" in
      1) menu_install ;;
      2) menu_upgrade ;;
      3) print_list; read -r -p "Tekan [Enter] untuk kembali..." ;;
      0|q|exit) clear; exit 0 ;;
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
