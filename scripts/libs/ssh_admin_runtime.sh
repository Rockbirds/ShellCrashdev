#!/bin/sh
# Persistent device-side SSH state. The account file contains a hash, never plaintext.

ssh_admin_select_data_dir() {
    if [ -n "${SSH_ADMIN_DATA_DIR:-}" ]; then
        ssh_admin_data_dir=$SSH_ADMIN_DATA_DIR
    elif [ -f /data/shellcrash-ssh/port ] || [ -f /data/shellcrash-ssh/shadow.enabled ]; then
        ssh_admin_data_dir=/data/shellcrash-ssh
    elif awk '$2=="/data" && $3!="tmpfs" {found=1} END {exit !found}' /proc/mounts 2>/dev/null; then
        ssh_admin_data_dir=/data/shellcrash-ssh
    elif awk '$2=="/mnt/userdata" && $3!="tmpfs" {found=1} END {exit !found}' /proc/mounts 2>/dev/null; then
        ssh_admin_data_dir=/mnt/userdata/shellcrash-ssh
    else
        ssh_admin_data_dir=/var/lib/shellcrash-ssh
    fi
}
ssh_admin_select_data_dir

ssh_admin_shadow_mounted() {
    ssh_admin_mount_target=${SSH_ADMIN_ETC_DIR:-/etc}/shadow
    awk -v target="$ssh_admin_mount_target" '$5==target {found=1} END {exit !found}' /proc/self/mountinfo 2>/dev/null
}

ssh_admin_shadow_source_is_ours() {
    # On this UBIFS layout, a bind mount of /data/shellcrash-ssh/shadow has
    # /shellcrash-ssh/shadow as its mount root. Only repair that known state.
    [ "$ssh_admin_data_dir" = /data/shellcrash-ssh ] || return 1
    awk '$4=="/shellcrash-ssh/shadow" && $5=="/etc/shadow" {found=1} END {exit !found}' \
        /proc/self/mountinfo 2>/dev/null
}

ssh_admin_write_shadow_marker() (
    umask 077
    [ ! -L "$ssh_admin_data_dir" ] &&
        [ ! -L "$ssh_admin_data_dir/shadow" ] &&
        [ ! -L "$ssh_admin_data_dir/shadow.enabled" ] || return 1
    chown 0:0 "$ssh_admin_data_dir" "$ssh_admin_data_dir/shadow" || return 1
    chmod 700 "$ssh_admin_data_dir" && chmod 600 "$ssh_admin_data_dir/shadow" || return 1
    ssh_admin_marker=$(mktemp "$ssh_admin_data_dir/.shadow.enabled.XXXXXX") || return 1
    if ! printf '1\n' >"$ssh_admin_marker" ||
       ! chown 0:0 "$ssh_admin_marker" ||
       ! chmod 600 "$ssh_admin_marker" ||
       ! mv -f "$ssh_admin_marker" "$ssh_admin_data_dir/shadow.enabled"; then
        rm -f "$ssh_admin_marker"
        return 1
    fi
)

ssh_admin_repair_shadow_persistence() {
    [ -f "$ssh_admin_data_dir/shadow.enabled" ] && return 0
    [ -f "$ssh_admin_data_dir/shadow" ] || return 1
    ssh_admin_shadow_source_is_ours || return 1
    cmp -s "$ssh_admin_data_dir/shadow" "${SSH_ADMIN_ETC_DIR:-/etc}/shadow" || return 1
    ssh_admin_write_shadow_marker
}

ssh_admin_restore_shadow() {
    [ "$(id -u)" = 0 ] || return 1
    [ -f "$ssh_admin_data_dir/shadow.enabled" ] || return 0
    [ -f "$ssh_admin_data_dir/shadow" ] || return 1
    [ ! -L "$ssh_admin_data_dir" ] && [ ! -L "$ssh_admin_data_dir/shadow" ] || return 1
    chown 0:0 "$ssh_admin_data_dir" "$ssh_admin_data_dir/shadow" || return 1
    chmod 700 "$ssh_admin_data_dir" && chmod 600 "$ssh_admin_data_dir/shadow" || return 1
    ssh_admin_shadow_mounted && return 0
    mount -o bind "$ssh_admin_data_dir/shadow" "${SSH_ADMIN_ETC_DIR:-/etc}/shadow"
}

ssh_admin_runtime_port() {
    [ -f "$ssh_admin_data_dir/port" ] || return 1
    IFS= read -r ssh_admin_saved_port <"$ssh_admin_data_dir/port"
    case "$ssh_admin_saved_port" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$ssh_admin_saved_port" -ge 1 ] && [ "$ssh_admin_saved_port" -le 65535 ]
}

ssh_admin_bundled_running() {
    ssh_admin_pidfile="$ssh_admin_data_dir/dropbear.$ssh_admin_saved_port.pid"
    [ -s "$ssh_admin_pidfile" ] || return 1
    IFS= read -r ssh_admin_daemon_pid <"$ssh_admin_pidfile"
    case "$ssh_admin_daemon_pid" in
        '' | *[!0-9]*) return 1 ;;
    esac
    ssh_admin_daemon_exe=$(readlink "/proc/$ssh_admin_daemon_pid/exe" 2>/dev/null) || return 1
    case "$ssh_admin_daemon_exe" in
        "$ssh_admin_bin_dir/dropbear" | "$ssh_admin_bin_dir/dropbear (deleted)") return 0 ;;
    esac
    return 1
}

ssh_admin_loader_hook_installed() {
    ssh_admin_loader=${SSH_ADMIN_LOADER_PATH:-/home/root/loader.sh}
    [ -f "$ssh_admin_loader" ] &&
        grep -F "$CRASHDIR/starts/ssh_admin_boot.sh" "$ssh_admin_loader" 2>/dev/null |
        grep -Fq '# ShellCrash SSH boot'
}

ssh_admin_sysv_hook_path() {
    ssh_admin_sysv_dir=${SSH_ADMIN_RCS_DIR:-/etc/rcS.d}
    [ -d "$ssh_admin_sysv_dir" ] && [ -w "$ssh_admin_sysv_dir" ] || return 1
    printf '%s/S99shellcrash-ssh\n' "$ssh_admin_sysv_dir"
}

ssh_admin_boot_hook_installed() {
    ssh_admin_loader_hook_installed && return 0
    ssh_admin_sysv_hook=$(ssh_admin_sysv_hook_path) || return 1
    [ -f "$ssh_admin_sysv_hook" ] && [ ! -L "$ssh_admin_sysv_hook" ] &&
        grep -Fq "$CRASHDIR/starts/ssh_admin_boot.sh" "$ssh_admin_sysv_hook"
}

ssh_admin_install_sysv_hook() {
    ssh_admin_sysv_hook=$(ssh_admin_sysv_hook_path) || return 1
    [ -x "$CRASHDIR/starts/ssh_admin_boot.sh" ] || return 1
    if [ -e "$ssh_admin_sysv_hook" ]; then
        ssh_admin_boot_hook_installed
        return $?
    fi
    ssh_admin_sysv_temp=$(mktemp "${ssh_admin_sysv_hook}.XXXXXX") || return 1
    if ! printf '#!/bin/sh\n# ShellCrash SSH boot\n[ "$1" = stop ] && exit 0\n"%s/starts/ssh_admin_boot.sh" >/tmp/shellcrash-ssh-boot.log 2>&1 &\n' "$CRASHDIR" >"$ssh_admin_sysv_temp" ||
       ! chmod 755 "$ssh_admin_sysv_temp" ||
       ! sh -n "$ssh_admin_sysv_temp" ||
       ! mv "$ssh_admin_sysv_temp" "$ssh_admin_sysv_hook"; then
        rm -f "$ssh_admin_sysv_temp"
        return 1
    fi
    sync
    ssh_admin_boot_hook_installed
}

ssh_admin_install_boot_hook() {
    if [ -f "${SSH_ADMIN_LOADER_PATH:-/home/root/loader.sh}" ] &&
       grep -Fq '/home/root/ttyd/start.sh' "${SSH_ADMIN_LOADER_PATH:-/home/root/loader.sh}"; then
        ssh_admin_install_loader_hook
    else
        ssh_admin_install_sysv_hook
    fi
}

ssh_admin_prepare_sftp() {
    ssh_admin_sftp_source="$CRASHDIR/assets/ssh/aarch64/sftp-server"
    ssh_admin_sftp_dir=${SSH_ADMIN_SFTP_DIR:-/tmp/shellcrash-ssh}
    [ -x "$ssh_admin_sftp_source" ] && [ ! -L "$ssh_admin_sftp_dir" ] || return 1
    (umask 077; mkdir -p "$ssh_admin_sftp_dir") || return 1
    chown 0:0 "$ssh_admin_sftp_dir" && chmod 700 "$ssh_admin_sftp_dir" || return 1
    [ ! -e "$ssh_admin_sftp_dir/sftp-server" ] || [ -L "$ssh_admin_sftp_dir/sftp-server" ] || return 1
    ln -sfn "$ssh_admin_sftp_source" "$ssh_admin_sftp_dir/sftp-server" || return 1
    [ -x "$ssh_admin_sftp_dir/sftp-server" ]
}

ssh_admin_install_loader_hook() {
    ssh_admin_loader=${SSH_ADMIN_LOADER_PATH:-/home/root/loader.sh}
    [ -f "$ssh_admin_loader" ] && [ -w "$ssh_admin_loader" ] &&
        [ ! -L "$ssh_admin_loader" ] &&
        [ -x "$CRASHDIR/starts/ssh_admin_boot.sh" ] || return 1
    ssh_admin_loader_hook_installed && return 0
    [ ! -L "$ssh_admin_data_dir" ] || return 1
    mkdir -p "$ssh_admin_data_dir" &&
        chown 0:0 "$ssh_admin_data_dir" && chmod 700 "$ssh_admin_data_dir" || return 1
    if [ ! -f "$ssh_admin_data_dir/loader.sh.before-shellcrash" ]; then
        cp -p "$ssh_admin_loader" "$ssh_admin_data_dir/loader.sh.before-shellcrash" || return 1
        chmod 600 "$ssh_admin_data_dir/loader.sh.before-shellcrash" || return 1
    fi
    ssh_admin_loader_temp=$(mktemp "${ssh_admin_loader}.shellcrash.XXXXXX") || return 1
    if ! cp -p "$ssh_admin_loader" "$ssh_admin_loader_temp" ||
       ! printf '\n"%s/starts/ssh_admin_boot.sh" >/tmp/shellcrash-ssh-boot.log 2>&1 & # ShellCrash SSH boot\n' "$CRASHDIR" >>"$ssh_admin_loader_temp" ||
       ! sh -n "$ssh_admin_loader_temp" ||
       ! mv -f "$ssh_admin_loader_temp" "$ssh_admin_loader"; then
        rm -f "$ssh_admin_loader_temp"
        return 1
    fi
    sync
    ssh_admin_loader_hook_installed
}

ssh_admin_start_bundled() {
    [ "$(id -u)" = 0 ] || return 1
    ssh_admin_runtime_port || return 1
    [ "$(uname -m)" = aarch64 ] || return 1
    ssh_admin_bin_dir="$CRASHDIR/assets/ssh/aarch64"
    [ -x "$ssh_admin_bin_dir/dropbear" ] && [ -x "$ssh_admin_bin_dir/dropbearkey" ] || return 1
    ssh_admin_prepare_sftp || return 1
    [ ! -L "$ssh_admin_data_dir" ] || return 1
    (umask 077; mkdir -p "$ssh_admin_data_dir") || return 1
    chown 0:0 "$ssh_admin_data_dir" && chmod 700 "$ssh_admin_data_dir" || return 1
    ssh_admin_hostkey="$ssh_admin_data_dir/host_ed25519_key"
    [ ! -L "$ssh_admin_hostkey" ] && [ ! -L "$ssh_admin_data_dir/dropbear.$ssh_admin_saved_port.pid" ] || return 1
    if [ ! -s "$ssh_admin_hostkey" ]; then
        "$ssh_admin_bin_dir/dropbearkey" -t ed25519 -f "$ssh_admin_hostkey" >/dev/null || return 1
    fi
    chown 0:0 "$ssh_admin_hostkey" && chmod 600 "$ssh_admin_hostkey" || return 1
    ssh_admin_pidfile="$ssh_admin_data_dir/dropbear.$ssh_admin_saved_port.pid"
    if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":$ssh_admin_saved_port "; then
        ssh_admin_bundled_running
        return $?
    fi
    if command -v netstat >/dev/null 2>&1 && netstat -ltn 2>/dev/null | grep -q ":$ssh_admin_saved_port "; then
        ssh_admin_bundled_running
        return $?
    fi
    "$ssh_admin_bin_dir/dropbear" -P "$ssh_admin_pidfile" -r "$ssh_admin_hostkey" -p "$ssh_admin_saved_port"
}

ssh_admin_runtime_restore() {
    [ "$(id -u)" = 0 ] || return 0
    [ ! -f "$ssh_admin_data_dir/shadow.enabled" ] &&
        ssh_admin_repair_shadow_persistence >/dev/null 2>&1 || :
    [ -f "$ssh_admin_data_dir/shadow.enabled" ] && ssh_admin_restore_shadow || :
    [ -f "$ssh_admin_data_dir/port" ] && ssh_admin_start_bundled || :
}
