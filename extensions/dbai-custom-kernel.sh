# Optional DBAI four-part kernel overlay.
# Inputs are HTTPS URLs to tar archives with paths rooted at the target filesystem.

function extension_prepare_config__dbai_custom_kernel() {
	if [[ "${DBAI_KERNEL_MODE:-official}" != "custom-four-part" ]]; then
		exit_with_error "dbai-custom-kernel extension was enabled while DBAI_KERNEL_MODE is not custom-four-part"
	fi
	for variable in DBAI_KERNEL_BOOT_URL DBAI_KERNEL_DTB_URL DBAI_KERNEL_MODULES_URL DBAI_KERNEL_HEADERS_URL; do
		if [[ -z "${!variable:-}" ]]; then
			exit_with_error "Custom kernel mode requires all four archive URLs; missing ${variable}"
		fi
		if [[ ! "${!variable}" =~ ^https:// ]]; then
			exit_with_error "${variable} must be an HTTPS URL"
		fi
	done
	EXTRA_IMAGE_SUFFIXES+=("-custom-kernel")
}

function pre_customize_image__dbai_overlay_four_part_kernel() {
	: "${SDCARD:?Armbian did not set SDCARD for custom kernel overlay}"
	local cache_dir="${SRC}/cache/dbai-custom-kernel"
	mkdir -p "${cache_dir}"

	local names=("boot" "dtb" "modules" "headers")
	local urls=("${DBAI_KERNEL_BOOT_URL}" "${DBAI_KERNEL_DTB_URL}" "${DBAI_KERNEL_MODULES_URL}" "${DBAI_KERNEL_HEADERS_URL}")
	local i archive
	for i in "${!names[@]}"; do
		archive="${cache_dir}/${names[$i]}.tar"
		display_alert "DBAI custom kernel" "Downloading ${names[$i]} archive" "info"
		curl --fail --location --silent --show-error --retry 3 "${urls[$i]}" --output "${archive}"
		if ! tar -tf "${archive}" >/dev/null 2>&1; then
			exit_with_error "Custom kernel ${names[$i]} input is not a readable tar archive"
		fi
		if tar -tf "${archive}" | awk 'BEGIN { bad=0 } /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }'; then
			:
		else
			exit_with_error "Unsafe absolute or parent-traversal path found in ${names[$i]} archive"
		fi
	done

	# Verify each archive's intended destination before extraction.
	tar -tf "${cache_dir}/boot.tar" | grep -Eq '^boot/' || exit_with_error "Boot archive must contain paths rooted at boot/"
	tar -tf "${cache_dir}/dtb.tar" | grep -Eq '^boot/.*\.dtb$' || exit_with_error "DTB archive must contain at least one .dtb under boot/"
	tar -tf "${cache_dir}/modules.tar" | grep -Eq '^lib/modules/[^/]+/' || exit_with_error "Modules archive must contain lib/modules/<kernel-release>/"
	tar -tf "${cache_dir}/headers.tar" | grep -Eq '^(usr/src/|lib/modules/[^/]+/build)' || exit_with_error "Headers archive must contain usr/src/ or matching lib/modules/<release>/build paths"

	for archive in "${cache_dir}/boot.tar" "${cache_dir}/dtb.tar" "${cache_dir}/modules.tar" "${cache_dir}/headers.tar"; do
		tar --no-same-owner --no-same-permissions -xf "${archive}" -C "${SDCARD}"
	done

	find "${SDCARD}/boot" -maxdepth 3 -type f \( -name 'Image' -o -name 'Image-*' -o -name 'vmlinuz*' -o -name 'uImage' -o -name 'zImage' \) -print -quit | grep -q . || exit_with_error "No recognizable kernel image found under target /boot after overlay"
	find "${SDCARD}/boot" -type f -name '*.dtb' -print -quit | grep -q . || exit_with_error "No DTB found under target /boot after overlay"
	find "${SDCARD}/lib/modules" -type f -name '*.ko*' -print -quit | grep -q . || exit_with_error "No kernel module found under target /lib/modules after overlay"
	find "${SDCARD}/usr/src" -type f -name 'Makefile' -print -quit | grep -q . || exit_with_error "No kernel header Makefile found under target /usr/src after overlay"

	local manifest="${SDCARD}/root/DBAI-CUSTOM-KERNEL-MANIFEST.txt"
	mkdir -p "${SDCARD}/root"
	{
		echo "Kernel mode: custom-four-part"
		echo "Overlay timestamp UTC: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
		echo "Archive SHA-256:"
		sha256sum "${cache_dir}/boot.tar" "${cache_dir}/dtb.tar" "${cache_dir}/modules.tar" "${cache_dir}/headers.tar"
	} > "${manifest}"
	display_alert "DBAI custom kernel" "Four-part overlay and basic checks completed; hardware boot testing is still required" "warn"
}
