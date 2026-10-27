# shellcheck shell=bash
# Replace default /boot files for the two custom-kernel modes.

function extension_prepare_config__dbai_custom_bootfs() {
	case "${DBAI_KERNEL_MODE:-}" in
		"Custom Kernel"|"Recompile Custom Kernel") ;;
		*) exit_with_error "dbai-custom-bootfs is only valid with Custom Kernel or Recompile Custom Kernel" ;;
	esac
	local archive="${SRC}/userpatches/platform/bootfs_custom_kernel.tar.gz"
	[[ -f "$archive" ]] || exit_with_error "Missing userpatches/platform/bootfs_custom_kernel.tar.gz"
	tar -tzf "$archive" >/dev/null 2>&1 || exit_with_error "Custom bootfs archive is not a valid .tar.gz file"
	EXTRA_IMAGE_SUFFIXES+=("-custom-bootfs")
}

function dbai_validate_boot_archive() {
	local archive="$1"
	[[ -s "$archive" ]] || exit_with_error "Required boot archive is missing or empty: $archive"
	tar -tzf "$archive" >/dev/null 2>&1 || exit_with_error "Boot archive is not a valid gzip-compressed tar: $archive"
	if ! tar -tzf "$archive" | awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }'; then
		exit_with_error "Unsafe absolute or parent-traversal path in boot archive: $archive"
	fi
	if ! tar -tzf "$archive" | awk 'NF && $0 !~ /^\.\/*$/ { found=1 } END { exit !found }'; then
		exit_with_error "Boot archive has no payload: $archive"
	fi
}

function dbai_stage_boot_archive_payload() {
	local archive="$1" stage="$2" payload="$2" other_top_level
	mkdir -p "$stage"
	dbai_validate_boot_archive "$archive"
	tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$stage"
	if [[ -d "$stage/boot" ]]; then
		other_top_level="$(find "$stage" -mindepth 1 -maxdepth 1 ! -name boot -print -quit)"
		[[ -n "$other_top_level" ]] || payload="$stage/boot"
	fi
	find "$payload" -mindepth 1 -print -quit | grep -q . || exit_with_error "Boot archive contains no files: $archive"
	printf '%s\n' "$payload"
}

function dbai_verify_boot_archive_payload_paths() {
	local payload="$1" boot_dir="$2" archive_label="$3" source_file relative destination
	while IFS= read -r -d '' source_file; do
		relative="${source_file#"$payload"/}"
		destination="${boot_dir}/${relative}"
		[[ -e "$destination" || -L "$destination" ]] || exit_with_error "${archive_label} payload file is missing from final /boot: ${relative}"
	done < <(find "$payload" \( -type f -o -type l \) -print0)
}

function dbai_configure_uenv_rootfs() {
	local uenv="$1" fs="${ROOTFS_TYPE:-${FILESYSTEM:-ext4}}"
	[[ -f "$uenv" ]] || return 0
	if [[ "${fs,,}" == "btrfs" ]]; then
		sed -i -E 's|^[[:space:]]*APPEND=.*|APPEND=root=UUID=19450817-1998-4512-a817-202510202026 rootflags=subvol=@,compress=zstd:6 rw rootwait rootfstype=btrfs console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 max_loop=128 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1|' "$uenv"
		display_alert "DBAI custom bootfs" "Configured uEnv.txt for BTRFS root filesystem" "info"
	fi
}

function dbai_replace_bootfs_files() {
	# Final /boot is composed from the U-Boot archive first, then the custom
	# bootfs config, then the custom kernel/DTB bundle. This prevents the later
	# custom-kernel finalizer from silently discarding u-boot.tar.gz.
	local target_root="${1:-${SDCARD:-}}"
	[[ -n "$target_root" ]] || exit_with_error "Armbian did not set SDCARD for custom bootfs replacement"
	local boot_dir="${target_root}/boot"
	local platform_dir="${SRC}/userpatches/platform"
	local uboot_archive="${platform_dir}/u-boot.tar.gz"
	local custom_archive="${platform_dir}/bootfs_custom_kernel.tar.gz"
	local stage_dir="${SRC}/cache/dbai-custom-bootfs-merged"
	local uboot_stage="${stage_dir}/u-boot-unpacked"
	local custom_stage="${stage_dir}/custom-bootfs-unpacked"
	local uboot_payload custom_payload

	dbai_validate_boot_archive "$uboot_archive"
	dbai_validate_boot_archive "$custom_archive"
	[[ ! -L "$boot_dir" ]] || exit_with_error "Refusing to replace a symlink at image /boot"
	rm -rf -- "$stage_dir"
	mkdir -p "$uboot_stage" "$custom_stage" "$boot_dir"
	uboot_payload="$(dbai_stage_boot_archive_payload "$uboot_archive" "$uboot_stage")"
	custom_payload="$(dbai_stage_boot_archive_payload "$custom_archive" "$custom_stage")"

	display_alert "DBAI custom bootfs" "Replacing default /boot with u-boot.tar.gz, then layering bootfs_custom_kernel.tar.gz configuration" "info"
	find "$boot_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
	cp -a "${uboot_payload}/." "$boot_dir/"
	cp -a "${custom_payload}/." "$boot_dir/"
	dbai_configure_uenv_rootfs "${boot_dir}/uEnv.txt"
	dbai_verify_boot_archive_payload_paths "$uboot_payload" "$boot_dir" "u-boot.tar.gz"
	dbai_verify_boot_archive_payload_paths "$custom_payload" "$boot_dir" "bootfs_custom_kernel.tar.gz"
	find "$boot_dir" -mindepth 1 -print -quit | grep -q . || exit_with_error "Custom bootfs merge left /boot empty"
	rm -rf -- "$stage_dir"
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

	dbai_replace_bootfs_files "$SDCARD"
	cp -a "$preserve/." "$boot_dir/"
	find "$boot_dir" -maxdepth 4 -type f \( -name 'Image' -o -name 'Image-*' -o -name 'vmlinuz*' -o -name 'uImage' -o -name 'zImage' \) -print -quit | grep -q . || exit_with_error "No compiled kernel image found in /boot after custom bootfs replacement"
	display_alert "DBAI custom bootfs" "Custom bootfs installed; compiled kernel and DTB artifacts were preserved" "info"
}
