# Application Profiles

The application selector is used only when the **Application** image checkbox is enabled. Minimal, Server, and Desktop images remain normal Armbian images. Incompatible Application/release pairs are omitted from the matrix; other image types for those releases still build. If every requested matrix row is incompatible, planning stops with a clear error.

| Workflow selection | What is staged/installed | Release and architecture constraints |
|---|---|---|
| `homeassistant` | Armbian's maintained `applications-ha` extension | Debian bullseye/bookworm/trixie; check the upstream extension before using older releases |
| `openmediavault` | Armbian's maintained `applications-omv` extension | Debian bookworm/trixie |
| `casaos` | First-boot installer service; runs on the target hardware after network is available | Debian bookworm/trixie, arm64/amd64 |
| `hermes-9router` | 9Router Docker container plus a first-boot Hermes Agent installer | Debian bookworm/trixie, arm64/amd64 |
| `lightnvr-go2rtc` | LightNVR 0.37.2 container with its bundled go2rtc integration | Debian bookworm/trixie, arm64/armhf/amd64 |
| `hermes-9router-lightnvr` | Both Docker services plus Hermes first-boot installer | Debian bookworm/trixie, arm64/amd64 |

## Hermes Agent

The first-boot service uses the official installer at [hermes-agent.nousresearch.com/install.sh](https://hermes-agent.nousresearch.com/install.sh). It runs on the target, not the build runner. No model-provider API key or Telegram/Discord token is baked into the image. After first boot, connect over SSH and run `hermes setup` as the account where Hermes was installed, then configure the model/provider and any gateway integrations you intend to use. The current scaffold installs Hermes as root because Armbian images are commonly administered through root; a dedicated unprivileged Hermes account is a future hardening improvement.

## 9Router

The container is pinned to `ghcr.io/decolua/9router:0.5.95`, which upstream documents as multi-platform for `linux/amd64` and `linux/arm64`. Its data is persisted in the `9router-data` Docker named volume mounted at `/app/data`. First-time setup is completed through port 20128. The image does not bake provider API keys into the firmware.

Upstream references: [9Router Docker guide](https://github.com/decolua/9router/blob/master/DOCKER.md) and [Docker Compose file](https://github.com/decolua/9router/blob/master/docker-compose.yml).

## LightNVR and go2rtc

The image is pinned to `ghcr.io/opensensor/lightnvr:0.37.2`. This image is published for amd64, arm64, and ARMv7; LightNVR includes go2rtc integration, so a second go2rtc container is not started on the same API port. The image uses named volumes for configuration and recordings/database so the default config is preserved on initial mount.

Ports exposed on the LAN:

- `8080/tcp`: web UI
- `8554/tcp`: RTSP
- `8555/tcp` and `8555/udp`: WebRTC
- `1984/tcp`: go2rtc API

Change the initial web credentials immediately and firewall these ports. Do not forward them directly from the public internet.

Upstream references: [LightNVR Docker guide](https://github.com/opensensor/lightNVR/blob/main/docs/DOCKER.md) and [published container versions](https://github.com/opensensor/lightNVR/pkgs/container/lightnvr).

## CasaOS

CasaOS is staged as a first-boot service so the installer detects the actual target architecture rather than the GitHub runner architecture. First boot requires working network access and can take several minutes. Check `/var/log/dbai-casaos-firstboot.log` if installation fails. The upstream installer is mutable, so treat this profile as experimental until tested on the exact board and Debian release.

## Proxmox application variants

Proxmox is selected from the same application dropdown as CasaOS and the other application profiles:

- `proxmox-official`: uses the official Proxmox package repository on Trixie.
- `proxmox-community`: uses community PXVIRT packages on Bookworm, with mirror fallback.
- `proxmox-both`: creates both variants and requires Bookworm and Trixie in the selected release set.

These are application-profile jobs, not a separate `proxmox` profile. The workflow uses the existing DBAI Proxmox extensions and VM-import helper from `enterdvoid/build`, and freezes BSP/kernel package updates for these variants. This is a package-based experiment that retains the Armbian kernel, not the official Proxmox ISO or a guarantee of full Proxmox VE compatibility on an Amlogic TV box. Official Proxmox VE 9.2 ARM64 requires UEFI/ACPI for supported systems; device-tree-only SBCs are not supported by the official ARM64 release.

See [Proxmox official ARM64 platform statement](https://forum.proxmox.com/threads/proxmox-virtual-environment-now-available-for-64-bit-arm-arm64.185527/).## Proxmox application variants

Proxmox options live in the same application selector as CasaOS and the other applications:

- `proxmox-official`: creates an application-profile variant on Trixie.
- `proxmox-community`: creates an application-profile variant on Bookworm.
- `proxmox-both`: creates both variants, requiring both Bookworm and Trixie in the selected release set.

When a selected app does not support a particular release in a multi-release batch, the workflow builds a generic application image for that release rather than trying an incompatible installer.
