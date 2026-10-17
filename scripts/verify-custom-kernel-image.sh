#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  echo "Usage: $0 IMAGE.img[.xz|.gz|.zst] EXPECTED_KERNEL_RELEASE [IMAGE_SIZE_MB]" >&2
  exit 2
fi

echo "VERIFY: starting custom-kernel image inspection"
image_path="$(realpath "$1")"
expected_release="$2"
image_size_mb="${3:-4096}"
[[ -f "$image_path" ]] || { echo "::error::Image file does not exist: $image_path"; exit 2; }
[[ "$expected_release" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo "::error::Unsafe expected kernel release."; exit 2; }
[[ "$image_size_mb" =~ ^[0-9]+$ ]] || { echo "::error::IMAGE_SIZE_MB must be an integer."; exit 2; }

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

manifest="${root_mount}/root/DBAI-CUSTOM-KERNEL-MANIFEST.txt"
echo "VERIFY: checking manifest and modules release $expected_release"
[[ -f "$manifest" ]] || { echo "::error::Custom-kernel manifest missing from built image."; exit 1; }
grep -Fqx "Kernel mode: Custom Kernel" "$manifest" || { echo "::error::Image manifest does not identify Custom Kernel mode."; exit 1; }
grep -Fqx "Kernel release: $expected_release" "$manifest" || {
  echo "::error::Kernel release in image manifest does not match expected release $expected_release."
  cat "$manifest"
  exit 1
}

modules_dir="${root_mount}/lib/modules/${expected_release}"
[[ -d "$modules_dir" ]] || { echo "::error::Image is missing /lib/modules/$expected_release."; exit 1; }
[[ -f "${modules_dir}/modules.dep" ]] || { echo "::error::Image is missing /lib/modules/$expected_release/modules.dep."; exit 1; }
module_file="$(find "$modules_dir" -type f -name '*.ko*' -print -quit)"
[[ -n "$module_file" ]] || { echo "::error::Image contains no kernel modules under /lib/modules/$expected_release."; exit 1; }

headers_layout="$(sed -n 's/^Headers archive layout: //p' "$manifest" | head -n 1)"
case "$headers_layout" in
  uapi-root)
    uapi_dir="${root_mount}/usr/src/linux-uapi-headers-${expected_release}/include"
    [[ -d "$uapi_dir" ]] || { echo "::error::Image is missing separately staged UAPI headers for $expected_release."; exit 1; }
    [[ -n "$(find "$uapi_dir" -type f -print -quit)" ]] || { echo "::error::UAPI headers directory is empty."; exit 1; }
    if [[ -L "${modules_dir}/build" || -L "${modules_dir}/source" ]]; then
      echo "::error::UAPI-only bundle left misleading build/source symlinks in /lib/modules/$expected_release."
      exit 1
    fi
    ;;
  header-root|target-root)
    if [[ ! -f "${modules_dir}/build/Makefile" ]] && [[ -z "$(find "${root_mount}/usr/src" -type f -name Makefile -print -quit 2>/dev/null)" ]]; then
      echo "::error::Image manifest claims build headers, but no matching kernel Makefile is present."
      exit 1
    fi
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
    boot_mount="$candidate_mount"
    boot_kernel="$kernel_file"
    boot_dtb="$dtb_file"
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
