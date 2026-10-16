# shellcheck shell=bash
# Replace default /boot files for the two custom-kernel modes.

function extension_prepare_config__dbai_custom_bootfs() {
	case "${DBAI_KERNEL_MODE:-}" in
		"Custom Kernel"|"Recompile Custom Kernel") ;;
		*) exit_with_error "dbai-custom-bootfs is only valid with Custom Kernel or Recompile Custom Kernel" ;;
	esac
	local archive="${SRC}/userpatches/bootfs-custom-kernel/bootfs_custom_kernel.tar.gz"
	[[ -f "$archive" ]] || exit_with_error "Missing userpatches/bootfs-custom-kernel/bootfs_custom_kernel.tar.gz"
	tar -tzf "$archive" >/dev/null 2>&1 || exit_with_error "Custom bootfs archive is not a valid .tar.gz file"
	EXTRA_IMAGE_SUFFIXES+=("-custom-bootfs")
}

function dbai_replace_bootfs_files() {
	: "${SDCARD:?Armbian did not set SDCARD for custom bootfs replacement}"
	local boot_dir="${SDCARD}/boot"
	local archive="${SRC}/userpatches/bootfs-custom-kernel/bootfs_custom_kernel.tar.gz"
	mkdir -p "$boot_dir"
	tar -tzf "$archive" >/dev/null 2>&1 || exit_with_error "Custom bootfs archive is invalid"
	if ! tar -tzf "$archive" | awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }'; then
		exit_with_error "Unsafe absolute or parent-traversal path in custom bootfs archive"
	fi
	if ! tar -tzf "$archive" | awk 'NF && $0 !~ /^\.\/?$/ { found=1 } END { exit !found }'; then
		exit_with_error "Custom bootfs archive is empty"
	fi

	display_alert "DBAI custom bootfs" "Removing default /boot contents and extracting bootfs_custom_kernel.tar.gz" "info"
	find "$boot_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
	tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$boot_dir"
	find "$boot_dir" -mindepth 1 -print -quit | grep -q . || exit_with_error "Custom bootfs extraction left /boot empty"
}

function pre_customize_image__dbai_replace_bootfs_for_recompile() {
	[[ "${DBAI_KERNEL_MODE:-}" == "Recompile Custom Kernel" ]] || return 0
	: "${SDCARD:?Armbian did not set SDCARD for custom bootfs replacement}"
	local boot_dir="${SDCARD}/boot"
	local preserve="${SRC}/cache/dbai-custom-bootfs-preserve"
	local path
	rm -rf "$preserve"
	mkdir -p "$preserve" "$boot_dir"

	# Keep compiled kernel and DTB artifacts while replacing the other boot files.
	while IFS= read -r -d '' path; do
		cp -a "$path" "$preserve/"
	done < <(find "$boot_dir" -mindepth 1 -maxdepth 1 \
		\( -type f \( -name 'Image' -o -name 'Image-*' -o -name 'vmlinuz*' -o -name 'uImage' -o -name 'zImage' -o -name 'initrd*' -o -name 'uInitrd*' -o -name '*.dtb' -o -name 'config-*' -o -name 'System.map-*' \) \
		-o -type d \( -name 'dtb' -o -name 'dtbs' \) \) -print0)

	dbai_replace_bootfs_files
	cp -a "$preserve/." "$boot_dir/"
	find "$boot_dir" -maxdepth 4 -type f \( -name 'Image' -o -name 'Image-*' -o -name 'vmlinuz*' -o -name 'uImage' -o -name 'zImage' \) -print -quit | grep -q . || exit_with_error "No compiled kernel image found in /boot after custom bootfs replacement"
	display_alert "DBAI custom bootfs" "Custom bootfs installed; compiled kernel and DTB artifacts were preserved" "info"
}
