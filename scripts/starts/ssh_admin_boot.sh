#!/bin/sh
# UDX710 boot entry: wait for persistent storage, restore root authentication,
# then start the bundled SSH listener. This runs independently of the proxy core.

CRASHDIR=$(cd "$(dirname "$0")/.." && pwd) || exit 1
. "$CRASHDIR/libs/ssh_admin_runtime.sh" || exit 1

ssh_admin_boot_attempt=0
while [ "$ssh_admin_boot_attempt" -lt 45 ]; do
    ssh_admin_select_data_dir
    if [ -f "$ssh_admin_data_dir/port" ] &&
       [ -x "$CRASHDIR/assets/ssh/aarch64/dropbear" ] &&
       [ -x "$CRASHDIR/assets/ssh/aarch64/sftp-server" ]; then
        if [ ! -f "$ssh_admin_data_dir/shadow.enabled" ] || ssh_admin_restore_shadow; then
            if ssh_admin_start_bundled; then
                sleep 1
            fi
            if ssh_admin_bundled_running; then
                ssh_admin_boot_id=$(cat "${SSH_ADMIN_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" 2>/dev/null)
                if [ -n "$ssh_admin_boot_id" ] && [ ! -L "$ssh_admin_data_dir/boot.id" ]; then
                    (umask 077; printf '%s\n' "$ssh_admin_boot_id" >"$ssh_admin_data_dir/boot.id")
                fi
                exit 0
            fi
        fi
    fi
    ssh_admin_boot_attempt=$((ssh_admin_boot_attempt + 1))
    sleep 2
done
printf 'ShellCrash SSH boot failed after 90 seconds\n' >&2
exit 1
