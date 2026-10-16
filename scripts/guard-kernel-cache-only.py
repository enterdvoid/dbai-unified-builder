#!/usr/bin/env python3
"""Make DBAI's Kernel Official mode fail closed if Armbian misses its kernel artifact cache."""

from pathlib import Path
import sys

MARKER = "# DBAI_KERNEL_OFFICIAL_CACHE_ONLY_GUARD"
FUNCTION = "function artifact_kernel_build_from_sources() {"
GUARD = '''function artifact_kernel_build_from_sources() {
\t{marker}
\tif [[ "${{DBAI_KERNEL_MODE:-}}" == "Kernel Official" ]]; then
\t\texit_with_error "DBAI Kernel Official: no reusable official kernel artifact was found in the Armbian artifact cache. Refusing to compile from source. Choose Recompile Kernel Official to build it."
\tfi
'''.replace("${{DBAI_KERNEL_MODE:-}}", "${DBAI_KERNEL_MODE:-}").format(marker=MARKER)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {Path(sys.argv[0]).name} <artifact-kernel.sh> <kernel-mode>", file=sys.stderr)
        return 2

    source = Path(sys.argv[1])
    mode = sys.argv[2]
    if mode != "Kernel Official":
        print(f"Kernel cache guard not needed for mode: {mode}")
        return 0

    if not source.is_file():
        print(f"ERROR: Armbian kernel artifact hook not found: {source}", file=sys.stderr)
        return 2

    text = source.read_text(encoding="utf-8")
    if MARKER in text:
        print("Kernel Official cache-only guard already installed.")
        return 0

    occurrences = text.count(FUNCTION)
    if occurrences != 1:
        print(
            f"ERROR: Expected exactly one '{FUNCTION}' hook in {source}; found {occurrences}. "
            "Refusing to continue because cache-only enforcement cannot be guaranteed.",
            file=sys.stderr,
        )
        return 2

    source.write_text(text.replace(FUNCTION, GUARD, 1), encoding="utf-8")
    print("Installed Kernel Official cache-only guard: cache miss will fail instead of compiling.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
