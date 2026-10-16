# Kernel mode behavior

The workflow exposes four intentionally distinct kernel modes.

| Mode | Behavior |
|---|---|
| `Kernel Official` | Allows Armbian's artifact framework to reuse a matching prebuilt kernel artifact. If the framework would fall back to compiling the kernel from source, the DBAI guard stops the job with an explicit error. |
| `Recompile Kernel Official` | Sets `ARTIFACT_IGNORE_CACHE=yes`, intentionally bypassing artifact caches and compiling the official-source kernel. |
| `Custom Kernel` | Overlays the four-part kernel bundle supplied through `kernel_custom_input`; it does not compile that kernel. |
| `Recompile Custom Kernel` | Builds from the Git repository/ref supplied through `kernel_custom_input`. |

## Why Kernel Official can fail

Armbian's artifact cache is keyed against the source and build configuration. A runner may not have a matching artifact for a selected source ref, board family, kernel configuration, patches, or framework revision. In that case, upstream Armbian normally falls back to compiling from source. DBAI now blocks that fallback in **Kernel Official** mode, so the selection cannot silently trigger a long kernel rebuild.

The failure message means no matching reusable artifact was available for that build combination. It does **not** mean the kernel source is broken. If you deliberately want to compile it, choose **Recompile Kernel Official**. A successful recompile is not a guarantee that a matching remote artifact will be available to every later runner; cache availability still depends on Armbian's configured artifact-cache backend and cache key.

The guard is injected into Armbian's `lib/functions/artifacts/artifact-kernel.sh` immediately before the build starts. If the expected upstream hook changes or is missing, the workflow fails closed rather than claiming cache-only behavior without enforcing it.

## Verification

Run `tests/test-kernel-cache-guard.sh` to check that the guard:
- inserts into the expected kernel artifact hook;
- is idempotent;
- fails closed if the hook changes or is missing; and
- leaves other kernel modes unchanged.

This check validates the guard logic only. A real workflow run is still needed to confirm that the selected source revision exposes the expected hook and that its Armbian artifact cache contains a matching kernel artifact.
