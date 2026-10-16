# Custom kernel bootfs archive

Place your archive here before running **Custom Kernel** or **Recompile Custom Kernel**:

```text
bootfs-custom-kernel/bootfs_custom_kernel.tar.gz
```

The archive should contain the *contents* of the boot partition directly, for example `s905_autoscript`, `extlinux/`, boot environment files, and your preferred boot scripts. Do not put everything under an extra `boot/` directory.

Create it from a directory containing the intended bootfs files:

```bash
tar -czf bootfs_custom_kernel.tar.gz -C /path/to/bootfs .
```

The workflow removes the default files under the image's `/boot` directory and extracts this archive. In **Custom Kernel**, the four-part kernel bundle is overlaid afterwards. In **Recompile Custom Kernel**, the compiled kernel and DTB artifacts are preserved and restored after the bootfs replacement.

The archive is not committed yet; add the binary file at this exact path when it is ready. The workflow intentionally stops before expensive builds if the archive is missing or invalid.
