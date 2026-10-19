# Platform boot and userspace payloads

The builder stages and installs these platform archives in every firmware build:

- **`u-boot.tar.gz`** — replaces the generated image's `/boot` contents with the archive payload. The archive may contain boot-partition files at its root or a single enclosing `boot/` directory. This is applied before custom-kernel hooks.
- **`usr.tar.gz`** — overlays its `bin/`, `sbin/`, and `share/` trees into the image's `/usr/`. The archive may store those directories directly or inside one leading `usr/` directory. Existing unrelated `/usr` files are preserved.
- **`bootfs_custom_kernel.tar.gz`** — used only by **Custom Kernel** and **Recompile Custom Kernel**. It replaces the boot filesystem as part of custom-kernel handling, after the generic `u-boot.tar.gz` overlay, so the selected custom boot files take precedence.

The installer sets executable mode only for these 23 files from `usr.tar.gz`:

- `/usr/bin/ampart`, `/usr/bin/uuidgen`
- `/usr/sbin/armbian-apt`, `armbian-ddbr`, `armbian-docker`, `armbian-fix`, `armbian-install`, `armbian-kernel`, `armbian-openvfd`, `armbian-software`, `armbian-swap`, `armbian-sync`, `armbian-tf`, `armbian-update`, `balethirq.pl`
- `/usr/share/openvfd/vfdservice`
- The seven `/usr/share/ophub/armbian-software/*.sh` scripts: `201-desktop-chinese-fonts.sh`, `301-frps.sh`, `302-frpc.sh`, `command-desktop.sh`, `command-docker.sh`, `command-service.sh`, and `software-command.sh`.

Configuration files such as `*.conf` and `software-list.conf` remain non-executable. The build preflight checks archive integrity, path safety, layout, and the presence of all designated executable paths.
