#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 4 ]]; then
  echo "Usage: $0 IMAGE.img[.xz|.gz|.zst] EXPECTED_KERNEL_RELEASE [IMAGE_SIZE_MB] [EXPECTED_BOOT_PARTITION_MIB]" >&2
  exit 2
fi

echo "VERIFY: starting custom-kernel image inspection"
image_path="$(realpath "$1")"
expected_release="$2"
image_size_mb="${3:-4096}"
expected_boot_partition_mib="${4:-0}"
[[ -f "$image_path" ]] || { echo "::error::Image file does not exist: $image_path"; exit 2; }
[[ "$expected_release" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo "::error::Unsafe expected kernel release."; exit 2; }
[[ "$image_size_mb" =~ ^[0-9]+$ ]] || { echo "::error::IMAGE_SIZE_MB must be an integer."; exit 2; }
[[ "$expected_boot_partition_mib" =~ ^[0-9]+$ ]] || { echo "::error::EXPECTED_BOOT_PARTITION_MIB must be a non-negative integer."; exit 2; }

image_dir="$(dirname "$image_path")"
available_bytes="$(df -B1 --output=avail "$image_dir" | awk 'NR==2 {print $1}')"
required_bytes=$((image_size_mb * 1024 * 1024 + 1024 * 1024 * 1024))
if (( available_bytes < required_bytes )); then
  echo "::error::Not enough free disk space to inspect the custom-kernel image read-only: available=$((available_bytes / 1024 / 1024 / 1024)) GiB, required at least $((required_bytes / 1024 / 1024 / 1024)) GiB."
  exit 1
fi

tmp_dir="$(mktemp -d "${image_dir}/.dbai-custom-kernel-verify.XXXXXX")"
raw_image="${tmp_dir}/image.raw"
root_mount="${tmp_dir}/root"
mkdir -p "$root_mount"
loop_device=""
mounted_dirs=()

cleanup() {
  set +e
  for ((i=${#mounted_dirs[@]}-1; i>=0; i--)); do
    mountpoint -q "${mounted_dirs[$i]}" && sudo umount "${mounted_dirs[$i]}"
  done
  if [[ -n "$loop_device" ]]; then
    sudo losetup -d "$loop_device"
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "VERIFY: checking/decompressing $image_path"
case "$image_path" in
  *.img.xz)
    xz --test "$image_path"
    xz --decompress --stdout "$image_path" > "$raw_image"
    ;;
  *.img.gz)
    gzip --test "$image_path"
    gzip --decompress --stdout "$image_path" > "$raw_image"
    ;;
  *.img.zst)
    command -v zstd >/dev/null 2>&1 || { echo "::error::zstd is required to inspect $image_path."; exit 1; }
    zstd --test "$image_path"
    zstd --decompress --stdout "$image_path" > "$raw_image"
    ;;
  *.img)
    cp --reflink=auto "$image_path" "$raw_image"
    ;;
  *)
    echo "::error::Unsupported custom-kernel image format: $image_path"
    exit 2
    ;;
esac

echo "VERIFY: decompression complete; attaching partition-aware loop device"
loop_device="$(sudo losetup --find --show --partscan "$raw_image")"
echo "VERIFY: loop device is $loop_device"
if ! timeout 30s sudo udevadm settle; then
  echo "::error::Timed out waiting for udev to discover image partitions."
  sudo lsblk -f "$loop_device" || true
  exit 1
fi
sudo lsblk -f "$loop_device" || true

root_part=""
root_fstype=""
root_size=0
while read -r device fstype size_bytes; do
  [[ -n "${device:-}" && -n "${fstype:-}" && "${size_bytes:-}" =~ ^[0-9]+$ ]] || continue
  case "${fstype,,}" in
    ext4|btrfs)
      if (( size_bytes > root_size )); then
        root_part="$device"
        root_fstype="${fstype,,}"
        root_size="$size_bytes"
      fi
      ;;
  esac
done < <(sudo lsblk --bytes --noheadings --raw --paths --output NAME,FSTYPE,SIZE "$loop_device")

[[ -n "$root_part" ]] || {
  echo "::error::Could not identify an ext4 or btrfs root filesystem in $image_path."
  sudo lsblk -f "$loop_device" || true
  exit 1
}

echo "VERIFY: selected root partition $root_part ($root_fstype, $root_size bytes)"
case "$root_fstype" in
  ext4) timeout 30s sudo mount -o ro,noload "$root_part" "$root_mount" ;;
  btrfs) timeout 30s sudo mount -o ro "$root_part" "$root_mount" ;;
esac
echo "VERIFY: root filesystem mounted read-only"
mounted_dirs+=("$root_mount")

modules_dir="${root_mount}/lib/modules/${expected_release}"
[[ -d "$modules_dir" ]] || {
  echo "::error::Selected root filesystem is missing /lib/modules/$expected_release."
  sudo ls -la "${root_mount}/lib/modules" || true
  exit 1
}
[[ -f "${modules_dir}/modules.dep" ]] || { echo "::error::Image is missing /lib/modules/$expected_release/modules.dep."; exit 1; }
module_file="$(find "$modules_dir" -type f -name '*.ko*' -print -quit)"
[[ -n "$module_file" ]] || { echo "::error::Image contains no kernel modules under /lib/modules/$expected_release."; exit 1; }

manifest="${root_mount}/etc/dbai-custom-kernel-manifest.txt"
if [[ ! -f "$manifest" ]]; then
  # Support already-built/custom bundles using the former location, but prefer
  # /etc because it survives normal cleanup of ephemeral root-home files.
  manifest="${root_mount}/root/DBAI-CUSTOM-KERNEL-MANIFEST.txt"
fi
[[ -f "$manifest" ]] || {
  echo "::error::Custom-kernel manifest missing from root filesystem (checked /etc/dbai-custom-kernel-manifest.txt and /root/DBAI-CUSTOM-KERNEL-MANIFEST.txt)."
  echo "Root filesystem top-level entries:"
  ls -la "$root_mount" || true
  echo "Kernel module tree present: $modules_dir"
  exit 1
}
echo "VERIFY: found custom-kernel manifest at $manifest"
grep -Fqx "Kernel mode: Custom Kernel" "$manifest" || { echo "::error::Image manifest does not identify Custom Kernel mode: $manifest"; exit 1; }
grep -Fqx "Kernel release: $expected_release" "$manifest" || {
  echo "::error::Kernel release in image manifest does not match expected release $expected_release (manifest $manifest)."
  cat "$manifest"
  exit 1
}


# A Custom Kernel image must not retain distro kernel trees or the stray root
# directory created by some archive layouts.
if [[ -e "$root_mount/$expected_release" || -L "$root_mount/$expected_release" ]]; then
  echo "::error::Unexpected kernel-release directory exists at image root: /$expected_release."
  exit 1
fi
for modules_root in "$root_mount/lib/modules" "$root_mount/usr/lib/modules"; do
  # /usr/lib/modules may be an absolute symlink to the host-visible /lib/modules path.
  # /lib/modules is checked directly, so do not follow a symlink outside the mounted image.
  [[ -L "$modules_root" ]] && continue
  [[ -d "$modules_root" ]] || continue
  for entry in "$modules_root"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    [[ "$(basename "$entry")" == "$expected_release" ]] || {
      echo "::error::Non-custom kernel module tree remains in Custom Kernel image: $(realpath --relative-to="$root_mount" "$entry")."
      exit 1
    }
  done
done
for entry in "$root_mount/usr/lib"/linux-image-*; do
  [[ -e "$entry" || -L "$entry" ]] || continue
  [[ "$(basename "$entry")" == "linux-image-$expected_release" ]] || {
    echo "::error::Distro kernel image payload remains in Custom Kernel image: $(realpath --relative-to="$root_mount" "$entry")."
    exit 1
  }
done

headers_layout="$(sed -n 's/^Headers archive layout: //p' "$manifest" | head -n 1)"
# Ensure no distro header tree remains in /usr/src. UAPI-only and full build
# headers are kept in distinct, release-specific directories.
for entry in "$root_mount/usr/src"/linux-headers-* "$root_mount/usr/src"/linux-uapi-headers-*; do
  [[ -e "$entry" || -L "$entry" ]] || continue
  name="$(basename "$entry")"
  case "$headers_layout" in
    uapi-root) [[ "$name" == "linux-uapi-headers-$expected_release" ]] || {
      echo "::error::Non-custom or unexpected kernel headers remain: /usr/src/$name."
      exit 1
    } ;;
    header-root|target-root) [[ "$name" == "linux-headers-$expected_release" ]] || {
      echo "::error::Non-custom or unexpected kernel headers remain: /usr/src/$name."
      exit 1
    } ;;
  esac
done


case "$headers_layout" in
  uapi-root)
    uapi_dir="$root_mount/usr/src/linux-uapi-headers-$expected_release/include"
    [[ -d "$uapi_dir" ]] || { echo "::error::Image is missing separately staged UAPI headers for $expected_release."; exit 1; }
    [[ -n "$(find "$uapi_dir" -type f -print -quit)" ]] || { echo "::error::UAPI headers directory is empty."; exit 1; }
    if [[ -L "$modules_dir/build" || -L "$modules_dir/source" ]]; then
      echo "::error::UAPI-only bundle left misleading build/source symlinks in /lib/modules/$expected_release."
      exit 1
    fi
    echo "VERIFY: custom bundle UAPI headers staged for $expected_release (UAPI only; not a full kernel build-header tree)"
    ;;
  header-root|target-root)
    headers_dir="${root_mount}/usr/src/linux-headers-${expected_release}"
    [[ -f "${headers_dir}/Makefile" ]] || {
      echo "::error::Custom kernel build headers are missing at /usr/src/linux-headers-${expected_release}/Makefile."
      exit 1
    }
    [[ -f "${headers_dir}/include/config/kernel.release" ]] || {
      echo "::error::Custom kernel headers lack include/config/kernel.release; cannot prove their release."
      exit 1
    }
    header_release="$(tr -d '\r\n' < "${headers_dir}/include/config/kernel.release")"
    [[ "$header_release" == "$expected_release" ]] || {
      echo "::error::Header release mismatch: modules use $expected_release but headers declare $header_release."
      exit 1
    }
    [[ -L "${modules_dir}/build" ]] || {
      echo "::error::/lib/modules/${expected_release}/build does not point to the custom kernel headers."
      exit 1
    }
    build_target="$(readlink "${modules_dir}/build")"
    [[ "$build_target" == "/usr/src/linux-headers-${expected_release}" ]] || {
      echo "::error::Kernel modules build symlink points to unexpected headers: $build_target."
      exit 1
    }
    echo "VERIFY: custom kernel headers release matches modules: $header_release"
    ;;
  *)
    echo "::error::Unknown headers archive layout recorded in image manifest: ${headers_layout:-missing}"
    exit 1
    ;;
esac

# Find the actual boot filesystem, not merely the rootfs /boot directory.
# Custom boot images may have a separate FAT or ext4 partition.
candidate_index=0
boot_mount=""
boot_kernel=""
boot_dtb=""
boot_partition_size_bytes=0
while read -r size_bytes device fstype; do
  [[ -n "${device:-}" && -n "${fstype:-}" ]] || continue
  [[ "$device" != "$root_part" ]] || continue
  case "${fstype,,}" in
    vfat|fat|fat32|ext2|ext3|ext4|btrfs|xfs) ;;
    *) continue ;;
  esac
  echo "VERIFY: inspecting possible boot partition $device ($fstype, $size_bytes bytes)"
  candidate_mount="${tmp_dir}/partition-${candidate_index}"
  mkdir -p "$candidate_mount"
  candidate_index=$((candidate_index + 1))
  if ! timeout 30s sudo mount -o ro "$device" "$candidate_mount" 2>/dev/null; then
    continue
  fi
  kernel_file="$(find "$candidate_mount" -maxdepth 5 -type f \( -name 'Image' -o -name 'Image-*' -o -name 'vmlinuz*' -o -name 'uImage' -o -name 'zImage' \) -print -quit)"
  dtb_file="$(find "$candidate_mount" -type f -name '*.dtb' -print -quit)"
  if [[ -n "$kernel_file" && -n "$dtb_file" ]]; then
    if (( expected_boot_partition_mib > 0 )); then
      expected_boot_bytes=$((expected_boot_partition_mib * 1024 * 1024))
      if [[ "$size_bytes" != "$expected_boot_bytes" ]]; then
        sudo umount "$candidate_mount"
        echo "::error::Boot partition size mismatch: expected ${expected_boot_partition_mib} MiB (${expected_boot_bytes} bytes), found ${size_bytes} bytes ($device)." >&2
        exit 1
      fi
      echo "VERIFY: boot partition size matches expected ${expected_boot_partition_mib} MiB (${size_bytes} bytes)"
    fi
    boot_mount="$candidate_mount"
    boot_kernel="$kernel_file"
    boot_dtb="$dtb_file"
    boot_partition_size_bytes="$size_bytes"
    mounted_dirs+=("$candidate_mount")
    break
  fi
  sudo umount "$candidate_mount"
done < <(
  sudo lsblk --bytes --noheadings --raw --paths --output NAME,FSTYPE,SIZE "$loop_device" |
    awk -v root="$root_part" '$1 != root && $2 != "" && $3 ~ /^[0-9]+$/ {print $3, $1, $2}' |
    sort -n
)

if [[ -z "$boot_mount" ]]; then
  if (( expected_boot_partition_mib > 0 )); then
    echo "::error::A separate boot partition of ${expected_boot_partition_mib} MiB was required, but no partition containing both kernel and DTB was found."
    exit 1
  fi
  if (( candidate_index > 0 )); then
    echo "::error::A separate boot partition exists, but no partition contains both a kernel image and DTB."
    exit 1
  fi
  boot_mount="${root_mount}/boot"
  boot_kernel="$(find "$boot_mount" -maxdepth 5 -type f \( -name 'Image' -o -name 'Image-*' -o -name 'vmlinuz*' -o -name 'uImage' -o -name 'zImage' \) -print -quit 2>/dev/null || true)"
  boot_dtb="$(find "$boot_mount" -type f -name '*.dtb' -print -quit 2>/dev/null || true)"
fi

[[ -n "$boot_kernel" ]] || { echo "::error::Built image has no kernel image in its boot filesystem."; exit 1; }
[[ -n "$boot_dtb" ]] || { echo "::error::Built image has no DTB in its boot filesystem."; exit 1; }

echo "VERIFY: boot files and installed kernel modules verified"
echo "Verified custom-kernel image contents:"
echo "  Image: $image_path"
echo "  Root filesystem: $root_part ($root_fstype)"
echo "  Installed kernel release: $expected_release"
echo "  Modules: $module_file"
echo "  Headers layout: $headers_layout"
echo "  Boot kernel: $boot_kernel"
echo "  Boot DTB: $boot_dtb"
if (( boot_partition_size_bytes > 0 )); then
  echo "  Boot partition size: $((boot_partition_size_bytes / 1024 / 1024)) MiB ($boot_partition_size_bytes bytes)"
fi
