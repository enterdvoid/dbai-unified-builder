# shellcheck shell=bash
# Patch Armbian first-login recovery selection for Proxmox images.
# Service accounts (for example ceph) must never be reused as the daily user.

function dbai_patch_proxmox_firstlogin_user_detection() {
	local target_root="$1"
	[[ -n "$target_root" ]] || { exit_with_error "DBAI first-login fix requires the target root filesystem"; return 1; }

	local firstlogin="${target_root}/usr/lib/armbian/armbian-firstlogin"
	[[ -f "$firstlogin" ]] || { exit_with_error "Expected Armbian first-login script not found: $firstlogin"; return 1; }

	if ! python3 - "$firstlogin" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
begin = "# DBAI-FIRSTLOGIN-HUMAN-USER-RECOVERY-BEGIN"
end = "# DBAI-FIRSTLOGIN-HUMAN-USER-RECOVERY-END"
old = """existing_user=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)"""
new = """# DBAI-FIRSTLOGIN-HUMAN-USER-RECOVERY-BEGIN
# Only reuse a complete, interactive human account when recovering an
# interrupted first-login run. UID alone is not enough: service packages
# (notably Proxmox's ceph-common dependency) may create UID >= 1000 users.
dbai_find_existing_human_user() {
    local passwd_file="${DBAI_FIRSTLOGIN_PASSWD_FILE:-/etc/passwd}"
    local home_root="${DBAI_FIRSTLOGIN_HOME_ROOT:-/home}"
    local shells_file="${DBAI_FIRSTLOGIN_SHELLS_FILE:-/etc/shells}"
    local candidate passwd_field uid gid gecos home shell

    [[ -r "$passwd_file" && -r "$shells_file" ]] || return 0
    while IFS=: read -r candidate passwd_field uid gid gecos home shell; do
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        (( uid >= 1000 && uid != 65534 )) || continue
        [[ "$candidate" != "nobody" ]] || continue
        [[ "$home" == "$home_root/$candidate" && -d "$home" ]] || continue
        case "$shell" in
            ""|*/nologin|*/false|*/sync|*/shutdown|*/halt) continue ;;
        esac
        [[ -x "$shell" ]] || continue
        grep -Fqx -- "$shell" "$shells_file" || continue
        printf '%s\\n' "$candidate"
        return 0
    done < "$passwd_file"
    return 0
}
existing_user="$(dbai_find_existing_human_user)"
# DBAI-FIRSTLOGIN-HUMAN-USER-RECOVERY-END"""
if begin in text or end in text:
    if begin in text and end in text and "dbai_find_existing_human_user()" in text:
        print("DBAI first-login human-user guard already installed.")
        raise SystemExit(0)
    raise SystemExit("Found an incomplete DBAI first-login guard; refusing to overwrite it.")
if text.count(old) != 1:
    raise SystemExit(
        "Expected exactly one known Armbian UID-only first-login selector; "
        "source version is unrecognized and was left unchanged."
    )
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Installed DBAI first-login human-user guard.")
PY
	then
		exit_with_error "Failed to patch Armbian first-login user selection safely in $firstlogin"
		return 1
	fi

	display_alert "DBAI first-login user selection" "Reuse only a real interactive /home user; never reuse service accounts such as ceph" "info"
}
