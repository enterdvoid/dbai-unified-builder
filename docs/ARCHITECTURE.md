# Architecture and Support Boundaries

## Source selection

- `aml-s9xx-box`: use `enterdvoid/build`, where `config/boards/aml-s9xx-box.tvb` and board-specific BSP files are present.
- Curated official SBCs: use `armbian/build`.
- `custom`: validate the supplied board ID; prefer an official config, then try the DBAI fork. A board is accepted only if a matching `config/boards/<id>.*` definition exists in the chosen source checkout.

The workflow records the resolved source URL, commit SHA, board ID, release, image profile, filesystem, kernel mode, and app profile in a per-image manifest.

## Build combinations

The workflow expands comma-separated releases and profiles into matrix jobs. Filesystem choice is `ext4`, `btrfs`, or `both`. Profiles map to Armbian build settings:

| Profile | BUILD_MINIMAL | BUILD_DESKTOP | Intended result |
|---|---:|---:|---|
| `minimal` | yes | no | Small CLI image |
| `server` | no | no | Full CLI/server image |
| `application` | no | no | Server base plus selected application extension |
| `desktop` | no | yes | Desktop image |

Target image sizes are 4096 MiB for minimal/server, 6144 MiB for application, and 8192 MiB for desktop. These are total image targets, not guarantees that every board or filesystem will fit every package combination.

## Release lifecycle

1. Every matrix job builds one combination on a clean runner.
2. Each job verifies that at least one image exists, generates a manifest and checksum, then uploads a uniquely named Actions artifact.
3. The publish job downloads all artifacts, checks every checksum, and creates a prerelease with a timestamped tag.
4. It downloads the release assets back and verifies checksums.
5. Only after successful verification does it delete older releases tagged `dbai-build-*` if cleanup is enabled.
6. If publication fails, the partial release and tag are deleted best-effort. Failed build jobs never publish a release.

## Proxmox modes

The `proxmox_mode` selector accepts `none`, `official`, `community`, or `both`. Official mode builds the Trixie package variant; community mode builds the Bookworm PXVIRT variant; `both` requires both releases and creates the corresponding variant per release. Select `app_profile=none` when Proxmox mode is enabled. The workflow applies `BSPFREEZE=yes` to Proxmox image builds and currently requires the official Armbian kernel mode; custom-kernel overlays are not combined with the Proxmox package stack until KVM compatibility is validated.

The Proxmox extensions and VM image-import helper are reused from the existing DBAI Armbian fork, including the PXVIRT mirror fallback, valid Deb822 source configuration, `/tmp` mode 1777, kernel package pinning, and first-boot hostname service. This remains an experimental ARM64 package integration, not official certification of an Amlogic TV box.

## Application compatibility

Home Assistant and OpenMediaVault use Armbian-maintained extensions. CasaOS is experimental. The `hermes-9router`, `lightnvr-go2rtc`, and combined profiles stage Docker Compose deployments; Hermes is installed on first boot and requires the owner to configure a model/provider. 9Router credentials are generated on first boot and stored in a root-only file at `/root/DBAI-APP-CREDENTIALS.txt`. LightNVR 0.37.2 bundles go2rtc integration and exposes the web UI, RTSP, WebRTC, and API ports; do not expose these services directly to the public internet without a firewall and secure configuration.

The workflow exposes Proxmox mode `none/official/community/both`. Official packages are restricted to Trixie and community PXVIRT packages to Bookworm; `both` builds community on Bookworm and official-repository packages on Trixie. This remains experimental on consumer TV boxes/SBCs and intentionally omits the `proxmox-ve` meta-package to retain the Armbian kernel. Official Proxmox Arm64 support announced in 2026 is limited to NVIDIA Grace/Vera platforms, not these consumer SBC targets.

## Security

- Release token is stored only in GitHub Actions secrets as `DBAI_RELEASE_TOKEN`.
- Custom kernel URLs must use HTTPS and should reference immutable releases.
- Kernel archives are checked for path traversal before extraction.
- Never embed access tokens in URLs or manifests.
- Pin `source_ref` to a commit SHA for repeatable production builds. `main` is convenient for testing but changes over time.
