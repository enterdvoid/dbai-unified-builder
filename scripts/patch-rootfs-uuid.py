#!/usr/bin/env python3
"""Patch Armbian rootfs creation to use DBAI's fixed ext4/btrfs filesystem UUID.

The UUID is supplied to mkfs itself, so Armbian's subsequent blkid-based
ROOT_PART_UUID, /etc/fstab and boot configuration all derive from the same ID.
"""
from __future__ import annotations

import pathlib
import sys

ROOTFS_UUID = "19450817-1998-4512-a817-202510202026"
UUID_MARKER = "# DBAI-STATIC-ROOTFS-UUID-BEGIN"
MKFS_LINE = (
    'run_host_command_logged mkfs.${mkfs[$ROOTFS_TYPE]} '
    '${mkopts[$ROOTFS_TYPE]} '
    '${mkopts_label[$ROOTFS_TYPE]:+${mkopts_label[$ROOTFS_TYPE]}"$ROOT_FS_LABEL"} '
    '"${rootdevice}"'
)
ROOT_UUID_LINE = 'root_part_uuid="$(blkid -s UUID -o value "${LOOP}p${rootpart}")"'

REPLACEMENT_MKFS = '''{UUID_MARKER}
        if [[ "$ROOTFS_TYPE" == "ext4" || "$ROOTFS_TYPE" == "btrfs" ]]; then
            run_host_command_logged "mkfs.${mkfs[$ROOTFS_TYPE]}" ${mkopts[$ROOTFS_TYPE]} -U "@UUID@" ${mkopts_label[$ROOTFS_TYPE]:+${mkopts_label[$ROOTFS_TYPE]}"$ROOT_FS_LABEL"} "${rootdevice}"
        else
            __ORIGINAL_MKFS__
        fi
        # DBAI-STATIC-ROOTFS-UUID-END'''.replace("{UUID_MARKER}", UUID_MARKER).replace("__ORIGINAL_MKFS__", MKFS_LINE).replace("@UUID@", ROOTFS_UUID)

REPLACEMENT_ROOT_UUID = f'''{ROOT_UUID_LINE}
        if [[ "$ROOTFS_TYPE" == "ext4" || "$ROOTFS_TYPE" == "btrfs" ]]; then
            [[ "$root_part_uuid" == "{ROOTFS_UUID}" ]] || exit_with_error "DBAI rootfs UUID verification failed" "$root_part_uuid"
        fi'''


def replace_once(content: str, old: str, new: str, label: str) -> str:
    count = content.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one {label} anchor in Armbian partitioning.sh, found {count}. Source was not modified.")
    return content.replace(old, new, 1)


def patch(path: pathlib.Path) -> None:
    content = path.read_text(encoding="utf-8")

    if UUID_MARKER in content:
        if f'-U "{ROOTFS_UUID}"' in content and f'"$root_part_uuid" == "{ROOTFS_UUID}"' in content:
            print(f"DBAI static rootfs UUID patch already installed: {path}")
            return
        raise SystemExit("Incomplete DBAI static rootfs UUID patch detected; refusing to continue.")

    # Ensure the target source has the expected Armbian mkfs and UUID flow.
    content = replace_once(content, MKFS_LINE, REPLACEMENT_MKFS, "rootfs mkfs command")
    content = replace_once(content, ROOT_UUID_LINE, REPLACEMENT_ROOT_UUID, "rootfs UUID readback")
    path.write_text(content, encoding="utf-8")
    print(f"Installed fixed rootfs UUID {ROOTFS_UUID} for ext4 and btrfs in {path}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {pathlib.Path(sys.argv[0]).name} /path/to/lib/functions/image/partitioning.sh")
    path = pathlib.Path(sys.argv[1])
    if not path.is_file():
        raise SystemExit(f"Armbian partitioning source not found: {path}")
    patch(path)


if __name__ == "__main__":
    main()
