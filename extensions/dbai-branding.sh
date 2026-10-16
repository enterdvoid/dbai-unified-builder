#!/usr/bin/env bash
# Apply DBAI2K26 vendor branding to the generated target image release metadata.
# shellcheck shell=bash

function post_repo_customize_image__dbai_branding() {
	: "${SDCARD:?Armbian did not set SDCARD for DBAI branding}"
	local release_file="${SDCARD}/etc/armbian-release"
	mkdir -p "${SDCARD}/etc"

	python3 - "$release_file" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    lines = path.read_text(encoding="utf-8").splitlines()
except FileNotFoundError:
    lines = []

branding = {
    "VENDOR": "DBAI2K26",
    "VENDORPRETTYNAME": "DBAI2K26",
}
seen = set()
updated = []
for line in lines:
    key = line.partition("=")[0]
    if key in branding:
        if key not in seen:
            updated.append(f'{key}="{branding[key]}"')
            seen.add(key)
    else:
        updated.append(line)

for key, value in branding.items():
    if key not in seen:
        updated.append(f'{key}="{value}"')

path.write_text("\n".join(updated) + "\n", encoding="utf-8")
print("Set DBAI2K26 vendor metadata in /etc/armbian-release")
PY
}
