#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
partitioning="$tmp/partitioning.sh"

cat > "$partitioning" <<'SOURCE'
#!/usr/bin/env bash
function make_test_rootfs() {
    local ROOTFS_TYPE="$1"
    declare -A mkopts mkopts_label mkfs
    mkopts[ext4]="-q -m 2"
    mkopts[btrfs]="-m dup"
    mkopts_label[ext4]='-L '
    mkopts_label[btrfs]='-L '
    mkfs[ext4]=ext4
    mkfs[btrfs]=btrfs
    local ROOT_FS_LABEL="armbi_root"
    local rootdevice="/dev/loop-testp2"
    local LOOP="/dev/loop-test"
    local rootpart=2
    local physical_rootdevice="$rootdevice"
    run_host_command_logged mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} ${mkopts_label[$ROOTFS_TYPE]:+${mkopts_label[$ROOTFS_TYPE]}"$ROOT_FS_LABEL"} "${rootdevice}"
    root_part_uuid="$(blkid -s UUID -o value "${LOOP}p${rootpart}")"
    declare -g -r ROOT_PART_UUID="${root_part_uuid}"
    rootfs="UUID=$(blkid -s UUID -o value "$rootdevice")"
    printf 'fstab-root=%s\n' "$rootfs"
}
SOURCE

python3 "$repo_root/scripts/patch-rootfs-uuid.py" "$partitioning"
bash -n "$partitioning"
grep -Fq 'DBAI-STATIC-ROOTFS-UUID-BEGIN' "$partitioning"
grep -Fq -- '-U "19450817-1945-4817-a817-194508170817"' "$partitioning"
# shellcheck disable=SC2016 # Assert literal Bash source preserved by the patch.
grep -Fq 'root_part_uuid="$(blkid -s UUID -o value "${LOOP}p${rootpart}")"' "$partitioning"
grep -Fq 'DBAI rootfs UUID verification failed' "$partitioning"

# Ensure the upstream-style fstab/root identifier continues to derive from blkid.
# shellcheck disable=SC2016 # Assert literal Bash source preserved by the patch.
grep -Fq 'rootfs="UUID=$(blkid -s UUID -o value "$rootdevice")"' "$partitioning"
# shellcheck disable=SC2016 # Assert literal Bash source preserved by the patch.
grep -Fq 'declare -g -r ROOT_PART_UUID="${root_part_uuid}"' "$partitioning"

run_helper="$tmp/run-helper.sh"
cat > "$run_helper" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
run_host_command_logged() {
  printf '%s\n' "$*"
}
blkid() {
  printf '%s\n' '19450817-1945-4817-a817-194508170817'
}
exit_with_error() {
  printf 'ERROR: %s (%s)\n' "$1" "${2:-}" >&2
  exit 1
}
source "$1"
make_test_rootfs "$2"
printf 'ROOT_PART_UUID=%s\n' "$ROOT_PART_UUID"
HELPER

for fs in ext4 btrfs; do
  output="$(bash "$run_helper" "$partitioning" "$fs")"
  grep -Fq "mkfs.$fs" <<< "$output"
  grep -Fq -- '-U 19450817-1945-4817-a817-194508170817' <<< "$output"
  grep -Fq 'ROOT_PART_UUID=19450817-1945-4817-a817-194508170817' <<< "$output"
  grep -Fq 'fstab-root=UUID=19450817-1945-4817-a817-194508170817' <<< "$output"
done

before="$(sha256sum "$partitioning" | awk '{print $1}')"
python3 "$repo_root/scripts/patch-rootfs-uuid.py" "$partitioning"
after="$(sha256sum "$partitioning" | awk '{print $1}')"
[[ "$before" == "$after" ]]

unknown="$tmp/unknown.sh"
printf '%s\n' '#!/usr/bin/env bash' 'function prepare_partitions() { echo upstream changed; }' > "$unknown"
if python3 "$repo_root/scripts/patch-rootfs-uuid.py" "$unknown" >"$tmp/unknown.log" 2>&1; then
  echo 'FAIL: unrecognized Armbian partitioning source should fail closed.' >&2
  exit 1
fi
grep -Fq 'rootfs mkfs command' "$tmp/unknown.log"

echo 'PASS: ext4 and btrfs rootfs are created with the fixed UUID and the source patch is idempotent.'
