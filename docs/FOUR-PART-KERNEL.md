# Custom Kernel Bundle and Recompile Modes

The workflow provides four kernel choices:

- **Kernel Official** — keep the Armbian/DBAI kernel selection. A matching cached artifact may be reused; a cache miss can trigger a source build.
- **Recompile Kernel Official** — bypass artifact caches and rebuild the configured Armbian/DBAI kernel from source, retaining the source's normal patch flow.
- **Custom Kernel** — overlay one downloadable bundle containing four matching archives.
- **Recompile Custom Kernel** — build from a user-provided Git kernel source URL/ref using Armbian's kernel build pipeline. This is source compilation, not a prebuilt-kernel overlay.

## Custom Kernel: one URL, four inner archives

Set `custom_kernel_bundle_url` to a public HTTPS URL for one outer `.tar.gz` or `.tar.xz` bundle, for example `6.1.66-DBAI.tar.gz`. The outer archive must contain exactly one of each:

- `boot-6.1.66-DBAI.tar.gz`
- `dtb-amlogic-6.1.66-DBAI.tar.gz`
- `modules-6.1.66-DBAI.tar.gz`
- `header-6.1.66-DBAI.tar.gz`

The version string is an example. The four inner archives must all use the same kernel release and contain paths rooted at the target filesystem:

- boot archive: `boot/` (kernel image and related boot files)
- DTB archive: DTB files under `boot/`
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

Set:
- `custom_kernel_repo_url`: Git URL of the kernel source repository.
- `custom_kernel_repo_ref`: branch or tag to compile (default `main`). Use `tag:v6.1.66` to select a tag explicitly; plain values are treated as branch names.

The workflow passes the repository URL and branch/ref to Armbian's build pipeline and bypasses artifact caches. The repository must be compatible with the selected board's kernel family, toolchain, and expected kernel configuration. Validate this source override with a small single-profile build before a large matrix.

## Where to place kernel patches

Place optional patch files in:

```text
kernel-patches/
└── meson64-current/
    ├── 0001-example-fix.patch
    └── 0002-example-feature.patch
```

For `aml-s9xx-box`, the default patch series is `meson64-current`. The workflow copies `.patch` files from `kernel-patches/<kernel_patch_series>/` into Armbian's `userpatches/kernel/archive/<kernel_patch_series>/` before the build. Use patches written for that exact kernel family/branch and apply them in numeric order. Do not put arbitrary source files or unrelated patches in this folder. If no patch files exist, no additional DBAI patches are applied.

## Compatibility and safety

The kernel image, DTBs, modules, and headers must match each other and the target board:
- same kernel release/version and ABI;
- correct architecture;
- DTB for the exact board/SoC;
- expected boot filenames/configuration;
- compatible firmware, initramfs, and modules.

Use public, immutable HTTPS release URLs for bundle downloads. Do not put private tokens in workflow inputs or URLs.
