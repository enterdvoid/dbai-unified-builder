#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The helper uses Armbian's standard error/notification hooks at build time.
display_alert() { :; }
exit_with_error() { printf 'EXPECTED/TEST ERROR: %s\n' "$*" >&2; }
# shellcheck disable=SC1091
source "$repo_root/extensions/dbai-proxmox-firstlogin-fix.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
target_root="$tmp/target"
firstlogin="$target_root/usr/lib/armbian/armbian-firstlogin"
mkdir -p "$(dirname "$firstlogin")"
cat > "$firstlogin" <<'FIRSTLOGIN'
#!/bin/bash
add_user() {
local existing_user

existing_user=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)
if [ -n "${existing_user}" ]; then
    echo "Detected existing user ${existing_user} from previous setup, reusing."
else
    echo "Please provide a username"
fi
}
FIRSTLOGIN
chmod 0755 "$firstlogin"

dbai_patch_proxmox_firstlogin_user_detection "$target_root"
bash -n "$firstlogin"
grep -Fq '# DBAI-FIRSTLOGIN-HUMAN-USER-RECOVERY-BEGIN' "$firstlogin"
# shellcheck disable=SC2016
grep -Fq 'existing_user="$(dbai_find_existing_human_user)"' "$firstlogin"
# shellcheck disable=SC2016
if grep -Fq 'existing_user=$(awk -F:' "$firstlogin"; then
  echo "FAIL: UID-only selector remains in patched first-login script." >&2
  exit 1
fi

# The patch must be idempotent.
before="$(sha256sum "$firstlogin" | awk '{print $1}')"
dbai_patch_proxmox_firstlogin_user_detection "$target_root"
after="$(sha256sum "$firstlogin" | awk '{print $1}')"
[[ "$before" == "$after" ]]

# Execute the exact selector function from the generated first-login script
# against fixture passwd/home/shells files; this avoids touching host accounts.
selector="$tmp/selector.sh"
sed -n '/^dbai_find_existing_human_user() {$/,/^}$/p' "$firstlogin" > "$selector"
[[ -s "$selector" ]]
bash -n "$selector"
runner="$tmp/run-selector.sh"
cat > "$runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
source "$1"
dbai_find_existing_human_user
RUNNER

home_root="$tmp/home"
mkdir -p "$home_root/alice" "$home_root/orphan" "$home_root/nobody"
shells_file="$tmp/shells"
printf '%s\n' /bin/bash /bin/sh > "$shells_file"
passwd_all="$tmp/passwd-all"
cat > "$passwd_all" <<PASSWD
root:x:0:0:root:/root:/bin/bash
ceph:x:1000:1000:Ceph service:/var/lib/ceph:/usr/sbin/nologin
orphan:x:1001:1001:Interrupted service:/home/orphan:/usr/sbin/nologin
wronghome:x:1002:1002:Service account:/var/lib/wronghome:/bin/bash
nobody:x:65534:65534:nobody:$home_root/nobody:/bin/bash
alice:x:1003:1003:Alice:$home_root/alice:/bin/bash
PASSWD

export DBAI_FIRSTLOGIN_PASSWD_FILE="$passwd_all"
export DBAI_FIRSTLOGIN_HOME_ROOT="$home_root"
export DBAI_FIRSTLOGIN_SHELLS_FILE="$shells_file"
selected="$(bash "$runner" "$selector")"
[[ "$selected" == "alice" ]] || {
  echo "FAIL: expected alice; selected '$selected'." >&2
  exit 1
}
echo "PASS: skips ceph/service accounts and reuses a complete interactive /home user."

passwd_services="$tmp/passwd-services"
cat > "$passwd_services" <<PASSWD
root:x:0:0:root:/root:/bin/bash
ceph:x:1000:1000:Ceph service:/var/lib/ceph:/usr/sbin/nologin
orphan:x:1001:1001:Interrupted service:$home_root/orphan:/usr/sbin/nologin
wronghome:x:1002:1002:Service account:/var/lib/wronghome:/bin/bash
nobody:x:65534:65534:nobody:$home_root/nobody:/bin/bash
PASSWD
export DBAI_FIRSTLOGIN_PASSWD_FILE="$passwd_services"
selected="$(bash "$runner" "$selector")"
[[ -z "$selected" ]] || {
  echo "FAIL: expected no candidate for service-only accounts; selected '$selected'." >&2
  exit 1
}
echo "PASS: service-only account tables do not select any account."

# Unknown future upstream source must fail closed, rather than ship an unpatched bug.
unknown_root="$tmp/unknown"
mkdir -p "$unknown_root/usr/lib/armbian"
printf '%s\n' '#!/bin/bash' 'echo upstream changed' > "$unknown_root/usr/lib/armbian/armbian-firstlogin"
unknown_log="$tmp/unknown-patch.log"
if dbai_patch_proxmox_firstlogin_user_detection "$unknown_root" >"$unknown_log" 2>&1; then
  cat "$unknown_log" >&2
  echo "FAIL: unknown upstream selector was accepted without a verified patch." >&2
  exit 1
fi
grep -Fq "Failed to patch Armbian first-login user selection safely" "$unknown_log" || {
  cat "$unknown_log" >&2
  echo "FAIL: unknown upstream source was rejected for an unexpected reason." >&2
  exit 1
}
echo "PASS: unknown upstream first-login source fails the build-time patch check."
