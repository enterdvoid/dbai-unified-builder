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

## Application compatibility

Home Assistant and OpenMediaVault use Armbian-maintained extensions. CasaOS is an experimental extension, and a successful image build is not proof of runtime compatibility; smoke-test on hardware.

Hermes, 9Router, and LightNVR/go2rtc need their exact upstream source and deployment contracts pinned before an image can be advertised as containing them. Proxmox VE is not a supported native ARM application; do not label generic virtualization tools as Proxmox VE.

## Security

- Release token is stored only in GitHub Actions secrets as `DBAI_RELEASE_TOKEN`.
- Custom kernel URLs must use HTTPS and should reference immutable releases.
- Kernel archives are checked for path traversal before extraction.
- Never embed access tokens in URLs or manifests.
- Pin `source_ref` to a commit SHA for repeatable production builds. `main` is convenient for testing but changes over time.
