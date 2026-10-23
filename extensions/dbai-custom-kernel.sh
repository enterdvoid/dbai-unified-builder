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
		# Do not follow absolute parent symlinks (for example /lib -> /usr/lib)
		# because path resolution would escape the target image and reach the host.
		case "$modules_root" in
			"$target_root/lib/modules")
				if [[ -L "$target_root/lib" ]] && [[ "$(readlink "$target_root/lib")" == /* ]]; then
					echo "Skipping module root through absolute image /lib symlink: $modules_root" >&2
					continue
				fi
				;;
			"$target_root/usr/lib/modules")
				if [[ -L "$target_root/usr" ]] && [[ "$(readlink "$target_root/usr")" == /* ]]; then
					echo "Skipping module root through absolute image /usr symlink: $modules_root" >&2
					continue
				fi
				if [[ -L "$target_root/usr/lib" ]] && [[ "$(readlink "$target_root/usr/lib")" == /* ]]; then
					echo "Skipping module root through absolute image /usr/lib symlink: $modules_root" >&2
					continue
				fi
				;;
		esac
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
		release="$(awk '
			{
				path=$0
				sub(/^\.\//, "", path)
				if (path ~ /^lib\/modules\/[^/]+\//) {
					sub(/^lib\/modules\//, "", path)
					split(path, parts, "/")
					print parts[1]
					exit
				}
			}
		' "${listing_file}")"
	else
		release="$(awk '
			{
				path=$0
				sub(/^\.\//, "", path)
				if (path ~ /^[^/]+\/modules[.]dep$/ || path ~ /^[^/]+\/kernel\//) {
					split(path, parts, "/")
					print parts[1]
					exit
				}
			}
		' "${listing_file}")"
	fi
	[[ -n "${release}" && "${release}" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
	printf '%s\n' "${release}"
}

# Normalize a module archive in disposable staging, then copy only the verified
# release tree into the target image. This avoids extracting a release-root
# archive directly into the image with tar path transforms, which can leave
# a stray /<release> directory behind.
function dbai_install_kernel_modules_archive() {
	local archive="$1" layout="$2" release="$3" staging_root="$4" target_root="$5"
	local unpack_root="$staging_root/unpacked" source_tree="" verified_tree="$staging_root/verified-tree"
	local listing_file="$staging_root/archive-list.txt" detected_release="" dest
	local target_abs="" staging_abs="" modules_parent_abs="" dest_abs=""

	[[ -f "$archive" && -d "$target_root" ]] || { echo "ERROR: Module archive or target root is unavailable." >&2; return 1; }
	[[ "$release" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo "ERROR: Unsafe module release: $release" >&2; return 1; }
	[[ "$layout" == "release-root" || "$layout" == "target-root" ]] || { echo "ERROR: Unknown module archive layout: $layout" >&2; return 1; }
	[[ -n "$staging_root" && "$staging_root" != "/" ]] || { echo "ERROR: Unsafe module staging directory." >&2; return 1; }

	target_abs="$(realpath -e "$target_root")" || { echo "ERROR: Cannot resolve target image root." >&2; return 1; }
	staging_abs="$(realpath -m "$staging_root")" || { echo "ERROR: Cannot resolve staging directory." >&2; return 1; }
	case "$staging_abs" in
		"$target_abs"|"$target_abs"/*) echo "ERROR: Staging directory must be outside the target image." >&2; return 1 ;;
	esac
	case "$target_abs" in
		"$staging_abs"|"$staging_abs"/*) echo "ERROR: Target image must be outside the staging directory." >&2; return 1 ;;
	esac

	# Resolve /lib/modules through any in-image usr-merge symlinks and refuse
	# paths that would escape the image root onto the builder host filesystem.
	modules_parent_abs="$(realpath -m "$target_abs/lib/modules")" || { echo "ERROR: Cannot resolve target /lib/modules path." >&2; return 1; }
	case "$modules_parent_abs" in
		"$target_abs"/*) ;;
		*) echo "ERROR: Target /lib/modules path resolves outside the image root: $modules_parent_abs" >&2; return 1 ;;
	esac
	if [[ -e "$target_abs/$release" || -L "$target_abs/$release" ]]; then
		echo "ERROR: Refusing to overlay modules while an unexpected root-level /$release path already exists." >&2
		return 1
	fi

	rm -rf -- "$staging_root" || return 1
	mkdir -p -- "$unpack_root" || return 1
	tar -tf "$archive" > "$listing_file" || { echo "ERROR: Cannot read module archive: $archive" >&2; return 1; }
	if ! awk ' /^\// { bad=1 } /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }' "$listing_file"; then
		echo "ERROR: Unsafe absolute or parent-traversal path in module archive." >&2
		return 1
	fi
	detected_release="$(dbai_detect_kernel_modules_release "$listing_file")" || {
		echo "ERROR: Cannot determine kernel release from module archive." >&2
		return 1
	}
	[[ "$detected_release" == "$release" ]] || {
		echo "ERROR: Module archive release mismatch: expected $release, found $detected_release." >&2
		return 1
	}

	case "$layout" in
		release-root)
			if ! awk -v release="$release" '
				{
					path=$0
					sub(/^\.\//, "", path)
					sub(/\/$/, "", path)
					if (path=="" || path=="." || path==release || index(path,release "/")==1) next
					bad=1
				}
				END { exit bad }
			' "$listing_file"; then
				echo "ERROR: Release-root module archive contains unexpected paths outside /$release." >&2
				return 1
			fi
			source_tree="$unpack_root/$release"
			;;
		target-root)
			if ! awk -v release="$release" '
				{
					path=$0
					sub(/^\.\//, "", path)
					sub(/\/$/, "", path)
					if (path=="" || path=="." || path=="lib" || path=="lib/modules" ||
					    path=="lib/modules/" release || index(path,"lib/modules/" release "/")==1) next
					bad=1
				}
				END { exit bad }
			' "$listing_file"; then
				echo "ERROR: Target-root module archive contains unexpected paths outside lib/modules/$release." >&2
				return 1
			fi
			source_tree="$unpack_root/lib/modules/$release"
			;;
	esac

	tar --no-same-owner --no-same-permissions -xf "$archive" -C "$unpack_root" || {
		echo "ERROR: Failed to extract module archive into staging." >&2
		return 1
	}
	[[ -d "$source_tree" && ! -L "$source_tree" ]] || {
		echo "ERROR: Expected module tree is missing from staged archive: $source_tree" >&2
		return 1
	}
	[[ -f "$source_tree/modules.dep" && ! -L "$source_tree/modules.dep" ]] || {
		echo "ERROR: Staged module tree lacks a regular modules.dep file for $release." >&2
		return 1
	}
	[[ -n "$(find "$source_tree" -type f -name '*.ko*' -print -quit)" ]] || {
		echo "ERROR: Staged module tree contains no .ko module files for $release." >&2
		return 1
	}

	mkdir -p -- "$verified_tree" || return 1
	cp -a -- "$source_tree/." "$verified_tree/" || { echo "ERROR: Could not normalize staged module tree." >&2; return 1; }
	[[ -f "$verified_tree/modules.dep" && -n "$(find "$verified_tree" -type f -name '*.ko*' -print -quit)" ]] || {
		echo "ERROR: Normalized staged module tree failed its post-copy checks." >&2
		return 1
	}

	dest="$modules_parent_abs/$release"
	[[ ! -L "$dest" ]] || { echo "ERROR: Refusing symlinked kernel module destination: $dest" >&2; return 1; }
	mkdir -p -- "$dest" || return 1
	dest_abs="$(realpath -e "$dest")" || { echo "ERROR: Cannot resolve installed module destination." >&2; return 1; }
	[[ "$dest_abs" == "$dest" ]] || { echo "ERROR: Kernel module destination resolves unexpectedly: $dest_abs" >&2; return 1; }
	cp -a -- "$verified_tree/." "$dest/" || { echo "ERROR: Could not copy verified modules into target image." >&2; return 1; }
	[[ -f "$dest/modules.dep" && -n "$(find "$dest" -type f -name '*.ko*' -print -quit)" ]] || {
		echo "ERROR: Installed module tree failed its post-install checks for $release." >&2
		return 1
	}
	[[ ! -e "$target_abs/$release" && ! -L "$target_abs/$release" ]] || {
		echo "ERROR: Unexpected root-level /$release path appeared during module installation." >&2
		return 1
	}

	rm -rf -- "$staging_root" || return 1
	echo "Installed verified module tree at /lib/modules/$release from isolated staging; no root-level release directory created."
}

function dbai_list_installed_distro_kernel_packages() {
	local status_file="$1"
	[[ -f "$status_file" ]] || return 1
	awk '
		BEGIN { RS=""; FS="\n" }
		{
			package=""
			status=""
			for (i=1; i<=NF; i++) {
				if ($i ~ /^Package: /) { package=$i; sub(/^Package: /, "", package) }
				if ($i ~ /^Status: /) { status=$i; sub(/^Status: /, "", status) }
			}
			if (package ~ /^linux-(image|dtb|headers)-/ && status ~ / ok installed$/) print package
		}
	' "$status_file" | sort -u
}

function dbai_purge_installed_distro_kernel_packages() {
	local target_root="$1" custom_release="$2" package status_file
	local -a packages=()
	status_file="$target_root/var/lib/dpkg/status"
	[[ -f "$status_file" ]] || { echo "ERROR: target dpkg status database is missing: $status_file" >&2; return 1; }
	# Kernel package maintainer scripts invoke update-initramfs/mktemp during purge.
	# The build WORK/TMPDIR may already be gone, so use a valid target /tmp.
	mkdir -p "$target_root/tmp" || return 1
	chmod 1777 "$target_root/tmp" || return 1
	mapfile -t packages < <(dbai_list_installed_distro_kernel_packages "$status_file")
	for package in "${packages[@]}"; do
		case "$package" in
			"linux-image-$custom_release"|"linux-dtb-$custom_release"|"linux-headers-$custom_release") continue ;;
		esac
		echo "Purging residual distro kernel package: $package"
		printf '%s install\n' "$package" | chroot "$target_root" dpkg --set-selections || return 1
		chroot "$target_root" env TMPDIR=/tmp dpkg --purge --force-depends "$package" || {
			echo "ERROR: Unable to purge residual distro kernel package: $package" >&2
			return 1
		}
	done
	mapfile -t packages < <(dbai_list_installed_distro_kernel_packages "$status_file")
	for package in "${packages[@]}"; do
		case "$package" in
			"linux-image-$custom_release"|"linux-dtb-$custom_release"|"linux-headers-$custom_release") continue ;;
		esac
		echo "ERROR: distro kernel package remains installed after purge: $package" >&2
		return 1
	done
}

function dbai_prune_noncustom_boot_artifacts() {
	local target_root="$1" custom_release="$2" entry name boot_artifact_release
	local boot_dir="$target_root/boot"
	[[ -d "$boot_dir" ]] || return 0
	for entry in "$boot_dir"/vmlinuz-* "$boot_dir"/Image-* "$boot_dir"/uImage-* "$boot_dir"/zImage-* "$boot_dir"/initrd.img-* "$boot_dir"/uInitrd-* "$boot_dir"/config-* "$boot_dir"/System.map-* "$boot_dir"/dtb-*; do
		[[ -e "$entry" || -L "$entry" ]] || continue
		name="$(basename "$entry")"
		case "$name" in
			vmlinuz-*) boot_artifact_release="${name#vmlinuz-}" ;;
			Image-*) boot_artifact_release="${name#Image-}" ;;
			uImage-*) boot_artifact_release="${name#uImage-}" ;;
			zImage-*) boot_artifact_release="${name#zImage-}" ;;
			initrd.img-*) boot_artifact_release="${name#initrd.img-}" ;;
			uInitrd-*) boot_artifact_release="${name#uInitrd-}" ;;
			config-*) boot_artifact_release="${name#config-}" ;;
			System.map-*) boot_artifact_release="${name#System.map-}" ;;
			dtb-*) boot_artifact_release="${name#dtb-}" ;;
			*) continue ;;
		esac
		[[ "$boot_artifact_release" == "$custom_release" ]] && continue
		echo "Removing non-custom boot artifact: /boot/$name"
		rm -rf -- "$entry"
	done
}
function dbai_sync_custom_kernel_uenv() {
	local uenv="$1" release="$2" kernel_name="$3" ramdisk_name="$4" tmp
	[[ -f "$uenv" && ! -L "$uenv" ]] || { echo "ERROR: custom-kernel U-Boot config is missing or not a regular file: $uenv" >&2; return 1; }
	[[ "$release" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || { echo "ERROR: Unsafe custom kernel release for uEnv.txt: $release" >&2; return 1; }
	[[ "$kernel_name" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || { echo "ERROR: Unsafe custom kernel filename for uEnv.txt: $kernel_name" >&2; return 1; }
	[[ "$ramdisk_name" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || { echo "ERROR: Unsafe U-Boot ramdisk filename for uEnv.txt: $ramdisk_name" >&2; return 1; }

	tmp="$(mktemp "$(dirname "$uenv")/.uEnv.txt.dbai.XXXXXX")" || return 1
	if ! awk -v release="$release" -v kernel_name="$kernel_name" -v ramdisk_name="$ramdisk_name" '
		BEGIN { kernels=0; linuxes=0; initrds=0 }
		{
			sub(/\r$/, "")
			if ($0 ~ /^[[:space:]]*KERNEL[[:space:]]*=/) { print "KERNEL=" release; kernels++; next }
			if ($0 ~ /^[[:space:]]*LINUX[[:space:]]*=/) { print "LINUX=/" kernel_name; linuxes++; next }
			if ($0 ~ /^[[:space:]]*INITRD[[:space:]]*=/) { print "INITRD=/" ramdisk_name; initrds++; next }
			print
		}
		END { if (kernels != 1 || linuxes > 1 || initrds > 1) exit 1 }
	' "$uenv" > "$tmp"; then
		rm -f -- "$tmp"
		echo "ERROR: uEnv.txt must contain exactly one KERNEL assignment and no duplicate optional LINUX/INITRD assignments." >&2
		return 1
	fi
	chmod --reference="$uenv" "$tmp" || { rm -f -- "$tmp"; return 1; }
	mv -f -- "$tmp" "$uenv" || { rm -f -- "$tmp"; return 1; }
	echo "Synchronized uEnv.txt to kernel release $release, kernel /$kernel_name, and ramdisk /$ramdisk_name."
}

function dbai_restore_custom_kernel_boot_payload() {
	local target_root="$1" cache_dir="${SRC}/cache/dbai-custom-kernel" archive dtb_stage dtb_file dtb_rel dtb_target
	local manifest custom_release kernel_name ramdisk_name
	[[ -f "$cache_dir/boot.tar" && -f "$cache_dir/dtb.tar" ]] || {
		echo "ERROR: validated custom-kernel boot/DTB archives are unavailable during final cleanup." >&2
		return 1
	}
	dbai_replace_bootfs_files "$target_root" || return 1
	archive="$cache_dir/boot.tar"
	if tar -tf "$archive" | grep -Eq '^boot/'; then
		tar --no-same-owner --no-same-permissions -xf "$archive" -C "$target_root"
	else
		tar --no-same-owner --no-same-permissions --transform='s,^[.]/,,;s,^,boot/,' -xf "$archive" -C "$target_root"
	fi
	manifest="$target_root/etc/dbai-custom-kernel-manifest.txt"
	custom_release="$(sed -n 's/^Kernel release: //p' "$manifest" | sed -n '1p')"
	kernel_name="$(sed -n 's/^Boot kernel file: //p' "$manifest" | sed -n '1p')"
	ramdisk_name="$(sed -n 's/^Boot ramdisk file: //p' "$manifest" | sed -n '1p')"
	dbai_sync_custom_kernel_uenv "$target_root/boot/uEnv.txt" "$custom_release" "$kernel_name" "$ramdisk_name" || return 1
	if [[ -s "$target_root/boot/$kernel_name" && ! -e "$target_root/boot/zImage" ]]; then
		cp -f "$target_root/boot/$kernel_name" "$target_root/boot/zImage"
	fi
	if [[ -s "$target_root/boot/$ramdisk_name" && ! -e "$target_root/boot/uInitrd" ]]; then
		cp -f "$target_root/boot/$ramdisk_name" "$target_root/boot/uInitrd"
	fi
	dtb_stage="$(TMPDIR=/tmp mktemp -d /tmp/dbai-final-dtb.XXXXXX)" || { echo "ERROR: unable to create temporary directory for custom DTBs." >&2; return 1; }
	if ! tar --no-same-owner --no-same-permissions -xf "$cache_dir/dtb.tar" -C "$dtb_stage"; then
		rm -rf -- "$dtb_stage"
		echo "ERROR: unable to restore the validated custom DTB archive." >&2
		return 1
	fi
	while IFS= read -r -d '' dtb_file; do
		dtb_rel="${dtb_file#"$dtb_stage"/}"
		while [[ "$dtb_rel" == ./* ]]; do dtb_rel="${dtb_rel#./}"; done
		case "/$dtb_rel" in
			*/boot/*) dtb_target="$target_root/$dtb_rel" ;;
			*/dtb/*) dtb_target="$target_root/boot/dtb/${dtb_rel#dtb/}" ;;
			*/amlogic/*) dtb_target="$target_root/boot/dtb/$dtb_rel" ;;
			*) dtb_target="$target_root/boot/dtb/amlogic/${dtb_rel##*/}" ;;
		esac
		mkdir -p "$(dirname "$dtb_target")"
		cp -f -- "$dtb_file" "$dtb_target"
	done < <(find "$dtb_stage" -type f -name '*.dtb' -print0)
	rm -rf -- "$dtb_stage"
	find "$target_root/boot" -type f -name '*.dtb' -print -quit | grep -q . || {
		echo "ERROR: custom DTB archive restored no DTBs into the final boot filesystem." >&2
		return 1
	}
}

function dbai_verify_custom_kernel_boot_payload() {
	local target_root="$1" manifest custom_release expected_kernel_name expected_kernel_sha expected_ramdisk_name expected_ramdisk_sha
	local kernel_path ramdisk_path actual_sha entry name boot_artifact_release
	manifest="$target_root/etc/dbai-custom-kernel-manifest.txt"
	custom_release="$(sed -n 's/^Kernel release: //p' "$manifest" | sed -n '1p')"
	expected_kernel_name="$(sed -n 's/^Boot kernel file: //p' "$manifest" | sed -n '1p')"
	expected_kernel_sha="$(sed -n 's/^Boot kernel SHA-256: //p' "$manifest" | sed -n '1p')"
	expected_ramdisk_name="$(sed -n 's/^Boot ramdisk file: //p' "$manifest" | sed -n '1p')"
	expected_ramdisk_sha="$(sed -n 's/^Boot ramdisk SHA-256: //p' "$manifest" | sed -n '1p')"
	[[ "$custom_release" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo "ERROR: custom-kernel manifest lacks a valid kernel release." >&2; return 1; }
	case "$expected_kernel_name" in
		"vmlinuz-$custom_release"|"Image-$custom_release"|"uImage-$custom_release"|"zImage-$custom_release"|vmlinuz|Image|uImage|zImage) ;;
		*) echo "ERROR: recorded kernel filename is incompatible with the DBAI boot scripts: ${expected_kernel_name:-missing}" >&2; return 1 ;;
	esac
	[[ "$expected_kernel_sha" =~ ^[[:xdigit:]]{64}$ ]] || { echo "ERROR: custom-kernel manifest lacks a valid boot-kernel SHA-256." >&2; return 1; }
	case "$expected_ramdisk_name" in
		"uInitrd-$custom_release"|uInitrd) ;;
		*) echo "ERROR: recorded ramdisk filename is incompatible with the DBAI boot scripts: ${expected_ramdisk_name:-missing}" >&2; return 1 ;;
	esac
	[[ "$expected_ramdisk_sha" =~ ^[[:xdigit:]]{64}$ ]] || { echo "ERROR: custom-kernel manifest lacks a valid supplied-ramdisk SHA-256." >&2; return 1; }

	local boot_config configured_release configured_kernel configured_ramdisk configured_kernel_count configured_ramdisk_count
	boot_config="$target_root/boot/uEnv.txt"
	[[ -s "$boot_config" && ! -L "$boot_config" ]] || { echo "ERROR: final /boot/uEnv.txt is missing." >&2; return 1; }
	configured_release="$(awk -F= '$1 == "KERNEL" { sub(/\r$/, "", $2); print $2; exit }' "$boot_config")"
	configured_kernel_count="$(awk -F= '$1 ~ /^[[:space:]]*LINUX[[:space:]]*$/ { count++ } END { print count+0 }' "$boot_config")"
	configured_ramdisk_count="$(awk -F= '$1 ~ /^[[:space:]]*INITRD[[:space:]]*$/ { count++ } END { print count+0 }' "$boot_config")"
	configured_kernel="$(awk -F= '$1 ~ /^[[:space:]]*LINUX[[:space:]]*$/ { sub(/\r$/, "", $2); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' "$boot_config")"
	configured_ramdisk="$(awk -F= '$1 ~ /^[[:space:]]*INITRD[[:space:]]*$/ { sub(/\r$/, "", $2); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' "$boot_config")"
	[[ "$configured_release" == "$custom_release" ]] || { echo "ERROR: uEnv.txt KERNEL does not match the custom module release." >&2; return 1; }
	if [[ "$configured_kernel_count" == "1" ]]; then
		[[ "$configured_kernel" == "/$expected_kernel_name" ]] || { echo "ERROR: uEnv.txt LINUX does not point to the original custom kernel filename." >&2; return 1; }
	elif [[ "$configured_kernel_count" == "0" ]]; then
		[[ "$expected_kernel_name" == "vmlinuz-$custom_release" ]] || { echo "ERROR: uEnv.txt uses KERNEL-derived kernel naming and requires vmlinuz-$custom_release." >&2; return 1; }
	else
		echo "ERROR: final uEnv.txt contains duplicate LINUX assignments." >&2
		return 1
	fi
	if [[ "$configured_ramdisk_count" == "1" ]]; then
		[[ "$configured_ramdisk" == "/$expected_ramdisk_name" ]] || { echo "ERROR: uEnv.txt INITRD does not point to the supplied U-Boot ramdisk filename." >&2; return 1; }
	elif [[ "$configured_ramdisk_count" == "0" ]]; then
		[[ "$expected_ramdisk_name" == "uInitrd-$custom_release" ]] || { echo "ERROR: uEnv.txt uses KERNEL-derived ramdisk naming and requires uInitrd-$custom_release." >&2; return 1; }
	else
		echo "ERROR: final uEnv.txt contains duplicate INITRD assignments." >&2
		return 1
	fi

	kernel_path="$target_root/boot/$expected_kernel_name"
	ramdisk_path="$target_root/boot/$expected_ramdisk_name"
	[[ -s "$kernel_path" ]] || { echo "ERROR: original custom kernel file is missing from final /boot: $expected_kernel_name." >&2; return 1; }
	actual_sha="$(sha256sum "$kernel_path" | awk '{print $1}')"
	[[ "$actual_sha" == "$expected_kernel_sha" ]] || { echo "ERROR: original custom kernel SHA-256 changed: $expected_kernel_name." >&2; return 1; }
	[[ -s "$ramdisk_path" ]] || { echo "ERROR: supplied U-Boot ramdisk is missing from final /boot: $expected_ramdisk_name." >&2; return 1; }
	actual_sha="$(sha256sum "$ramdisk_path" | awk '{print $1}')"
	[[ "$actual_sha" == "$expected_ramdisk_sha" ]] || { echo "ERROR: supplied U-Boot ramdisk SHA-256 changed: $expected_ramdisk_name." >&2; return 1; }

	if find "$target_root/boot" -maxdepth 1 -type f -name 'initrd.img-*' -print -quit | grep -q .; then
		echo "ERROR: generated/stale initrd.img-* remains in final /boot; expected the original supplied U-Boot ramdisk only." >&2
		return 1
	fi
	for entry in "$target_root/boot"/vmlinuz-* "$target_root/boot"/Image-* "$target_root/boot"/uImage-* "$target_root/boot"/zImage-* "$target_root/boot"/uInitrd-* "$target_root/boot"/config-* "$target_root/boot"/System.map-* "$target_root/boot"/dtb-*; do
		[[ -e "$entry" || -L "$entry" ]] || continue
		name="$(basename "$entry")"
		case "$name" in
			vmlinuz-*) boot_artifact_release="${name#vmlinuz-}" ;;
			Image-*) boot_artifact_release="${name#Image-}" ;;
			uImage-*) boot_artifact_release="${name#uImage-}" ;;
			zImage-*) boot_artifact_release="${name#zImage-}" ;;
			uInitrd-*) boot_artifact_release="${name#uInitrd-}" ;;
			config-*) boot_artifact_release="${name#config-}" ;;
			System.map-*) boot_artifact_release="${name#System.map-}" ;;
			dtb-*) boot_artifact_release="${name#dtb-}" ;;
			*) continue ;;
		esac
		[[ "$boot_artifact_release" == "$custom_release" ]] || { echo "ERROR: residual old-kernel boot artifact remains: /boot/$name" >&2; return 1; }
	done
	echo "Verified original custom kernel and supplied U-Boot ramdisk SHA-256 values; no generated initramfs or old versioned boot artifacts remain."
}
function pre_umount_final_image__dbai_prune_noncustom_kernel_artifacts() {
	[[ "${DBAI_KERNEL_MODE:-}" == "Custom Kernel" ]] || return 0
	local target_root="${MOUNT:-}" custom_release="${DBAI_CUSTOM_KERNEL_RELEASE:-}"
	[[ -n "$target_root" && -d "$target_root" ]] || exit_with_error "Final image root mount is unavailable for custom-kernel cleanup"
	[[ "$custom_release" =~ ^[A-Za-z0-9._+-]+$ ]] || exit_with_error "Custom kernel release was not retained for final-image cleanup"
	[[ -d "$target_root/lib/modules/$custom_release" ]] || exit_with_error "Custom kernel modules are missing from final image root: /lib/modules/$custom_release"

	display_alert "DBAI custom kernel" "Purging distro kernel packages, restoring supplied boot payloads, and checking their hashes" "info"
	dbai_purge_installed_distro_kernel_packages "$target_root" "$custom_release" || exit_with_error "Unable to remove residual distro kernel packages from the final image"
	dbai_restore_custom_kernel_boot_payload "$target_root" || exit_with_error "Unable to restore original bootfs and custom kernel/ramdisk/DTB payload"
	dbai_prune_noncustom_kernel_artifacts "$target_root" "$custom_release" || exit_with_error "Unable to clean non-custom kernel modules and headers from the final image"
	dbai_verify_custom_kernel_boot_payload "$target_root" || exit_with_error "Final original kernel and supplied ramdisk verification failed"
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
	dbai_install_kernel_modules_archive "${cache_dir}/modules.tar" "${modules_layout}" "${modules_release}" "${cache_dir}/modules-stage" "${SDCARD}" || exit_with_error "Unable to safely stage and install the custom module tree"

	# Replace default boot scripts/config before applying the kernel bundle's /boot files.
	dbai_replace_bootfs_files "$SDCARD"

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
	# The custom module archive was normalized and installed from isolated staging above.
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

	# The boot scripts in bootfs_custom_kernel.tar.gz load the original
	# versioned kernel and U-Boot ramdisk directly; never rebuild or rename them.
	DBAI_CUSTOM_KERNEL_RELEASE="${modules_release}"

	local manifest="${SDCARD}/etc/dbai-custom-kernel-manifest.txt"
	local boot_config="${SDCARD}/boot/uEnv.txt" boot_kernel_file boot_kernel_name boot_kernel_sha boot_ramdisk_file boot_ramdisk_name boot_ramdisk_sha
	[[ -s "$boot_config" ]] || exit_with_error "Custom bootfs is missing /boot/uEnv.txt"

	boot_kernel_file=""
	if grep -Eq '^[[:space:]]*LINUX[[:space:]]*=' "$boot_config"; then
		for boot_kernel_name in "vmlinuz-${modules_release}" "Image-${modules_release}" "uImage-${modules_release}" "zImage-${modules_release}" vmlinuz Image uImage zImage; do
			if [[ -s "${SDCARD}/boot/${boot_kernel_name}" ]]; then
				boot_kernel_file="${SDCARD}/boot/${boot_kernel_name}"
				break
			fi
		done
	else
		boot_kernel_name="vmlinuz-${modules_release}"
		[[ -s "${SDCARD}/boot/${boot_kernel_name}" ]] && boot_kernel_file="${SDCARD}/boot/${boot_kernel_name}"
	fi
	[[ -n "$boot_kernel_file" ]] || exit_with_error "Custom bootfs requires the KERNEL-derived vmlinuz-${modules_release} unless it has an explicit LINUX= assignment"
	boot_ramdisk_file=""
	if grep -Eq '^[[:space:]]*INITRD[[:space:]]*=' "$boot_config"; then
		for boot_ramdisk_name in "uInitrd-${modules_release}" uInitrd; do
			if [[ -s "${SDCARD}/boot/${boot_ramdisk_name}" ]]; then
				boot_ramdisk_file="${SDCARD}/boot/${boot_ramdisk_name}"
				break
			fi
		done
	else
		boot_ramdisk_name="uInitrd-${modules_release}"
		[[ -s "${SDCARD}/boot/${boot_ramdisk_name}" ]] && boot_ramdisk_file="${SDCARD}/boot/${boot_ramdisk_name}"
	fi
	[[ -n "$boot_ramdisk_file" ]] || exit_with_error "Custom bootfs requires the KERNEL-derived uInitrd-${modules_release} unless it has an explicit INITRD= assignment"
	dbai_sync_custom_kernel_uenv "$boot_config" "$modules_release" "$(basename "$boot_kernel_file")" "$(basename "$boot_ramdisk_file")" || exit_with_error "Unable to align /boot/uEnv.txt with the custom kernel and supplied U-Boot ramdisk"
	if [[ -s "$boot_kernel_file" && ! -e "${SDCARD}/boot/zImage" ]]; then
		cp -f "$boot_kernel_file" "${SDCARD}/boot/zImage"
	fi
	if [[ -s "$boot_ramdisk_file" && ! -e "${SDCARD}/boot/uInitrd" ]]; then
		cp -f "$boot_ramdisk_file" "${SDCARD}/boot/uInitrd"
	fi

	boot_kernel_sha="$(sha256sum "$boot_kernel_file" | awk '{print $1}')"
	boot_ramdisk_sha="$(sha256sum "$boot_ramdisk_file" | awk '{print $1}')"
	[[ "$boot_kernel_sha" =~ ^[[:xdigit:]]{64}$ ]] || exit_with_error "Unable to hash the bundled custom kernel image"
	[[ "$boot_ramdisk_sha" =~ ^[[:xdigit:]]{64}$ ]] || exit_with_error "Unable to hash the original supplied U-Boot ramdisk"
	mkdir -p "${SDCARD}/etc"
	{
		echo "Kernel mode: Custom Kernel"
		echo "Kernel release: ${modules_release}"
		echo "Modules path: /lib/modules/${modules_release}"
		echo "Bundle URL: ${DBAI_KERNEL_BUNDLE_URL}"
		echo "Overlay timestamp UTC: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
		echo "Headers archive layout: ${headers_layout}"
		echo "Boot kernel file: $(basename "$boot_kernel_file")"
		echo "Boot kernel SHA-256: ${boot_kernel_sha}"
		echo "Boot ramdisk file: $(basename "$boot_ramdisk_file")"
		echo "Boot ramdisk SHA-256: ${boot_ramdisk_sha}"
		echo "Inner archive SHA-256:"
		if [[ "${headers_layout}" == "uapi-root" ]]; then
			echo "Header capability: exported userspace UAPI headers only; kernel build headers/Makefile are not included."
		fi
		sha256sum "${cache_dir}/boot.tar" "${cache_dir}/dtb.tar" "${cache_dir}/modules.tar" "${cache_dir}/headers.tar"
	} > "${manifest}"
	[[ -s "${manifest}" ]] || exit_with_error "Custom-kernel manifest was not written to target /etc"
	display_alert "DBAI custom kernel" "Manifest written to /etc/dbai-custom-kernel-manifest.txt; bundle overlay checks completed, hardware boot testing still required" "warn"
}
