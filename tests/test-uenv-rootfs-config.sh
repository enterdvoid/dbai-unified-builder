#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

function display_alert() { :; }

eval "$(sed -n '/function dbai_configure_uenv_rootfs() {/,/^}/p' "$repo_root/extensions/dbai-custom-bootfs.sh")"

# Test BTRFS configuration
cat > "$tmp/uEnv.txt" <<'UENV'
KERNEL=6.1.66-DBAI
FDT=/dtb/amlogic/meson-gxl-s905x-b860h.dtb
UBOOT=u-boot-p212.bin
APPEND=root=UUID=19450817-1998-4512-a817-202510202026 rootflags=data=writeback rw rootfstype=ext4 console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 max_loop=128 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
UENV

ROOTFS_TYPE="btrfs" dbai_configure_uenv_rootfs "$tmp/uEnv.txt"

grep -q "rootfstype=btrfs" "$tmp/uEnv.txt" || { echo "FAIL: rootfstype=btrfs missing" >&2; exit 1; }
grep -q "rootflags=subvol=@,compress=zstd:6" "$tmp/uEnv.txt" || { echo "FAIL: rootflags missing subvol=@ or compress=zstd:6" >&2; exit 1; }
grep -q "console=tty0" "$tmp/uEnv.txt" || { echo "FAIL: console=tty0 missing in btrfs uEnv.txt" >&2; exit 1; }
grep -q "no_console_suspend" "$tmp/uEnv.txt" || { echo "FAIL: no_console_suspend missing in btrfs uEnv.txt" >&2; exit 1; }
grep -q "console=ttyAML0,115200n8" "$tmp/uEnv.txt" || { echo "FAIL: console=ttyAML0 missing" >&2; exit 1; }

# Test EXT4 configuration (must NOT alter ext4 APPEND)
cat > "$tmp/uEnv_ext4.txt" <<'UENV'
KERNEL=6.1.66-DBAI
FDT=/dtb/amlogic/meson-gxl-s905x-b860h.dtb
UBOOT=u-boot-p212.bin
APPEND=root=UUID=19450817-1998-4512-a817-202510202026 rootflags=data=writeback rw rootfstype=ext4 console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 max_loop=128 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
UENV

ROOTFS_TYPE="ext4" dbai_configure_uenv_rootfs "$tmp/uEnv_ext4.txt"

grep -q "rootfstype=ext4" "$tmp/uEnv_ext4.txt" || { echo "FAIL: ext4 altered" >&2; exit 1; }
grep -q "rootflags=data=writeback" "$tmp/uEnv_ext4.txt" || { echo "FAIL: ext4 rootflags altered" >&2; exit 1; }

echo "PASS: dbai_configure_uenv_rootfs correctly configures BTRFS while preserving HDMI console (tty0, no_console_suspend) and leaves EXT4 unchanged."
