# DBAI Unified Builder

A GitHub Actions frontend for building ready-to-use Armbian-based firmware for Amlogic TV boxes and official Armbian SBCs.

## Current design

- Manual build workflow with a board selector and a separate custom-board-name field.
- Amlogic TV-box builds use the DBAI Armbian fork; official SBCs use the official `armbian/build` source.
- Batch selection of Debian releases, image profiles, and ext4/btrfs.
- Official kernel is the default. Optional custom-kernel mode overlays four validated archive inputs: boot, DTB, modules, and headers.
- App integration starts with Armbian-maintained Home Assistant and OpenMediaVault extensions plus an experimental CasaOS extension.
- Release publication happens only after all matrix jobs succeed and every image has a manifest and SHA-256 checksum. Partial releases are removed on publication failure.

## Run

1. Open [Actions](../../actions/workflows/dbai-build.yml).
2. Select **Run workflow**.
3. Choose a board. If `custom` is selected, enter the exact board ID in `custom_board_name`.
4. Enter comma-separated release and profile lists. Example: `bookworm,trixie` and `minimal,server,application,desktop`.
5. Select `both` to build ext4 and btrfs variants.
6. Keep `kernel_mode=official` unless all four custom-kernel archives are ready.
7. Choose an application profile for the `application` image profile. The app is installed only in the application variant.
8. Start the run and inspect each matrix job. The release is created only after all build jobs pass.

The default batch can produce many images. Start with one release, one profile, and ext4 when testing a new board.

## Application status

- **Home Assistant Supervised**: uses Armbian's maintained `applications-ha` extension and its documented release constraints.
- **OpenMediaVault**: uses Armbian's maintained `applications-omv` extension.
- **CasaOS**: experimental extension that invokes the upstream installer in the target root filesystem; validate the generated image on the target before relying on it.
- **Hermes + 9Router**: selectable profile. 9Router runs as a Docker container; Hermes is installed on first boot and still requires provider/model setup.
- **LightNVR + go2rtc**: selectable profile using the pinned LightNVR 0.37.2 multi-architecture image, which includes go2rtc integration.
- **Proxmox VE**: not offered for general TV boxes/SBCs. Official Arm64 support announced in 2026 is limited to NVIDIA Grace/Vera platforms, not these consumer SBC targets.

## Important limitations

- The `aml-s9xx-box` target is community/DBAI-specific, not an official Armbian SBC target.
- The four custom-kernel inputs must be tar archives with paths relative to the target root filesystem. See [custom kernel contract](docs/FOUR-PART-KERNEL.md).
- The current workflow is an initial production-oriented scaffold. Each new board/app combination still requires a successful build and boot test before it should be advertised as supported.
- Never put tokens in workflow inputs, source files, or build artifacts. Configure `DBAI_RELEASE_TOKEN` as a repository Actions secret for release publication.

## Documents

- [Architecture and board policy](docs/ARCHITECTURE.md)
- [Four-part custom kernel contract](docs/FOUR-PART-KERNEL.md)
- [Backup and release recovery](docs/BACKUP-AND-RELEASE.md)
