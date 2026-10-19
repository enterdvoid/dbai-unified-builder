#!/usr/bin/env bash
set -euo pipefail

platform_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/platform}"
[[ -d "$platform_dir" ]] || { echo "FAIL: platform directory does not exist: $platform_dir" >&2; exit 1; }

validate_archive() {
	local archive="$1"
	[[ -s "$archive" ]] || { echo "FAIL: required platform archive is missing or empty: $archive" >&2; return 1; }
	tar -tzf "$archive" >/dev/null 2>&1 || { echo "FAIL: invalid .tar.gz archive: $archive" >&2; return 1; }
	if ! tar -tzf "$archive" | awk ' /^\/|(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad }'; then
		echo "FAIL: absolute or parent-traversal path in $archive" >&2
		return 1
	fi
	if ! tar -tzf "$archive" | awk 'NF && $0 !~ /^\.\/?$/ { found=1 } END { exit !found }'; then
		echo "FAIL: archive has no payload: $archive" >&2
		return 1
	fi
}

uboot_archive="$platform_dir/u-boot.tar.gz"
usr_archive="$platform_dir/usr.tar.gz"
validate_archive "$uboot_archive"
validate_archive "$usr_archive"

if ! tar -tzf "$usr_archive" | awk '
	function clean(path) {
		sub(/^\.\//, "", path)
		sub(/\/+$/, "", path)
		return path
	}
	{
		path=clean($0)
		if (path=="" || path==".") next
		if (path=="usr") { prefixed=1; next }
		if (path ~ /^usr\//) { prefixed=1; sub(/^usr\//, "", path) }
		else direct=1
		if (path=="" || path==".") next
		split(path, parts, "/")
		if (parts[1]!="bin" && parts[1]!="sbin" && parts[1]!="share") bad=1
	}
	END { if (bad || (prefixed && direct) || (!prefixed && !direct)) exit 1 }
'; then
	echo "FAIL: usr.tar.gz must contain only bin/, sbin/, and share/ (optionally wrapped in one usr/ directory)" >&2
	exit 1
fi

normalized_listing="$(tar -tzf "$usr_archive" | awk '
	{
		path=$0
		sub(/^\.\//, "", path)
		sub(/\/+$/, "", path)
		if (path=="usr") next
		if (path ~ /^usr\//) sub(/^usr\//, "", path)
		if (path!="" && path!=".") print path
	}
')"

executables=(
	"bin/ampart"
	"bin/uuidgen"
	"sbin/armbian-apt"
	"sbin/armbian-ddbr"
	"sbin/armbian-docker"
	"sbin/armbian-fix"
	"sbin/armbian-install"
	"sbin/armbian-kernel"
	"sbin/armbian-openvfd"
	"sbin/armbian-software"
	"sbin/armbian-swap"
	"sbin/armbian-sync"
	"sbin/armbian-tf"
	"sbin/armbian-update"
	"sbin/balethirq.pl"
	"share/openvfd/vfdservice"
	"share/ophub/armbian-software/201-desktop-chinese-fonts.sh"
	"share/ophub/armbian-software/301-frps.sh"
	"share/ophub/armbian-software/302-frpc.sh"
	"share/ophub/armbian-software/command-desktop.sh"
	"share/ophub/armbian-software/command-docker.sh"
	"share/ophub/armbian-software/command-service.sh"
	"share/ophub/armbian-software/software-command.sh"
)
for path in "${executables[@]}"; do
	if ! grep -Fxq -- "$path" <<< "$normalized_listing"; then
		echo "FAIL: usr.tar.gz is missing required executable payload: $path" >&2
		exit 1
	fi
done

echo "PASS: u-boot.tar.gz and usr.tar.gz are valid, path-safe platform archives."
echo "PASS: usr.tar.gz contains all 23 required executable program/script paths."
