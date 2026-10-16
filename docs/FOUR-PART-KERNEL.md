# Custom Kernel Bundle and Recompile Modes

The workflow provides four kernel choices:

- **Kernel Official** — keep the Armbian/DBAI kernel selection. A matching cached artifact may be reused; a cache miss can trigger a source build.
- **Recompile Kernel Official** — bypass artifact caches and rebuild the configured Armbian/DBAI kernel from source, retaining the source's normal patch flow.
- **Custom Kernel** — overlay one downloadable bundle containing four matching archives.
- **Recompile Custom Kernel** — build from a user-provided Git kernel source URL/ref using Armbian's kernel build pipeline. This is source compilation, not a prebuilt-kernel overlay.

## Custom Kernel: one URL, four inner archives

Set `kernel_custom_input` to a public HTTPS URL for one outer `.tar.gz` or `.tar.xz` bundle, for example `6.1.66-DBAI.tar.gz`. The outer archive must contain exactly one of each:

- `boot-6.1.66-DBAI.tar.gz`
- `dtb-amlogic-6.1.66-DBAI.tar.gz`
- `modules-6.1.66-DBAI.tar.gz`
- `header-6.1.66-DBAI.tar.gz`

The version string is an example. The four inner archives must all use the same kernel release and contain paths rooted at the target filesystem:

- boot archive: either `boot/` (kernel image and related boot files), or boot-partition-root entries such as `Image` / `uInitrd` (the workflow normalizes these into `boot/`)
- DTB archive: at least one `.dtb` file; the workflow normalizes common layouts such as `boot/dtb/`, `dtb/amlogic/`, `amlogic/`, and root-level DTBs into the image's `/boot/dtb/` tree
- modules archive: `lib/modules/<kernel-release>/`
- header archive: `usr/src/` and/or matching module build links

Example staging layout before creating the outer bundle:

```text
6.1.66-DBAI/
├── boot-6.1.66-DBAI.tar.gz
├── dtb-amlogic-6.1.66-DBAI.tar.gz
├── header-6.1.66-DBAI.tar.gz
└── modules-6.1.66-DBAI.tar.gz
```

Create the outer bundle from the directory containing those four files:

```bash
tar -czf 6.1.66-DBAI.tar.gz -C 6.1.66-DBAI .
```

The workflow validates the outer archive, each inner archive, safe relative paths, expected content roots, and the resulting files before continuing. It writes a manifest with SHA-256 hashes. A successful overlay does not guarantee bootability; test on the exact target hardware.

## Recompile Custom Kernel

Set `kernel_custom_input` to a public HTTPS Git URL. Append `#branch:<name>` or `#tag:<name>` to select a ref; without a suffix, the default branch `main` is used. Examples: `https://github.com/example/linux.git#branch:linux-6.1.y` or `https://github.com/example/linux.git#tag:v6.1.66`.

The workflow splits the single input at `#`, passes the repository URL and branch/ref to Armbian's build pipeline, and bypasses artifact caches. The repository must be compatible with the selected board's kernel family, toolchain, and expected kernel configuration. Validate this source override with a small single-profile build before a large matrix.

## Where to place kernel patches

Place optional patch files in:

```text
kernel-patches/
└── meson64-current/
    ├── 0001-example-fix.patch
    └── 0002-example-feature.patch
```

For `aml-s9xx-box`, the default patch series is `meson64-current`. The workflow copies `.patch` files from `kernel-patches/meson64-current/` into Armbian's `userpatches/kernel/archive/<kernel_patch_series>/` before the build. Use patches written for that exact kernel family/branch and apply them in numeric order. Do not put arbitrary source files or unrelated patches in this folder. If no patch files exist, no additional DBAI patches are applied.

## Compatibility and safety

The kernel image, DTBs, modules, and headers must match each other and the target board:
- same kernel release/version and ABI;
- correct architecture;
- DTB for the exact board/SoC;
- expected boot filenames/configuration;
- compatible firmware, initramfs, and modules.

Use public, immutable HTTPS release URLs for bundle downloads. Do not put private tokens in workflow inputs or URLs.


## Custom bootfs overlay

Both **Custom Kernel** and **Recompile Custom Kernel** require the repository file:

```text
platform/bootfs_custom_kernel.tar.gz
```

This archive represents the contents of the boot partition itself. Archive entries should be relative to the boot partition root (for example `s905_autoscript`, `extlinux/extlinux.conf`, and any other scripts/configuration you intend to supply), not wrapped inside another `boot/` directory. Create it from a directory containing the intended bootfs files:

```bash
tar -czf bootfs_custom_kernel.tar.gz -C /path/to/your-bootfs .
```

For either custom-kernel mode, the workflow removes the default files under the image's `/boot` directory and extracts this archive. In **Custom Kernel**, the four-part kernel bundle is overlaid afterwards so its kernel and DTBs take precedence where paths collide. In **Recompile Custom Kernel**, the workflow preserves the freshly built kernel image and compiled DTB files, replaces the other boot files with your archive, and restores those kernel artifacts.

The archive is intentionally not included in this repository yet. Add your own file at the exact path above before starting either custom-kernel mode; the planning job will fail early if the archive is missing or invalid.
