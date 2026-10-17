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
```

The GitHub Actions validation workflow additionally runs actionlint on all workflow YAML files and validates the embedded Docker Compose configuration.

## 2. Custom-kernel cleanup regression coverage

`tests/test-custom-kernel-residue-cleanup.sh` is the regression test for the final image cleanup path. It must cover all of the following:

- `SDCARD` may be readonly in the Armbian build shell. Helpers that need another target root must receive it as an argument; never assign to `SDCARD` to temporarily change the target.
- Generic names from the Armbian shell (especially `version`) may already be readonly. Use scoped, purpose-specific names such as `boot_artifact_release` rather than shadowing generic globals.
- Non-custom versioned kernel artifacts must be removed from final `/boot`, including `vmlinuz-*`, `Image-*`, `uImage-*`, `zImage-*`, `initrd.img-*`, `uInitrd-*`, `config-*`, `System.map-*`, and `dtb-*`.
- The final verifier must reject stale distro initramfs/ramdisk files and confirm the custom kernel, initramfs, and U-Boot ramdisk match the recorded SHA-256 values.

When fixing a failure in this path, inspect the whole cleanup call chain and all sibling helpers for the same class of issue before rerunning the build. Do not stop after fixing the first shell error.

## 3. Full-build verification

After static validation passes, run an actual workflow build with the exact failing configuration when feasible. A static-validation success is not equivalent to a firmware-build success.

For any custom-kernel image, inspect the build log and resulting image to verify:

1. The intended kernel release is present in `/boot` and `/lib/modules`.
2. Versioned distro kernel packages have been purged.
3. No stale kernel, DTB, initramfs, or U-Boot ramdisk artifacts remain.
4. The generated custom initramfs and U-Boot ramdisk are present and match the manifest checksums.
5. The image filename and selected board/release/profile/filesystem match the workflow inputs.

Record the failing workflow URL, failed step, decisive error line, corrective commit, static test result, and full-build result in the follow-up. Do not mark a bug resolved based only on lint or unit tests.

## 4. Known shell-variable failure class

Armbian extension hooks run inside a shell with upstream variables already populated. Bash reports errors such as `local: NAME: readonly variable` when a function declares a local variable with the same name as an existing readonly global. Fix this by renaming the local variable to a descriptive, extension-specific identifier and add a regression test with that global explicitly marked readonly.
