# shellcheck shell=bash
# Install platform boot files, Ophub userspace tools, and Triad firmware into each image.
# Custom-kernel handling rebuilds /boot later by merging U-Boot, custom bootfs, and kernel payloads.

function dbai_platform_validate_archive() {
	local archive="${1}"
	[[ -s "$archive" ]] || exit_with_error "Required DBAI platform archive is missing or empty: $archive"
	tar -tzf "$archive" >/dev/null 2>&1 || exit_with_error "Invalid gzip-compressed tar archive: $archive"
	if ! tar -tzf "$archive" | awk ' /^\/|(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }'; then
		exit_with_error "Unsafe absolute or parent-traversal path in platform archive: $archive"
	fi
	if ! tar -tzf "$archive" | awk 'NF && $0 !~ /^\.\/?$/ { found=1 } END { exit !found }'; then
		exit_with_error "Platform archive is empty: $archive"
	fi
}

function extension_prepare_config__dbai_platform_overlays() {
	local platform_dir="${SRC}/userpatches/platform"
	local uboot_archive="${platform_dir}/u-boot.tar.gz"
	local usr_archive="${platform_dir}/usr.tar.gz"
	local triad_archive="${platform_dir}/triad-firmware.tar.gz"

	dbai_platform_validate_archive "$uboot_archive"
	dbai_platform_validate_archive "$usr_archive"
	dbai_platform_validate_archive "$triad_archive"

	if ! tar -tzf "$usr_archive" | awk '
		function clean(path) {
			sub(/^\.\//, "", path)
			sub(/\/+$/, "", path)
			return path
		}
		{
			path=clean($0)
			if (path=="" || path==".") next
			if (path=="usr") { prefixed=1; next }
			if (path ~ /^usr\//) { prefixed=1; sub(/^usr\//, "", path) }
			else direct=1
			if (path=="" || path==".") next
			split(path, parts, "/")
			if (parts[1]!="bin" && parts[1]!="sbin" && parts[1]!="share") bad=1
		}
		END { if (bad || (prefixed && direct) || (!prefixed && !direct)) exit 1 }
	'; then
		exit_with_error "usr.tar.gz must contain only bin/, sbin/, and share/ (optionally wrapped in one usr/ directory)"
	fi
}

function pre_customize_image__100_dbai_platform_overlays() {
	: "${SDCARD:?Armbian did not set SDCARD for DBAI platform overlays}"
	local platform_dir="${SRC}/userpatches/platform"
	local uboot_archive="${platform_dir}/u-boot.tar.gz"
	local usr_archive="${platform_dir}/usr.tar.gz"
	local triad_archive="${platform_dir}/triad-firmware.tar.gz"
	local stage_dir="${SRC}/cache/dbai-platform-overlays"
	local boot_stage="${stage_dir}/boot-unpacked"
	local usr_stage="${stage_dir}/usr-unpacked"
	local triad_stage="${stage_dir}/triad-unpacked"
	local boot_dir="${SDCARD}/boot"
	local usr_dir="${SDCARD}/usr"
	local firmware_dir="${SDCARD}/usr/lib/firmware"
	local boot_payload="$boot_stage"
	local usr_payload="$usr_stage"
	local triad_payload="$triad_stage"
	local relative file destination
	local -a executable_paths=(
		"bin/ampart"
		"bin/uuidgen"
		"sbin/armbian-apt"
		"sbin/armbian-ddbr"
		"sbin/armbian-docker"
		"sbin/armbian-fix"
		"sbin/armbian-install"
		"sbin/armbian-kernel"
		"sbin/armbian-openvfd"
		"sbin/armbian-software"
		"sbin/armbian-swap"
		"sbin/armbian-sync"
		"sbin/armbian-tf"
		"sbin/armbian-update"
		"sbin/balethirq.pl"
		"share/openvfd/vfdservice"
		"share/ophub/armbian-software/201-desktop-chinese-fonts.sh"
		"share/ophub/armbian-software/301-frps.sh"
		"share/ophub/armbian-software/302-frpc.sh"
		"share/ophub/armbian-software/command-desktop.sh"
		"share/ophub/armbian-software/command-docker.sh"
		"share/ophub/armbian-software/command-service.sh"
		"share/ophub/armbian-software/software-command.sh"
	)

	dbai_platform_validate_archive "$uboot_archive"
	dbai_platform_validate_archive "$usr_archive"
	dbai_platform_validate_archive "$triad_archive"
	[[ ! -L "$boot_dir" ]] || exit_with_error "Refusing to replace a symlink at image /boot"
	[[ ! -L "$usr_dir" ]] || exit_with_error "Refusing to overlay a symlink at image /usr"
	[[ ! -L "${SDCARD}/usr/lib" ]] || exit_with_error "Refusing to overlay firmware through a symlink at image /usr/lib"
	[[ ! -L "$firmware_dir" ]] || exit_with_error "Refusing to overlay firmware through a symlink at image /usr/lib/firmware"

	rm -rf -- "$stage_dir"
	mkdir -p "$boot_stage" "$usr_stage" "$triad_stage" "$boot_dir" "$usr_dir" "$firmware_dir"

	# Normalize either a boot-root tarball or an archive with one enclosing boot/ directory.
	tar --no-same-owner --no-same-permissions -xzf "$uboot_archive" -C "$boot_stage"
	if [[ -d "$boot_stage/boot" ]]; then
		local other_top_level
		other_top_level="$(find "$boot_stage" -mindepth 1 -maxdepth 1 ! -name boot -print -quit)"
		[[ -n "$other_top_level" ]] || boot_payload="${boot_stage}/boot"
	fi
	find "$boot_payload" -mindepth 1 -print -quit | grep -q . || exit_with_error "u-boot.tar.gz contains no boot files"

	# Match bootfs_custom_kernel.tar.gz semantics: replace default /boot contents.
	display_alert "DBAI platform boot" "Replacing image /boot contents from u-boot.tar.gz" "info"
	find "$boot_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
	cp -a "${boot_payload}/." "$boot_dir/"

	# usr.tar.gz may be rooted at bin/sbin/share or wrapped by one usr/ directory.
	tar --no-same-owner --no-same-permissions -xzf "$usr_archive" -C "$usr_stage"
	if [[ -d "$usr_stage/usr" ]]; then
		usr_payload="${usr_stage}/usr"
	fi
	for relative in bin sbin share; do
		[[ -d "${usr_payload}/${relative}" ]] || exit_with_error "usr.tar.gz is missing ${relative}/ under its payload root"
	done

	display_alert "DBAI platform userspace" "Overlaying usr.tar.gz into image /usr" "info"
	cp -a "${usr_payload}/." "$usr_dir/"

	# Triad firmware archives may be rooted directly at the firmware tree or
	# wrapped in firmware/, lib/firmware/, or usr/lib/firmware/.
	tar --no-same-owner --no-same-permissions -xzf "$triad_archive" -C "$triad_stage"
	if [[ -d "$triad_stage/usr/lib/firmware" ]]; then
		triad_payload="$triad_stage/usr/lib/firmware"
	elif [[ -d "$triad_stage/lib/firmware" ]]; then
		triad_payload="$triad_stage/lib/firmware"
	elif [[ -d "$triad_stage/firmware" ]]; then
		triad_payload="$triad_stage/firmware"
	fi
	find "$triad_payload" -mindepth 1 -print -quit | grep -q . || exit_with_error "triad-firmware.tar.gz contains no firmware payload"
	display_alert "DBAI Triad firmware" "Overlaying triad-firmware.tar.gz into image /usr/lib/firmware" "info"
	cp -a "${triad_payload}/." "$firmware_dir/"
	local triad_file_count
	triad_file_count="$(find "$triad_payload" -type f -print | wc -l | tr -d '[:space:]')"
	[[ "$triad_file_count" =~ ^[0-9]+$ && "$triad_file_count" -gt 0 ]] || exit_with_error "triad-firmware.tar.gz contains no regular firmware files"

	# Clear execute bits on archive-supplied regular files, then mark only known
	# programs and scripts executable; configuration and list files stay data.
	while IFS= read -r -d '' file; do
		relative="${file#"${usr_payload}/"}"
		destination="${usr_dir}/${relative}"
		if [[ -f "$destination" && ! -L "$destination" ]]; then
			chmod a-x "$destination"
		fi
	done < <(find "$usr_payload" -type f -print0)

	for relative in "${executable_paths[@]}"; do
		destination="${usr_dir}/${relative}"
		[[ -f "$destination" && ! -L "$destination" ]] || exit_with_error "Required executable missing or not a regular file in usr.tar.gz: /usr/${relative}"
		chmod 0755 "$destination"
	done

	if [[ -f "${usr_dir}/bin/imba" && ! -L "${usr_dir}/bin/imba" ]]; then
		chmod 0755 "${usr_dir}/bin/imba"
	fi

	rm -rf -- "$stage_dir"
	display_alert "DBAI platform payloads" "Installed U-Boot files, overlaid usr.tar.gz, installed ${triad_file_count} Triad firmware files, and marked the 23 designated programs/scripts executable" "info"
}

function post_config__dbai_platform_overlays_rename_docker() {
	local idx
	for idx in "${!EXTRA_IMAGE_SUFFIXES[@]}"; do
		if [[ "${EXTRA_IMAGE_SUFFIXES[idx]}" == "-docker" ]]; then
			EXTRA_IMAGE_SUFFIXES[idx]="-docker+portainer"
		fi
	done
}
