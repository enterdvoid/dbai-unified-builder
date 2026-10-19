# Validation and Build Verification

Use this sequence when changing workflow inputs, Armbian extension hooks, or custom-kernel handling. A green static-validation workflow is necessary, but it does **not** prove that a real Armbian image build succeeds.

## 1. Required local checks

Run from the repository root:

```bash
shellcheck scripts/*.sh extensions/*.sh tests/*.sh
bash tests/test-validate-inputs.sh
bash tests/test-custom-kernel-headers-layout.sh
bash tests/test-desktop-selection.sh
bash tests/test-workflow-build-args.sh
bash tests/test-custom-kernel-residue-cleanup.sh
bash tests/test-custom-kernel-image-verifier.sh
bash tests/test-custom-kernel-bundle-integration.sh
bash tests/test-proxmox-firstlogin-service-user.sh
bash tests/test-patch-armbian-motd.sh
bash tests/test-dbai-apps.sh
```

The GitHub Actions validation workflow additionally runs actionlint on all workflow YAML files and validates the embedded Docker Compose configuration.

## 2. Custom-kernel cleanup regression coverage

`tests/test-custom-kernel-residue-cleanup.sh` is the regression test for the final image cleanup path. It must cover all of the following:

- `SDCARD` may be readonly in the Armbian build shell. Helpers that need another target root must receive it as an argument; never assign to `SDCARD` to temporarily change the target.
- Generic names from the Armbian shell (especially `version`) may already be readonly. Use scoped, purpose-specific names such as `boot_artifact_release` rather than shadowing generic globals.
- Non-custom versioned kernel artifacts must be removed from final `/boot`, including `vmlinuz-*`, `Image-*`, `uImage-*`, `zImage-*`, `initrd.img-*`, `uInitrd-*`, `config-*`, `System.map-*`, and `dtb-*`.
- The finalizer must restore the bundle-supplied kernel and U-Boot ramdisk without renaming or regenerating them, record their exact filenames and SHA-256 values, and fail if those values change.
- The final verifier must reject stale versioned distro boot files and any generated `initrd.img-*`; the supplied `uInitrd-<release>` must remain byte-for-byte the same as in the kernel bundle.

When fixing a failure in this path, inspect the whole cleanup call chain and all sibling helpers for the same class of issue before rerunning the build. Do not stop after fixing the first shell error.

## Proxmox first-login service-account regression\n\nRun `bash tests/test-proxmox-firstlogin-service-user.sh` when changing either Proxmox extension or the Armbian first-login integration. The test exercises the patched selector against `ceph` and other service-account fixtures, checks idempotence, and requires the build-time patch to fail closed if the upstream selector is unrecognized. Both Proxmox Official and Community images use the same patch helper.\n\n## Debian Bullseye package-install environment

The firmware build step must export `COLUMNS=80` and `LINES=24` before running `compile.sh`. GitHub Actions builds do not guarantee an interactive TTY, and package maintainer scripts may fail or behave incorrectly when terminal dimensions are empty. The workflow-argument regression test checks that both exports remain present. This guards the historical fix from `enterdvoid/build` commit [051b217](https://github.com/enterdvoid/build/commit/051b21779563585cf5c8a4a57929e816530d547c).

A passing static test confirms the workaround is wired in; it does not replace a full Bullseye image build. Bullseye is currently limited to Minimal and Server matrix rows in the unified builder; application and desktop rows are deliberately not generated for this end-of-service release.

## DBAI branding on the existing Armbian MOTD

DBAI does not replace Armbian's MOTD renderer. The `dbai-branding` extension updates `VENDOR`, `VENDORPRETTYNAME`, and `VENDORCOLOR` in `/etc/armbian-release`, then patches the existing `/etc/update-motd.d/10-armbian-header` and `41-commands` in place. The original Armbian IP, performance, tips, updates, support and command sections remain enabled.

The header's existing `figlet` wordmark becomes `DBAI-2K26` and uses the slanted `slant` font when figlet is available. The identity line reads the running kernel via Armbian's existing `uname -r` value, the live model from `/proc/device-tree/model`, and a recognized SoC from `/proc/device-tree/compatible`; `/etc/armbian-release` values remain fallbacks. If the upstream header or command-list layout changes, the patcher fails rather than silently overwriting an unknown format.

A separate `dbai-apps` command is installed in `/usr/local/bin` and appears beside `htop` in Armbian's original Commands section. It checks application state only when invoked:

```bash
dbai-apps list
dbai-apps proxmox
dbai-apps hermes
dbai-apps 9router
```

The status labels are `running`, `stopped`, and `not installed`. Tests:

```bash
bash tests/test-patch-armbian-motd.sh
bash tests/test-dbai-apps.sh
```

## Fixed rootfs UUID

Every builder image selecting `ext4` or `btrfs` applies `scripts/patch-rootfs-uuid.py` to Armbian's rootfs partitioning function before build. The UUID is passed directly to `mkfs.ext4` or `mkfs.btrfs`, then read back from `blkid` and checked before Armbian uses it to write `/etc/fstab` and the boot configuration:

```text
19450817-1945-4817-a817-194508170817
```

This changes the filesystem UUID (not GPT/MBR PARTUUID). The patch is fail-closed if the expected Armbian source anchors change, and the validation test covers ext4, btrfs, fstab/root UUID propagation, idempotence, and unknown source layouts.

Run `bash tests/test-static-rootfs-uuid.sh` to test the patch.

## 3. Full-build verification

After static validation passes, run an actual workflow build with the exact failing configuration when feasible. A static-validation success is not equivalent to a firmware-build success.

For any custom-kernel image, inspect the build log and resulting image to verify:

1. The intended kernel release is present in `/boot` and `/lib/modules`.
2. Versioned distro kernel packages have been purged.
3. No stale versioned kernel, DTB, or distro `initrd.img-*` artifacts remain.
4. The original bundle kernel and U-Boot ramdisk retain their supplied filenames and match the manifest SHA-256 values; the builder does not regenerate or rename them.
5. The image filename and selected board/release/profile/filesystem match the workflow inputs.

Record the failing workflow URL, failed step, decisive error line, corrective commit, static test result, and full-build result in the follow-up. Do not mark a bug resolved based only on lint or unit tests.

## 4. Reproduce the Proxmox custom-kernel failure

A commit to `.github/workflows/dbai-build.yml` with a subject containing `[dbai-smoke-app]` launches the targeted regression build: `aml-s9xx-box`, Debian Trixie, Application profile, Proxmox Official extension, ext4, and the published DBAI custom-kernel bundle. This smoke run uses the workflow's APT workaround and must not publish or clean up releases. Use it to validate the actual final-image hooks after the static tests pass.

The existing `[dbai-smoke]` tag continues to exercise a smaller server-image custom-kernel build; `[dbai-smoke-desktop]` exercises the desktop path. All smoke modes select Trixie/ext4 and skip release publication.

## 5. Known shell-variable failure class

Armbian extension hooks run inside a shell with upstream variables already populated. Bash reports errors such as `local: NAME: readonly variable` when a function declares a local variable with the same name as an existing readonly global. Fix this by renaming the local variable to a descriptive, extension-specific identifier and add a regression test with that global explicitly marked readonly.
