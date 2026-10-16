# DBAI2K26 Unified Builder

A GitHub Actions frontend for building ready-to-use DBAI2K26-branded Armbian-based firmware for Amlogic TV boxes and official Armbian SBCs.

## Current design

- Manual build workflow with a board selector and a separate custom-board-name field.
- Builds prefer the official `armbian/build` framework to maximize compatibility with Armbian's remote OCI artifact cache; only boards absent upstream fall back to the DBAI fork.
- Release dropdown supports all listed Debian releases, Ubuntu LTS releases, Debian-only, Ubuntu-only, or a custom comma-separated list.
- Kernel mode is selectable per run: **Kernel Official** reuses a matching official Armbian OCI kernel artifact and fails on cache miss rather than compiling; **Recompile Kernel Official** bypasses the artifact cache and builds from source; **Custom Kernel** uses one URL containing four kernel archives; **Recompile Custom Kernel** builds from a custom Git source URL/ref. Optional patches live in `kernel-patches/meson64-current/`. See [kernel mode behavior](docs/KERNEL-MODES.md).
- Four independent checkbox inputs select Minimal, Server, Application, and Desktop images. The application selector only affects Application images; choose `none` for a generic image without an extra app. Application jobs are skipped on OS releases the selected app does not support.
- Published firmware filenames use the `DBAI2K26-Armbian_...` prefix and normalize application suffixes so they appear once. Release publication happens only after all matrix jobs succeed. Releases contain firmware images and one consolidated `SHA256SUMS` file; partial releases are removed on publication failure. Runner reports record CPU/runner identity, RAM and swap, disk capacity/usage/free space, block devices, and Docker storage immediately before and after each firmware build.

## Run

1. Open [Actions](../../actions/workflows/dbai-build.yml).
2. Select **Run workflow**.
3. Choose a board. If `custom` is selected, enter the exact board ID in `custom_board_name`.
4. Choose **Armbian Version Release**: **All** (`bullseye,bookworm,trixie,forky,jammy,noble,resolute`), **Ubuntu Only** (`jammy,noble,resolute`), **Debian Only** (`bullseye,bookworm,trixie,forky`), or **Custom**. For Custom, enter comma-separated codenames; default is `trixie,resolute`.
5. Tick the image types you want: **Minimal**, **Server**, **Application**, and/or **Desktop**. Select at least one. These are independent checkboxes, not a comma-separated text field.
6. Choose **Application to install**. This affects only Application images. Choose `none` for a generic Application image without a bundled app. Incompatible release/application combinations are skipped; other selected image types for those releases still build.
7. Select `both` to build ext4 and btrfs variants.
8. Select a kernel mode: **Kernel Official** uses a matching cached official Armbian OCI kernel artifact only and stops with an explicit error if the cache misses; **Recompile Kernel Official** bypasses artifact caches and rebuilds from source; **Custom Kernel** requires one HTTPS bundle URL containing the four matching inner archives; **Recompile Custom Kernel** uses the same `kernel_custom_input` field with a Git URL optionally followed by `#branch:<name>` or `#tag:<name>`. Optional patch files are placed under `kernel-patches/meson64-current/`. See [kernel mode behavior](docs/KERNEL-MODES.md).
9. Ensure the repository Actions secret `DBAI_RELEASE_TOKEN` is configured before starting; the plan job checks this before expensive builds.
10. Start the run and inspect each matrix job. The release is created only after all build jobs pass.

Compatibility rules: Proxmox Community uses Bookworm; Proxmox Official uses Trixie; Proxmox Both maps Bookworm to Community and Trixie to Official. Home Assistant uses Debian Bullseye/Bookworm/Trixie. OpenMediaVault, CasaOS, Hermes, and LightNVR variants use Bookworm/Trixie. Incompatible Application rows are skipped rather than replaced with generic images.

The default batch can produce many images. Start with one release, one image type, and ext4 when testing a new board.

## Application status

- **Home Assistant Supervised**: uses Armbian's maintained `applications-ha` extension and its documented release constraints.
- **OpenMediaVault**: uses Armbian's maintained `applications-omv` extension.
- **CasaOS**: experimental first-boot installer that runs on the actual target device to avoid build-runner architecture mismatch.
- **Hermes + 9Router**: selectable profile. 9Router runs as a Docker container; Hermes is installed on first boot and still requires provider/model setup.
- **LightNVR + go2rtc**: selectable profile using the pinned LightNVR 0.37.2 multi-architecture image, which includes go2rtc integration.
- **Proxmox application variants**: `proxmox-official` targets Trixie, `proxmox-community` targets Bookworm, and `proxmox-both` generates both variants. This is an experimental package-based ARM integration retaining the Armbian kernel, not a supported official Proxmox install on every SBC. Official Arm64 support announced in 2026 is limited to NVIDIA Grace/Vera platforms.

## Important limitations

- The `aml-s9xx-box` target is community/DBAI-specific, not an official Armbian SBC target.
- Custom kernel modes require `platform/bootfs_custom_kernel.tar.gz`. Custom Kernel also requires one bundle URL containing four matching inner archives. See [custom kernel and recompile guide](docs/FOUR-PART-KERNEL.md).
- The current workflow is an initial production-oriented scaffold. Each new board/app combination still requires a successful build and boot test before it should be advertised as supported.
- Never put tokens in workflow inputs, source files, or build artifacts. Configure `DBAI_RELEASE_TOKEN` as a repository Actions secret for release publication.

## Documents

- [Architecture and board policy](docs/ARCHITECTURE.md)
- [Application profiles and Proxmox constraints](docs/APP-PROFILES.md)
- [Custom kernel and recompile guide](docs/FOUR-PART-KERNEL.md)
- [Backup and release recovery](docs/BACKUP-AND-RELEASE.md)
- [Workflow history cleanup](.github/workflows/delete-workflow-history.yml)
