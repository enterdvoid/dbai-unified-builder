# shellcheck shell=bash
# Optional custom kernel bundle overlay. One outer tar contains four inner archives.
# Inner archive paths are rooted at the target filesystem (boot/, lib/, usr/).

# Shared classifier used by the installer and the workflow's preflight check.
# UAPI-only archives contain just include/ and are NOT kernel build headers.
function dbai_detect_kernel_headers_layout() {
	local listing_file="${1:-}"
	[[ -n "${listing_file}" && -f "${listing_file}" ]] || return 1

	if grep -Eq '^([.]/)?(usr/src/|lib/modules/[^/]+/build)' "${listing_file}"; then
		printf 'target-root\n'
		return 0
	fi
	if grep -Eq '^([.]/)?include/' "${listing_file}" && grep -Eq '^([.]/)?Makefile$' "${listing_file}"; then
		printf 'header-root\n'
		return 0
	fi
	if grep -Eq '^([.]/)?include/' "${listing_file}" && ! grep -Eq '^([.]/)?Makefile$' "${listing_file}" && awk '
		{
			path=$0
			sub(/^\.\//, "", path)
			if (path=="." || path=="" || path=="include" || path ~ /^include\//) next
			bad=1
		}
		END { exit bad }
	' "${listing_file}"; then
		printf 'uapi-root\n'
		return 0
	fi
	return 1
}


# Remove distro-kernel artifacts left by the Armbian base image after the
# custom kernel overlay has been installed. Keep only the module tree whose
# release was derived from the validated custom bundle.
function dbai_prune_noncustom_kernel_artifacts() {
	local target_root="$1" custom_release="$2" modules_root entry name stray
	[[ -n "$target_root" && -d "$target_root" ]] || return 1
	[[ "$custom_release" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1

	for modules_root in "$target_root/lib/modules" "$target_root/usr/lib/modules"; do
		# Never follow an absolute /usr/lib/modules symlink out of the image root.
		[[ -L "$modules_root" ]] && continue
		[[ -d "$modules_root" ]] || continue
		for entry in "$modules_root"/*; do
			[[ -e "$entry" || -L "$entry" ]] || continue
			name="$(basename "$entry")"
			[[ "$name" == "$custom_release" ]] && continue
			echo "Removing non-custom kernel modules: $(realpath --relative-to="$target_root" "$entry")"
			rm -rf -- "$entry"
		done
	done

	for entry in "$target_root/usr/src"/linux-headers-* "$target_root/usr/src"/linux-uapi-headers-*; do
		[[ -e "$entry" || -L "$entry" ]] || continue
		name="$(basename "$entry")"
		case "$name" in
			"linux-headers-$custom_release"|"linux-uapi-headers-$custom_release") continue ;;
		esac
		echo "Removing non-custom kernel headers: $(realpath --relative-to="$target_root" "$entry")"
		rm -rf -- "$entry"
	done

	for entry in "$target_root/usr/lib"/linux-image-*; do
		[[ -e "$entry" || -L "$entry" ]] || continue
		name="$(basename "$entry")"
		[[ "$name" == "linux-image-$custom_release" ]] && continue
		echo "Removing distro kernel image payload: $(realpath --relative-to="$target_root" "$entry")"
		rm -rf -- "$entry"
	done

	# The release directory belongs under /lib/modules, never at image root.
	stray="$target_root/$custom_release"
	if [[ -d "$stray" ]]; then
		if find "$stray" -mindepth 1 -print -quit | grep -q .; then
			echo "ERROR: Unexpected non-empty kernel-release directory at image root: /$custom_release" >&2
			return 1
		fi
		rmdir -- "$stray"
		echo "Removed empty root-level kernel-release directory: /$custom_release"
	fi
}

# Resolve the module release from the archive itself. The preflight workflow and
# installer share this parser so filenames match the modules actually overlaid.
function dbai_detect_kernel_modules_release() {
	local listing_file="${1:-}"
	local release=""
	[[ -n "${listing_file}" && -f "${listing_file}" ]] || return 1

	if grep -Eq '^([.]/)?lib/modules/[^/]+/' "${listing_file}"; then
		release="$(sed -nE 's#^([.]/)?lib/modules/([^/]+)/.*#\2#p' "${listing_file}" | head -n 1)"
	else
		release="$(sed -nE 's#^([.]/)?([^/]+)/modules[.]dep$#\2#p; s#^([.]/)?([^/]+)/kernel/.*#\2#p' "${listing_file}" | head -n 1)"
	fi
	[[ -n "${release}" && "${release}" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
	printf '%s\n' "${release}"
}
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
	# Accept either a target-root archive (lib/modules/<release>/...) or
	# a module-tree archive whose top-level directory is the kernel release
	# (for example 6.1.66-DBAI/modules.dep and 6.1.66-DBAI/kernel/...).
	local modules_layout="target-root"
	if ! grep -Eq '^([.]/)?lib/modules/[^/]+/' "${modules_listing}"; then
		if grep -Eq '^([.]/)?[^/]+/modules[.]dep$|^([.]/)?[^/]+/kernel/' "${modules_listing}"; then
			modules_layout="release-root"
		else
			echo "First modules archive entries:"
			sed -n '1,40p' "${modules_listing}"
			exit_with_error "modules-<version> archive must contain lib/modules/<kernel-release>/ or a top-level <kernel-release>/ module tree"
		fi
	fi
	local headers_listing="${cache_dir}/headers-list.txt"
	tar -tf "${cache_dir}/headers.tar" > "${headers_listing}" || exit_with_error "Unable to read headers archive file list"
	local headers_layout
	headers_layout="$(dbai_detect_kernel_headers_layout "${headers_listing}")" || {
		echo "First headers archive entries:"
		sed -n '1,40p' "${headers_listing}"
		exit_with_error "header-<version> archive must contain a kernel build tree or only a root include/ UAPI tree"
	}
	local modules_release=""
	modules_release="$(dbai_detect_kernel_modules_release "${modules_listing}")" || exit_with_error "Unable to safely determine kernel release from modules archive"

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
	# The supplied DBAI modules archive stores the kernel-release directory
	# at archive root. Normalize it into the standard target /lib/modules path.
	if [[ "${modules_layout}" == "release-root" ]]; then
		tar --no-same-owner --no-same-permissions --transform='s,^[.]/,,;s,^\([^/][^/]*\)/,lib/modules/\1/,' -xf "${cache_dir}/modules.tar" -C "${SDCARD}"
	else
		tar --no-same-owner --no-same-permissions -xf "${cache_dir}/modules.tar" -C "${SDCARD}"
	fi
	case "${headers_layout}" in
		header-root)
			mkdir -p "${SDCARD}/usr/src/linux-headers-${modules_release}"
			tar --no-same-owner --no-same-permissions --transform="s,^[.]/,,;s,^,usr/src/linux-headers-${modules_release}/," -xf "${cache_dir}/headers.tar" -C "${SDCARD}"
			;;
		target-root)
			tar --no-same-owner --no-same-permissions -xf "${cache_dir}/headers.tar" -C "${SDCARD}"
			;;
		uapi-root)
			# This bundle contains exported userspace ABI headers, not a kernel build tree.
			# Preserve them separately so they cannot overwrite distro /usr/include files
			# or be mistaken for valid /lib/modules/<release>/build headers.
			mkdir -p "${SDCARD}/usr/src/linux-uapi-headers-${modules_release}"
			tar --no-same-owner --no-same-permissions --transform="s,^[.]/,,;s,^,usr/src/linux-uapi-headers-${modules_release}/," -xf "${cache_dir}/headers.tar" -C "${SDCARD}"
			;;
	esac
	mkdir -p "${SDCARD}/lib/modules/${modules_release}" "${SDCARD}/usr/src"
	if [[ "${headers_layout}" == "uapi-root" ]]; then
		# The module archive can include dangling links to a missing build tree.
		[[ ! -L "${SDCARD}/lib/modules/${modules_release}/build" ]] || rm -f "${SDCARD}/lib/modules/${modules_release}/build"
		[[ ! -L "${SDCARD}/lib/modules/${modules_release}/source" ]] || rm -f "${SDCARD}/lib/modules/${modules_release}/source"
	elif [[ -d "${SDCARD}/usr/src/linux-headers-${modules_release}" ]]; then
		ln -sfn "/usr/src/linux-headers-${modules_release}" "${SDCARD}/lib/modules/${modules_release}/build"
		ln -sfn "/usr/src/linux-headers-${modules_release}" "${SDCARD}/lib/modules/${modules_release}/source"
	fi

	find "${SDCARD}/boot" -maxdepth 4 -type f \( -name 'Image' -o -name 'Image-*' -o -name 'vmlinuz*' -o -name 'uImage' -o -name 'zImage' \) -print -quit | grep -q . || exit_with_error "No recognizable kernel image found under target /boot after overlay"
	find "${SDCARD}/boot" -type f -name '*.dtb' -print -quit | grep -q . || exit_with_error "No DTB found under target /boot after overlay"
	find "${SDCARD}/lib/modules" -type f -name '*.ko*' -print -quit | grep -q . || exit_with_error "No kernel module found under target /lib/modules after overlay"
	if [[ "${headers_layout}" == "uapi-root" ]]; then
		find "${SDCARD}/usr/src/linux-uapi-headers-${modules_release}/include" -type f -print -quit | grep -q . || exit_with_error "UAPI header archive did not install any files"
	else
		find "${SDCARD}/usr/src" -type f -name 'Makefile' -print -quit | grep -q . || exit_with_error "No kernel header Makefile found under target /usr/src after overlay"
	fi

	# Purge official-kernel leftovers only after the custom modules were overlaid.
	dbai_prune_noncustom_kernel_artifacts "$SDCARD" "$modules_release" || exit_with_error "Unable to clean non-custom kernel artifacts from the image"

	local manifest="${SDCARD}/etc/dbai-custom-kernel-manifest.txt"
	mkdir -p "${SDCARD}/etc"
	{
		echo "Kernel mode: Custom Kernel"
		echo "Kernel release: ${modules_release}"
		echo "Modules path: /lib/modules/${modules_release}"
		echo "Bundle URL: ${DBAI_KERNEL_BUNDLE_URL}"
		echo "Overlay timestamp UTC: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
		echo "Inner archive SHA-256:"
		echo "Headers archive layout: ${headers_layout}"
		if [[ "${headers_layout}" == "uapi-root" ]]; then
			echo "Header capability: exported userspace UAPI headers only; kernel build headers/Makefile are not included."
		fi
		sha256sum "${cache_dir}/boot.tar" "${cache_dir}/dtb.tar" "${cache_dir}/modules.tar" "${cache_dir}/headers.tar"
	} > "${manifest}"
	[[ -s "${manifest}" ]] || exit_with_error "Custom-kernel manifest was not written to target /etc"
	display_alert "DBAI custom kernel" "Manifest written to /etc/dbai-custom-kernel-manifest.txt; bundle overlay checks completed, hardware boot testing still required" "warn"
}
