# shellcheck shell=bash
# Optional custom kernel bundle overlay. One outer tar contains four inner archives.
# Inner archive paths are rooted at the target filesystem (boot/, lib/, usr/).

function extension_prepare_config__dbai_custom_kernel() {
	if [[ "${DBAI_KERNEL_MODE:-}" != "Custom Kernel" ]]; then
		exit_with_error "dbai-custom-kernel extension was enabled while DBAI_KERNEL_MODE is not Custom Kernel"
	fi
	if [[ -z "${DBAI_KERNEL_BUNDLE_URL:-}" || ! "${DBAI_KERNEL_BUNDLE_URL}" =~ ^https:// ]]; then
		exit_with_error "Custom Kernel requires one HTTPS URL to a bundle archive"
	fi
	EXTRA_IMAGE_SUFFIXES+=("-custom-kernel")
}

function pre_customize_image__dbai_overlay_kernel_bundle() {
	: "${SDCARD:?Armbian did not set SDCARD for custom kernel overlay}"
	local cache_dir="${SRC}/cache/dbai-custom-kernel"
	local bundle_dir="${cache_dir}/bundle"
	mkdir -p "${bundle_dir}"
	local bundle="${cache_dir}/kernel-bundle.tar"

	display_alert "DBAI custom kernel" "Downloading single kernel bundle" "info"
	curl --fail --location --silent --show-error --retry 3 "${DBAI_KERNEL_BUNDLE_URL}" --output "${bundle}"
	tar -tf "${bundle}" >/dev/null 2>&1 || exit_with_error "Custom kernel bundle is not a valid .tar.gz/.tar.xz archive"
	if ! tar -tf "${bundle}" | awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }'; then
		exit_with_error "Unsafe absolute or parent-traversal path found in custom kernel bundle"
	fi
	rm -rf "${bundle_dir}"
	mkdir -p "${bundle_dir}"
	tar --no-same-owner --no-same-permissions -xf "${bundle}" -C "${bundle_dir}"

	local prefixes=("boot-" "dtb-amlogic-" "modules-" "header-")
	local labels=("boot" "dtb" "modules" "headers")
	local i matches archive
	for i in "${!labels[@]}"; do
		mapfile -t matches < <(find "${bundle_dir}" -type f \( -name "${prefixes[$i]}*.tar.gz" -o -name "${prefixes[$i]}*.tar.xz" \) -print)
		if [[ "${#matches[@]}" -ne 1 ]]; then
			exit_with_error "Bundle must contain exactly one ${prefixes[$i]}<version>.tar.gz or .tar.xz archive"
		fi
		archive="${cache_dir}/${labels[$i]}.tar"
		cp "${matches[0]}" "${archive}"
		tar -tf "${archive}" >/dev/null 2>&1 || exit_with_error "Inner ${labels[$i]} archive is invalid"
		if ! tar -tf "${archive}" | awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }'; then
			exit_with_error "Unsafe path in inner ${labels[$i]} archive"
		fi
	done

	if ! tar -tf "${cache_dir}/boot.tar" | grep -Eq '^(boot/.*|(\./)?(Image[^/]*|vmlinuz[^/]*|uImage|zImage|initrd[^/]*|uInitrd)(/|$))'; then
		exit_with_error "boot-<version> archive must contain files under boot/ or a recognizable kernel image at its archive root"
	fi
	local dtb_listing="${cache_dir}/dtb-list.txt"
	tar -tf "${cache_dir}/dtb.tar" > "${dtb_listing}" || exit_with_error "Unable to read DTB archive file list"
	grep -Eq '(^|/)[^/]+[.]dtb' "${dtb_listing}" || exit_with_error "dtb-amlogic-<version> archive must contain at least one .dtb file"
	local modules_listing="${cache_dir}/modules-list.txt"
	tar -tf "${cache_dir}/modules.tar" > "${modules_listing}" || exit_with_error "Unable to read modules archive file list"
	if ! grep -Eq '^([.]/)?lib/modules/[^/]+/' "${modules_listing}"; then
		echo "First modules archive entries:"
		sed -n '1,40p' "${modules_listing}"
		exit_with_error "modules-<version> archive must contain lib/modules/<kernel-release>/"
	fi
	local headers_listing="${cache_dir}/headers-list.txt"
	tar -tf "${cache_dir}/headers.tar" > "${headers_listing}" || exit_with_error "Unable to read headers archive file list"
	if ! grep -Eq '^([.]/)?(usr/src/|lib/modules/[^/]+/build)' "${headers_listing}"; then
		echo "First headers archive entries:"
		sed -n '1,40p' "${headers_listing}"
		exit_with_error "header-<version> archive must contain usr/src/ or matching modules build paths"
	fi

	# Replace default boot scripts/config before applying the kernel bundle's /boot files.
	dbai_replace_bootfs_files

	# Some kernel bundles store boot archive entries directly at the boot-partition root
	# (for example Image and uInitrd) instead of prefixing every entry with boot/.
	# Normalize those entries into /boot; preserve archives already rooted at boot/.
	if tar -tf "${cache_dir}/boot.tar" | grep -Eq '^boot/'; then
		tar --no-same-owner --no-same-permissions -xf "${cache_dir}/boot.tar" -C "${SDCARD}"
	else
		tar --no-same-owner --no-same-permissions --transform='s,^[.]/,,;s,^,boot/,' -xf "${cache_dir}/boot.tar" -C "${SDCARD}"
	fi
	# Normalize common DTB archive layouts into the target /boot/dtb tree.
	local dtb_stage="${cache_dir}/dtb-unpacked"
	rm -rf "${dtb_stage}"
	mkdir -p "${dtb_stage}"
	tar --no-same-owner --no-same-permissions -xf "${cache_dir}/dtb.tar" -C "${dtb_stage}"
	local dtb_file dtb_rel dtb_target
	while IFS= read -r -d '' dtb_file; do
		dtb_rel="${dtb_file#"${dtb_stage}/"}"
		while [[ "${dtb_rel}" == ./* ]]; do dtb_rel="${dtb_rel#./}"; done
		case "/${dtb_rel}" in
			*/boot/*) dtb_target="${SDCARD}/${dtb_rel}" ;;
			*/dtb/*) dtb_target="${SDCARD}/boot/dtb/${dtb_rel#dtb/}" ;;
			*/amlogic/*) dtb_target="${SDCARD}/boot/dtb/${dtb_rel#./}" ;;
			*) dtb_target="${SDCARD}/boot/dtb/amlogic/${dtb_rel##*/}" ;;
		esac
		mkdir -p "$(dirname "${dtb_target}")"
		cp -f "${dtb_file}" "${dtb_target}"
	done < <(find "${dtb_stage}" -type f -name '*.dtb' -print0)
	find "${SDCARD}/boot" -type f -name '*.dtb' -print -quit | grep -q . || exit_with_error "DTB archive contained .dtb files, but none were installed under target /boot"
	for archive in "${cache_dir}/modules.tar" "${cache_dir}/headers.tar"; do
		tar --no-same-owner --no-same-permissions -xf "${archive}" -C "${SDCARD}"
	done

	find "${SDCARD}/boot" -maxdepth 4 -type f \( -name 'Image' -o -name 'Image-*' -o -name 'vmlinuz*' -o -name 'uImage' -o -name 'zImage' \) -print -quit | grep -q . || exit_with_error "No recognizable kernel image found under target /boot after overlay"
	find "${SDCARD}/boot" -type f -name '*.dtb' -print -quit | grep -q . || exit_with_error "No DTB found under target /boot after overlay"
	find "${SDCARD}/lib/modules" -type f -name '*.ko*' -print -quit | grep -q . || exit_with_error "No kernel module found under target /lib/modules after overlay"
	find "${SDCARD}/usr/src" -type f -name 'Makefile' -print -quit | grep -q . || exit_with_error "No kernel header Makefile found under target /usr/src after overlay"

	local manifest="${SDCARD}/root/DBAI-CUSTOM-KERNEL-MANIFEST.txt"
	mkdir -p "${SDCARD}/root"
	{
		echo "Kernel mode: Custom Kernel"
		echo "Bundle URL: ${DBAI_KERNEL_BUNDLE_URL}"
		echo "Overlay timestamp UTC: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
		echo "Inner archive SHA-256:"
		sha256sum "${cache_dir}/boot.tar" "${cache_dir}/dtb.tar" "${cache_dir}/modules.tar" "${cache_dir}/headers.tar"
	} > "${manifest}"
	display_alert "DBAI custom kernel" "Four-part bundle overlay and basic checks completed; hardware boot testing is still required" "warn"
}
