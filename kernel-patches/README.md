# Kernel patch series

Put optional kernel patches as `.patch` files under the subfolder matching the Armbian kernel family/branch series.

For the current `aml-s9xx-box` build, use `meson64-current/`:

```text
kernel-patches/
└── meson64-current/
    ├── 0001-fix.patch
    └── 0002-feature.patch
```

The workflow copies these files into Armbian's `userpatches/kernel/archive/meson64-current/` before building. Only add patches that apply cleanly to the exact selected kernel source and branch. Keep filenames numerically ordered. An empty folder means no extra DBAI patch is applied.
