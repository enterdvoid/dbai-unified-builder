# Platform boot and userspace payloads

The builder stages and installs these platform archives in every firmware build:

- **`u-boot.tar.gz`** — supplies the base `/boot` contents. The archive may contain files at its root or inside one enclosing `boot/` directory. For custom-kernel builds it is applied again during final bootfs assembly so its files are not lost during later kernel hooks.
- **`bootfs_custom_kernel.tar.gz`** — used only by **Custom Kernel** and **Recompile Custom Kernel**. Its configuration is layered over the U-Boot base; matching paths such as `uEnv.txt` use the custom-kernel version. Kernel, ramdisk, and DTB files are then applied and verified.
- **`usr.tar.gz`** — overlays its `bin/`, `sbin/`, and `share/` trees into the image's `/usr/`. The archive may store those directories directly or inside one leading `usr/` directory. Existing unrelated `/usr` files are preserved.
- **`triad-firmware.tar.gz`** — overlays firmware files into `/usr/lib/firmware/`. It accepts a firmware-root archive or a single `firmware/`, `lib/firmware/`, or `usr/lib/firmware/` wrapper. Existing firmware files not present in the archive are preserved.

The installer sets executable mode only for these 23 files from `usr.tar.gz`:

- `/usr/bin/ampart`, `/usr/bin/uuidgen`
- `/usr/sbin/armbian-apt`, `armbian-ddbr`, `armbian-docker`, `armbian-fix`, `armbian-install`, `armbian-kernel`, `armbian-openvfd`, `armbian-software`, `armbian-swap`, `armbian-sync`, `armbian-tf`, `armbian-update`, `balethirq.pl`
- `/usr/share/openvfd/vfdservice`
- The seven `/usr/share/ophub/armbian-software/*.sh` scripts: `201-desktop-chinese-fonts.sh`, `301-frps.sh`, `302-frpc.sh`, `command-desktop.sh`, `command-docker.sh`, `command-service.sh`, and `software-command.sh`.

Configuration files such as `*.conf` and `software-list.conf` remain non-executable. The build preflight checks archive integrity, path safety, layout, and the presence of all designated executable paths.
