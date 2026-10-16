# shellcheck shell=bash
# Experimental CasaOS installer extension.
# Use only on supported Debian/Armbian images and validate the result on hardware.

enable_extension "docker-ce"

function extension_prepare_config__dbai_casaos() {
	case "${RELEASE}" in
		bookworm|trixie)
			display_alert "DBAI CasaOS" "Preparing CasaOS on Debian ${RELEASE}" "info"
			;;
		*)
			exit_with_error "DBAI CasaOS extension currently allows bookworm and trixie only; got ${RELEASE}"
			;;
	esac
	case "${ARCH}" in
		arm64|amd64)
			;;
		*)
			exit_with_error "DBAI CasaOS extension requires arm64 or amd64; got ${ARCH}"
			;;
	esac
	EXTRA_IMAGE_SUFFIXES+=("-casaos")
}

function post_repo_customize_image__dbai_install_casaos() {
	display_alert "DBAI CasaOS" "Installing via the upstream CasaOS installer" "warn"
	chroot_sdcard_apt_get_install curl ca-certificates
	chroot_sdcard "bash -lc 'curl --fail --location --silent --show-error https://get.casaos.io | bash'"
}
