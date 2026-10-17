#!/usr/bin/env bash
# @description Builds a lightweight standalone Openbox X11 session with a graphical login, LXPanel application menu, PCManFM file manager, terminal, and NetworkManager tray. Used by the DBAI unified builder as a standalone window-manager variant rather than an Armbian configng desktop environment.

function extension_prepare_config__openbox() {
	case "${RELEASE}" in
		bullseye|bookworm|trixie|forky|jammy|noble|resolute)
			display_alert "Target image will have the lightweight Openbox window manager" "${RELEASE} ${EXTENSION}" "info"
			;;
		*)
			exit_with_error "Openbox WM is not configured for ${DISTRIBUTION} ${RELEASE}"
			;;
	esac

	EXTRA_IMAGE_SUFFIXES+=("-openbox")
}

function post_repo_customize_image__install_openbox_session() {
	display_alert "Installing Openbox standalone graphical session" "${EXTENSION}" "info"

	local network_applet_pkg="network-manager-gnome"
	if [[ "${RELEASE}" == "forky" ]]; then
		network_applet_pkg="network-manager-applet"
	fi

	chroot_sdcard_apt_get_install \
		dbus-x11 \
		fonts-dejavu-core \
		lightdm \
		lightdm-gtk-greeter \
		lxappearance \
		lxpanel \
		lxpolkit \
		lxterminal \
		"${network_applet_pkg}" \
		openbox \
		pcmanfm \
		x11-xserver-utils \
		xinit \
		xserver-xorg

	run_host_command_logged mkdir -p "${SDCARD}/etc/xdg/openbox"
	run_host_command_logged cat <<'OPENBOX_AUTOSTART' > "${SDCARD}/etc/xdg/openbox/autostart"
# DBAI Openbox standalone session
if command -v lxpanel >/dev/null 2>&1; then
	lxpanel --profile default &
fi
if command -v pcmanfm >/dev/null 2>&1; then
	pcmanfm --desktop --profile=openbox &
fi
if command -v lxpolkit >/dev/null 2>&1; then
	lxpolkit &
fi
if command -v nm-applet >/dev/null 2>&1; then
	nm-applet --indicator &
fi
OPENBOX_AUTOSTART
	run_host_command_logged chmod 0644 "${SDCARD}/etc/xdg/openbox/autostart"

	firstlogin_script="${SDCARD}/usr/lib/armbian/armbian-firstlogin"
	if [[ ! -f "${firstlogin_script}" ]]; then
		exit_with_error "Armbian first-login script not found at ${firstlogin_script}; cannot configure Openbox as the default session"
	fi
	run_host_command_logged python3 - "${firstlogin_script}" <<'OPENBOX_FIRSTLOGIN_PATCH'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = 'ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service'
block = """# Select Openbox for the DBAI standalone Openbox image.
[[ -x $(command -v openbox-session) ]] && sed -i "s/user-session.*/user-session=openbox/" /etc/lightdm/lightdm.conf.d/11-armbian.conf
[[ -x $(command -v openbox-session) ]] && sed -i "s/user-session.*/user-session=openbox/" /etc/lightdm/lightdm.conf.d/22-armbian-autologin.conf

"""
if "Select Openbox for the DBAI standalone Openbox image." not in text:
    if marker not in text:
        raise SystemExit(f"Expected LightDM setup marker not found in {path}")
    text = text.replace(marker, block + marker, 1)
    path.write_text(text, encoding="utf-8")
    print(f"Configured Openbox first-login session in {path}")
else:
    print(f"Openbox first-login patch already present in {path}")
OPENBOX_FIRSTLOGIN_PATCH

	display_alert "Openbox session installed; Armbian first-login now selects Openbox in LightDM" "${EXTENSION}" "info"
}
