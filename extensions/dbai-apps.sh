# DBAI app profile: Docker-based apps plus optional Hermes first-boot installer.
# The Docker extension installs the daemon and Compose plugin into the target image.
# Hermes requires interactive provider setup after first boot; never bake API credentials into firmware.

# shellcheck shell=bash
enable_extension "docker-ce"

function extension_prepare_config__dbai_apps() {
	case "${RELEASE}" in
		bookworm|trixie)
			;;
		*)
			exit_with_error "DBAI Docker app profiles currently support bookworm and trixie only; got ${RELEASE}"
			;;
	esac
	case "${DBAI_APP_PROFILE:-docker}" in
		docker|"")
			;;
		hermes-9router|hermes-9router-lightnvr)
			case "${ARCH}" in arm64|amd64) ;; *) exit_with_error "Hermes + 9Router profiles require arm64 or amd64; got ${ARCH}" ;; esac
			;;
		lightnvr-go2rtc)
			case "${ARCH}" in arm64|armhf|amd64) ;; *) exit_with_error "LightNVR profile requires arm64, armhf, or amd64; got ${ARCH}" ;; esac
			;;
	esac
	case "${DBAI_APP_PROFILE:-docker}" in
		docker|"")
			local idx found=no
			for idx in "${!EXTRA_IMAGE_SUFFIXES[@]}"; do
				if [[ "${EXTRA_IMAGE_SUFFIXES[idx]}" == "-docker" ]]; then
					EXTRA_IMAGE_SUFFIXES[idx]="-docker+portainer"
					found=yes
				fi
			done
			[[ "$found" == "yes" ]] || EXTRA_IMAGE_SUFFIXES+=("-docker+portainer")
			;;
		hermes-9router|lightnvr-go2rtc|hermes-9router-lightnvr)
			EXTRA_IMAGE_SUFFIXES+=("-${DBAI_APP_PROFILE}")
			;;
		*)
			exit_with_error "dbai-apps extension does not recognize DBAI_APP_PROFILE=${DBAI_APP_PROFILE:-unset}"
			;;
	esac
}

function pre_customize_image__dbai_stage_docker_apps() {
	: "${SDCARD:?Armbian did not set SDCARD for DBAI app staging}"
	chroot_sdcard_apt_get_install ca-certificates curl

	# Install Tailscale & Cloudflare Tunnel for secure remote management
	mkdir -p "${SDCARD}/usr/share/keyrings" "${SDCARD}/etc/apt/sources.list.d" "${SDCARD}/usr/local/bin"
	curl -fsSL "https://pkgs.tailscale.com/stable/debian/${RELEASE}.noarmor.gpg" -o "${SDCARD}/usr/share/keyrings/tailscale-archive-keyring.gpg" 2>/dev/null || true
	if [[ -f "${SDCARD}/usr/share/keyrings/tailscale-archive-keyring.gpg" ]]; then
		printf 'deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian %s main\n' "${RELEASE}" > "${SDCARD}/etc/apt/sources.list.d/tailscale.list"
		chroot_sdcard apt-get update 2>/dev/null || true
		chroot_sdcard_apt_get_install tailscale || true
	fi

	local cf_arch="arm64"
	case "${ARCH}" in
		arm64) cf_arch="arm64" ;;
		amd64) cf_arch="amd64" ;;
		armhf|arm) cf_arch="arm" ;;
	esac
	curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}" -o "${SDCARD}/usr/local/bin/cloudflared" 2>/dev/null || true
	if [[ -s "${SDCARD}/usr/local/bin/cloudflared" ]]; then
		chmod 755 "${SDCARD}/usr/local/bin/cloudflared"
	fi
	local app_dir="${SDCARD}/opt/dbai/apps"
	mkdir -p "${app_dir}" "${SDCARD}/usr/local/sbin" "${SDCARD}/etc/systemd/system" "${SDCARD}/var/lib/dbai"
	chmod 755 "${app_dir}"

	cat > "${app_dir}/docker-compose.yml" <<'COMPOSE'
services:
  9router:
    image: ghcr.io/decolua/9router:0.5.95
    container_name: dbai-9router
    profiles: ["hermes-9router"]
    restart: unless-stopped
    ports:
      - "20128:20128"
    environment:
      NODE_ENV: production
      PORT: "20128"
      HOSTNAME: 0.0.0.0
      DATA_DIR: /app/data
    volumes:
      - 9router-data:/app/data

  lightnvr:
    image: ghcr.io/opensensor/lightnvr:0.37.2
    container_name: dbai-lightnvr
    profiles: ["lightnvr-go2rtc"]
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "8554:8554"
      - "8555:8555"
      - "8555:8555/udp"
      - "1984:1984"
    environment:
      TZ: Asia/Jakarta
      GO2RTC_CONFIG_PERSIST: "true"
    volumes:
      - lightnvr-config:/etc/lightnvr
      - lightnvr-data:/var/lib/lightnvr/data

  portainer:
    image: portainer/portainer-ce:latest
    container_name: dbai-portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer-data:/data

volumes:
  9router-data:
  lightnvr-config:
  lightnvr-data:
  portainer-data:
COMPOSE

	# The profile list is supplied explicitly so unrelated containers do not start.
	local compose_profiles=""
	case "${DBAI_APP_PROFILE:-docker}" in
		docker|"") compose_profiles="" ;;
		hermes-9router) compose_profiles="hermes-9router" ;;
		lightnvr-go2rtc) compose_profiles="lightnvr-go2rtc" ;;
		hermes-9router-lightnvr) compose_profiles="hermes-9router lightnvr-go2rtc" ;;
	esac
	cat > "${SDCARD}/usr/local/sbin/dbai-apps-start.sh" <<'START'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR=/opt/dbai/apps
mkdir -p "$APP_DIR"
chmod 750 "$APP_DIR"
read -r -a selected_profiles <<< "${DBAI_COMPOSE_PROFILE}"
profile_args=()
for profile in "${selected_profiles[@]}"; do
  profile_args+=(--profile "$profile")
done
docker compose --project-directory "$APP_DIR" "${profile_args[@]}" -f "$APP_DIR/docker-compose.yml" up -d
START
	chmod 755 "${SDCARD}/usr/local/sbin/dbai-apps-start.sh"

	cat > "${SDCARD}/usr/local/sbin/dbai-apps-stop.sh" <<'STOP'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR=/opt/dbai/apps
read -r -a selected_profiles <<< "${DBAI_COMPOSE_PROFILE}"
profile_args=()
for profile in "${selected_profiles[@]}"; do
  profile_args+=(--profile "$profile")
done
docker compose --project-directory "$APP_DIR" "${profile_args[@]}" -f "$APP_DIR/docker-compose.yml" down
STOP
	chmod 755 "${SDCARD}/usr/local/sbin/dbai-apps-stop.sh"

	# Store selected Compose profiles in a root-only environment file.
	printf 'DBAI_COMPOSE_PROFILE="%s"\n' "${compose_profiles}" > "${SDCARD}/etc/dbai-apps.env"
	chmod 600 "${SDCARD}/etc/dbai-apps.env"

	cat > "${SDCARD}/etc/systemd/system/dbai-apps.service" <<'UNIT'
[Unit]
Description=DBAI preconfigured Docker applications
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=/etc/dbai-apps.env
ExecStart=/usr/local/sbin/dbai-apps-start.sh
ExecStop=/usr/local/sbin/dbai-apps-stop.sh
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT
	mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	ln -sf ../dbai-apps.service "${SDCARD}/etc/systemd/system/multi-user.target.wants/dbai-apps.service"

	if [[ "${DBAI_APP_PROFILE}" == "hermes-9router" || "${DBAI_APP_PROFILE}" == "hermes-9router-lightnvr" ]]; then
		cat > "${SDCARD}/usr/local/sbin/dbai-hermes-firstboot.sh" <<'HERMES'
#!/usr/bin/env bash
set -euo pipefail
exec >> /var/log/dbai-hermes-firstboot.log 2>&1
mkdir -p /var/lib/dbai
if command -v hermes >/dev/null 2>&1; then
  touch /var/lib/dbai/hermes-install-complete
  exit 0
fi
echo "Installing Hermes Agent from the official installer; model/provider setup is still required."
curl --fail --location --silent --show-error https://hermes-agent.nousresearch.com/install.sh -o /tmp/dbai-hermes-install.sh
bash /tmp/dbai-hermes-install.sh
command -v hermes >/dev/null 2>&1
touch /var/lib/dbai/hermes-install-complete
systemctl disable dbai-hermes-firstboot.service || true
HERMES
		chmod 755 "${SDCARD}/usr/local/sbin/dbai-hermes-firstboot.sh"
		cat > "${SDCARD}/etc/systemd/system/dbai-hermes-firstboot.service" <<'UNIT'
[Unit]
Description=Install Hermes Agent on first boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/dbai/hermes-install-complete

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/dbai-hermes-firstboot.sh
Restart=on-failure
RestartSec=60
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT
		ln -sf ../dbai-hermes-firstboot.service "${SDCARD}/etc/systemd/system/multi-user.target.wants/dbai-hermes-firstboot.service"
	fi

	display_alert "DBAI app profile" "Docker Compose files staged; runtime install/health checks are required on first boot" "warn"
}
