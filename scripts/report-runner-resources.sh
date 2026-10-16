#!/usr/bin/env bash
set -uo pipefail

phase="${1:-unspecified}"
workspace="${GITHUB_WORKSPACE:-$PWD}"
docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"

echo
echo "============================================================"
echo "DBAI RUNNER RESOURCE REPORT — $phase"
echo "============================================================"
echo "Timestamp (UTC): $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "Runner name: ${RUNNER_NAME:-unknown}"
echo "Runner OS: ${RUNNER_OS:-$(uname -s)}"
echo "Runner architecture: ${RUNNER_ARCH:-$(uname -m)}"
echo "ImageOS: ${ImageOS:-unknown}"
echo "ImageVersion: ${ImageVersion:-unknown}"
echo "Kernel: $(uname -srmo)"
echo "CPU logical cores: $(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
cpu_model="$(awk -F: '/model name|Hardware/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
echo "CPU model: ${cpu_model:-unknown}"
echo
echo "--- RAM and swap ---"
free -h 2>&1 || true
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null || true
swapon --show 2>&1 || true
echo
echo "--- Disk capacity / used / free ---"
paths=(/ /mnt "$workspace")
[[ -n "$docker_root" ]] && paths+=("$docker_root")
df -hT "${paths[@]}" 2>&1 || true
echo
echo "--- Block devices ---"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS 2>&1 || true
echo
echo "--- Docker storage ---"
if command -v docker >/dev/null 2>&1; then
  docker info --format 'DockerRootDir={{.DockerRootDir}} | ServerVersion={{.ServerVersion}} | StorageDriver={{.Driver}}' 2>&1 || true
  docker system df 2>&1 || true
else
  echo "Docker is not installed/available at this phase."
fi
echo "============================================================"
