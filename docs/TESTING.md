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

## Proxmox first-login service-account regression\n\nRun `bash tests/test-proxmox-firstlogin-service-user.sh` when changing either Proxmox extension or the Armbian first-login integration. The test exercises the patched selector against `ceph` and other service-account fixtures, checks idempotence, and requires the build-time patch to fail closed if the upstream selector is unrecognized. Both Proxmox Official and Community images use the same patch helper.\n\n## 3. Full-build verification

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
