# Platform boot filesystem archive

Place your custom boot partition archive at:

`platform/bootfs_custom_kernel.tar.gz`

The archive should contain the boot partition's files directly (for example `s905_autoscript` and `extlinux/`), not an extra enclosing `boot/` directory. Create it with:

```bash
tar -czf bootfs_custom_kernel.tar.gz -C /path/to/your-bootfs .
```

This archive is required only for **Custom Kernel** and **Recompile Custom Kernel** workflow modes. It is intentionally not included in the repository; add your own archive before running either mode.
