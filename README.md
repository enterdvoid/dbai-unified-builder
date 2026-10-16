# DBAI Unified Builder

A GitHub Actions frontend for building ready-to-use Armbian-based firmware for Amlogic TV boxes and official Armbian SBCs.

## Current design

- Manual build workflow with a board selector and a separate custom-board-name field.
- Amlogic TV-box builds use the DBAI Armbian fork; official SBCs use the official `armbian/build` source.
- Batch selection of Debian releases, image profiles, and ext4/btrfs.
- Kernel mode is selectable per run: **Kernel Official**, **Recompile Kernel Official**, **Custom Kernel** (one URL containing four kernel archives), or **Recompile Custom Kernel** (build from a custom Git source URL/ref). Optional patches live in `kernel-patches/meson64-current/`.
- App integration starts with Armbian-maintained Home Assistant and OpenMediaVault extensions plus an experimental CasaOS extension. Select `app_profile=none` to build a generic application image without a bundled app.
- Release publication happens only after all matrix jobs succeed and every image has a manifest and SHA-256 checksum. Partial releases are removed on publication failure.

## Run

1. Open [Actions](../../actions/workflows/dbai-build.yml).
2. Select **Run workflow**.
3. Choose a board. If `custom` is selected, enter the exact board ID in `custom_board_name`.
4. Enter comma-separated release and profile lists. Example: `bookworm,trixie` and `minimal,server,application,desktop`.
5. Select `both` to build ext4 and btrfs variants.
6. Select a kernel mode: **Kernel Official** uses the configured Armbian/DBAI kernel and may reuse matching artifacts; **Recompile Kernel Official** bypasses artifact caches and rebuilds from source; **Custom Kernel** requires one HTTPS bundle URL containing the four matching inner archives; **Recompile Custom Kernel** uses the same `kernel_custom_input` field with a Git URL optionally followed by `#branch:<name>` or `#tag:<name>`. Optional patch files are placed under `kernel-patches/meson64-current/`.
7. Choose an application profile for the `application` image profile. The app is installed only in the application variant. Proxmox modes add separate `proxmox` profile jobs: `official` on Trixie, `community` on Bookworm, or `both` on both releases. The normal application image can still use the selected `app_profile`. Proxmox-specific jobs always use the official Armbian kernel and freeze BSP/kernel package updates.
8. Ensure the repository Actions secret `DBAI_RELEASE_TOKEN` is configured before starting; the plan job checks this before expensive builds.
9. Start the run and inspect each matrix job. The release is created only after all build jobs pass.

The default batch can produce many images. Start with one release, one profile, and ext4 when testing a new board.

## Application status

- **Home Assistant Supervised**: uses Armbian's maintained `applications-ha` extension and its documented release constraints.
- **OpenMediaVault**: uses Armbian's maintained `applications-omv` extension.
- **CasaOS**: experimental first-boot installer that runs on the actual target device to avoid build-runner architecture mismatch.
- **Hermes + 9Router**: selectable profile. 9Router runs as a Docker container; Hermes is installed on first boot and still requires provider/model setup.
- **LightNVR + go2rtc**: selectable profile using the pinned LightNVR 0.37.2 multi-architecture image, which includes go2rtc integration.
- **Proxmox mode selector**: `none`, `official`, `community`, or `both`. Official packages target Trixie; community PXVIRT packages target Bookworm. This is an experimental package-based ARM integration retaining the Armbian kernel, not a supported official Proxmox install on every SBC. Official Arm64 support announced in 2026 is limited to NVIDIA Grace/Vera platforms.

## Important limitations

- The `aml-s9xx-box` target is community/DBAI-specific, not an official Armbian SBC target.
- The custom-kernel bundle must contain four inner tar archives with paths relative to the target root filesystem. See [custom kernel and recompile guide](docs/FOUR-PART-KERNEL.md).
- The current workflow is an initial production-oriented scaffold. Each new board/app combination still requires a successful build and boot test before it should be advertised as supported.
- Never put tokens in workflow inputs, source files, or build artifacts. Configure `DBAI_RELEASE_TOKEN` as a repository Actions secret for release publication.

## Documents

- [Architecture and board policy](docs/ARCHITECTURE.md)
- [Application profiles and Proxmox constraints](docs/APP-PROFILES.md)
- [Custom kernel and recompile guide](docs/FOUR-PART-KERNEL.md)
- [Backup and release recovery](docs/BACKUP-AND-RELEASE.md)
