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
	case "${DBAI_APP_PROFILE:-}" in
		hermes-9router|hermes-9router-lightnvr)
			case "${ARCH}" in arm64|amd64) ;; *) exit_with_error "Hermes + 9Router profiles require arm64 or amd64; got ${ARCH}" ;; esac
			;;
		lightnvr-go2rtc)
			case "${ARCH}" in arm64|armhf|amd64) ;; *) exit_with_error "LightNVR profile requires arm64, armhf, or amd64; got ${ARCH}" ;; esac
			;;
	esac
	case "${DBAI_APP_PROFILE:-}" in
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
	chroot_sdcard_apt_get_install ca-certificates curl openssl
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
      JWT_SECRET: ${JWT_SECRET:?JWT_SECRET is required}
      INITIAL_PASSWORD: ${INITIAL_PASSWORD:?INITIAL_PASSWORD is required}
      API_KEY_SECRET: ${API_KEY_SECRET:?API_KEY_SECRET is required}
      MACHINE_ID_SALT: ${MACHINE_ID_SALT:?MACHINE_ID_SALT is required}
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
      - ./lightnvr/config:/etc/lightnvr
      - ./lightnvr/data:/var/lib/lightnvr/data

volumes:
  9router-data:
COMPOSE

	# The profile list is supplied explicitly so unrelated containers do not start.
	local compose_profiles=""
	case "${DBAI_APP_PROFILE}" in
		hermes-9router) compose_profiles="hermes-9router" ;;
		lightnvr-go2rtc) compose_profiles="lightnvr-go2rtc" ;;
		hermes-9router-lightnvr) compose_profiles="hermes-9router lightnvr-go2rtc" ;;
	esac
	cat > "${SDCARD}/usr/local/sbin/dbai-apps-start.sh" <<'START'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR=/opt/dbai/apps
ENV_FILE="$APP_DIR/.env"
mkdir -p "$APP_DIR/lightnvr/config" "$APP_DIR/lightnvr/data"
chmod 750 "$APP_DIR" "$APP_DIR/lightnvr" "$APP_DIR/lightnvr/config" "$APP_DIR/lightnvr/data"
if [[ ! -s "$ENV_FILE" ]]; then
  tmp="$(mktemp)"
  {
    printf 'JWT_SECRET=%s\n' "$(openssl rand -hex 32)"
    printf 'INITIAL_PASSWORD=%s\n' "$(openssl rand -hex 12)"
    printf 'API_KEY_SECRET=%s\n' "$(openssl rand -hex 32)"
    printf 'MACHINE_ID_SALT=%s\n' "$(openssl rand -hex 32)"
  } > "$tmp"
  install -o root -g root -m 600 "$tmp" "$ENV_FILE"
  rm -f "$tmp"
  if [[ "${DBAI_COMPOSE_PROFILE:-}" == *"hermes-9router"* ]]; then
    {
      echo "DBAI first-boot app credentials"
      echo "9Router dashboard: http://<device-ip>:20128"
      echo "Initial 9Router password: $(sed -n 's/^INITIAL_PASSWORD=//p' "$ENV_FILE")"
      echo "Change the password immediately after first login."
    } > /root/DBAI-APP-CREDENTIALS.txt
    chmod 600 /root/DBAI-APP-CREDENTIALS.txt
  fi
fi
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
	printf 'DBAI_COMPOSE_PROFILE=%s\n' "${compose_profiles}" > "${SDCARD}/etc/dbai-apps.env"
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
