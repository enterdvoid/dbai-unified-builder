# Kernel mode behavior

The workflow exposes four intentionally distinct kernel modes.

| Mode | Behavior |
|---|---|
| `Kernel Official` | Uses the official `armbian/build` framework and attempts to pull the matching prebuilt kernel artifact from Armbian's remote OCI cache. If the framework would fall back to compiling from source, the DBAI guard stops the job with an explicit error. |
| `Recompile Kernel Official` | Sets `ARTIFACT_IGNORE_CACHE=yes`, intentionally bypassing artifact caches and compiling the official-source kernel. |
| `Custom Kernel` | Overlays the four-part kernel bundle supplied through `kernel_custom_input`; it does not compile that kernel. |
| `Recompile Custom Kernel` | Builds from the Git repository/ref supplied through `kernel_custom_input`. |

## Why Kernel Official can fail

Armbian's artifact cache is keyed against the source and build configuration, including framework code. DBAI now prefers the official `armbian/build` repository for boards that exist upstream because using the DBAI fork can change the framework hash and prevent a hit on the official cache. A runner may still lack a matching artifact for a selected source ref, board family, kernel configuration, patches, or framework revision. In that case, upstream Armbian normally falls back to compiling from source. DBAI now blocks that fallback in **Kernel Official** mode, so the selection cannot silently trigger a long kernel rebuild.

The failure message means no matching reusable artifact was available for that build combination. It does **not** mean the kernel source is broken. If you deliberately want to compile it, choose **Recompile Kernel Official**. A successful recompile is not a guarantee that a matching remote artifact will be available to every later runner; cache availability still depends on Armbian's configured artifact-cache backend and cache key.

The guard is injected into Armbian's `lib/functions/artifacts/artifact-kernel.sh` immediately before the build starts. If the expected upstream hook changes or is missing, the workflow fails closed rather than claiming cache-only behavior without enforcing it.

## Verification

Run `tests/test-kernel-cache-guard.sh` to check that the guard:
- inserts into the expected kernel artifact hook;
- is idempotent;
- fails closed if the hook changes or is missing; and
- leaves other kernel modes unchanged.

This check validates the guard logic only. A real workflow run is still needed to confirm that the selected source revision exposes the expected hook and that its Armbian artifact cache contains a matching kernel artifact.
