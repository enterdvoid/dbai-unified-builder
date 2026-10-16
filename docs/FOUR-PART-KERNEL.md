# Optional Four-Part Custom Kernel

The default `kernel_mode=official` leaves Armbian's normal kernel, modules, DTBs, and headers untouched.

Select `custom-four-part` only when all four archive URLs are available:

1. **Boot archive** — a tar archive whose paths begin with `boot/`; includes the intended kernel image and boot-side kernel files.
2. **DTB archive** — a tar archive containing device-tree blobs under `boot/` (for example `boot/dtb/` or the board's matching `boot/dtb-<version>/` directory).
3. **Modules archive** — a tar archive whose paths begin with `lib/modules/<kernel-release>/`; includes module files and dependency metadata where applicable.
4. **Headers archive** — a tar archive whose paths begin with `usr/src/` and/or the matching `lib/modules/<kernel-release>/build` structure.

Archives are extracted into the target root filesystem after the base image has been prepared. Paths must be relative to the target root (no leading slash and no `..` traversal). The workflow verifies that expected boot files, at least one DTB, kernel modules, and headers exist after overlay, then records SHA-256 hashes in the image manifest.

## Important compatibility checks

A successful overlay does not guarantee a bootable kernel. The four parts must match each other and the target board:

- identical kernel release/version across the boot image, modules and headers;
- correct architecture and ABI;
- DTB for the exact board and SoC;
- expected boot configuration and filenames for the board's bootloader;
- required firmware and initramfs behavior.

The custom mode is optional and experimental until the resulting image boots and its devices are tested on target hardware. Keep the official-kernel image as a separate artifact for comparison.

Do not put private tokens into archive URLs. Use public, immutable HTTPS URLs (such as versioned release assets).
