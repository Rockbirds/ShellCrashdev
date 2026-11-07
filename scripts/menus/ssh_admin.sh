#!/bin/sh
# Device SSH and root account management. Never store passwords in ShellCrash.

. "$CRASHDIR/libs/ssh_admin_runtime.sh"

ssh_admin_set_readonly_password() (
    umask 077
    ssh_admin_etc_dir=${SSH_ADMIN_ETC_DIR:-/etc}
    [ -f "$ssh_admin_etc_dir/shadow" ] && [ -f "$ssh_admin_etc_dir/passwd" ] || return 1
    awk -F: '$1=="root" && $2=="x" {ok=1} END {exit !ok}' "$ssh_admin_etc_dir/passwd" || return 1
    ssh_admin_hash_helper="$CRASHDIR/assets/ssh/aarch64/hash_password"
    if [ "$(uname -m)" = aarch64 ] && [ -x "$ssh_admin_hash_helper" ]; then
        printf 'test\n' | "$ssh_admin_hash_helper" >/dev/null 2>&1 || return 1
        ssh_admin_hash_method=bundled
    else
        command -v openssl >/dev/null 2>&1 || return 1
        printf 'test\n' | openssl passwd -6 -stdin >/dev/null 2>&1 || return 1
        ssh_admin_hash_method=openssl
    fi
    [ ! -L "$ssh_admin_data_dir" ] &&
        [ ! -L "$ssh_admin_data_dir/shadow" ] &&
        [ ! -L "$ssh_admin_data_dir/shadow.enabled" ] || return 1
    mkdir -p "$ssh_admin_data_dir" &&
        chown 0:0 "$ssh_admin_data_dir" &&
        chmod 700 "$ssh_admin_data_dir" || return 1
    if ssh_admin_shadow_mounted && [ ! -f "$ssh_admin_data_dir/shadow.enabled" ]; then
        ssh_admin_repair_shadow_persistence || return 1
    fi
    stty -echo 2>/dev/null || return 1
    trap 'stty echo 2>/dev/null; [ -n "${ssh_admin_new_shadow:-}" ] && rm -f "$ssh_admin_new_shadow"; unset ssh_admin_password_one ssh_admin_password_two ssh_admin_hash' 0 1 2 3 15
    printf '%s' "$TOOLS_ADMIN_NEW_PASSWORD_PROMPT"
    IFS= read -r ssh_admin_password_one || return 1
    printf '\n%s' "$TOOLS_ADMIN_REPEAT_PASSWORD_PROMPT"
    IFS= read -r ssh_admin_password_two || return 1
    printf '\n'
    [ -n "$ssh_admin_password_one" ] && [ "$ssh_admin_password_one" = "$ssh_admin_password_two" ] || return 1
    unset ssh_admin_password_two
    if [ "$ssh_admin_hash_method" = bundled ]; then
        ssh_admin_hash=$(printf '%s\n' "$ssh_admin_password_one" | "$ssh_admin_hash_helper") || return 1
    else
        ssh_admin_hash=$(printf '%s\n' "$ssh_admin_password_one" | openssl passwd -6 -stdin) || return 1
    fi
    unset ssh_admin_password_one
    case "$ssh_admin_hash" in \$6\$*) ;; *) return 1 ;; esac
    ssh_admin_new_shadow=$(mktemp "$ssh_admin_data_dir/.shadow.XXXXXX") || return 1
    ssh_admin_found_root=0
    while IFS= read -r ssh_admin_line || [ -n "$ssh_admin_line" ]; do
        case "$ssh_admin_line" in
            root:*)
                ssh_admin_suffix=${ssh_admin_line#root:}
                ssh_admin_suffix=${ssh_admin_suffix#*:}
                printf 'root:%s:%s\n' "$ssh_admin_hash" "$ssh_admin_suffix" >>"$ssh_admin_new_shadow"
                ssh_admin_found_root=1
                ;;
            *) printf '%s\n' "$ssh_admin_line" >>"$ssh_admin_new_shadow" ;;
        esac
    done <"$ssh_admin_etc_dir/shadow"
    unset ssh_admin_hash ssh_admin_line ssh_admin_suffix
    if [ "$ssh_admin_found_root" != 1 ]; then
        rm -f "$ssh_admin_new_shadow"
        return 1
    fi
    chown 0:0 "$ssh_admin_new_shadow" && chmod 600 "$ssh_admin_new_shadow" || {
        rm -f "$ssh_admin_new_shadow"
        return 1
    }
    ssh_admin_old_shadow=''
    if [ -f "$ssh_admin_data_dir/shadow" ]; then
        ssh_admin_old_shadow=$(mktemp "$ssh_admin_data_dir/.shadow.backup.XXXXXX") || return 1
        cp -p "$ssh_admin_data_dir/shadow" "$ssh_admin_old_shadow" || return 1
    fi
    if ssh_admin_shadow_mounted; then
        if [ ! -f "$ssh_admin_data_dir/shadow.enabled" ] ||
           ! cmp -s "$ssh_admin_data_dir/shadow" "$ssh_admin_etc_dir/shadow" ||
           ! umount "$ssh_admin_etc_dir/shadow"; then
            rm -f "$ssh_admin_new_shadow" "$ssh_admin_old_shadow"
            return 1
        fi
    fi
    if ! mv -f "$ssh_admin_new_shadow" "$ssh_admin_data_dir/shadow" ||
       ! mount -o bind "$ssh_admin_data_dir/shadow" "$ssh_admin_etc_dir/shadow"; then
        [ -n "$ssh_admin_old_shadow" ] && mv -f "$ssh_admin_old_shadow" "$ssh_admin_data_dir/shadow"
        [ -f "$ssh_admin_data_dir/shadow.enabled" ] && ssh_admin_restore_shadow >/dev/null 2>&1
        return 1
    fi
    if ! cmp -s "$ssh_admin_data_dir/shadow" "$ssh_admin_etc_dir/shadow" ||
       ! ssh_admin_write_shadow_marker; then
        umount "$ssh_admin_etc_dir/shadow" >/dev/null 2>&1 || :
        if [ -n "$ssh_admin_old_shadow" ]; then
            mv -f "$ssh_admin_old_shadow" "$ssh_admin_data_dir/shadow"
            ssh_admin_restore_shadow >/dev/null 2>&1 || :
        else
            rm -f "$ssh_admin_data_dir/shadow" "$ssh_admin_data_dir/shadow.enabled"
        fi
        return 1
    fi
    [ -n "$ssh_admin_old_shadow" ] && rm -f "$ssh_admin_old_shadow"
    return 0
)

ssh_admin_root() {
    if [ "$(id -u)" != 0 ]; then
        msg_alert "\033[31m$TOOLS_ADMIN_ROOT_REQUIRED\033[0m"
        return 1
    fi
}

ssh_admin_persistence_state() {
    if [ -f "$ssh_admin_data_dir/shadow.enabled" ]; then
        if ssh_admin_shadow_mounted &&
           cmp -s "$ssh_admin_data_dir/shadow" "${SSH_ADMIN_ETC_DIR:-/etc}/shadow"; then
            printf '%s\n' "$TOOLS_ADMIN_PERSISTENCE_SAVED"
        else
            printf '%s\n' "$TOOLS_ADMIN_PERSISTENCE_INACTIVE"
        fi
    elif ssh_admin_shadow_mounted; then
        printf '%s\n' "$TOOLS_ADMIN_PERSISTENCE_RUNTIME"
    elif [ "$(ssh_admin_password_state)" = "$TOOLS_ADMIN_PASSWORD_SET" ] &&
         awk '$2=="/" && $3=="ubifs" && $4 ~ /(^|,)rw(,|$)/ {root=1}
              $2=="/etc" || $2=="/etc/shadow" {separate=1}
              END {exit !(root && !separate)}' "${SSH_ADMIN_MOUNTS_FILE:-/proc/mounts}" 2>/dev/null; then
        printf '%s\n' "$TOOLS_ADMIN_PERSISTENCE_SYSTEM"
    else
        printf '%s\n' "$TOOLS_ADMIN_PERSISTENCE_NONE"
    fi
}

ssh_admin_boot_state() {
    if ! ssh_admin_boot_hook_installed; then
        printf '%s\n' "$TOOLS_ADMIN_BOOT_NOT_INSTALLED"
        return
    fi
    ssh_admin_current_boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    ssh_admin_previous_boot_id=$(cat "$ssh_admin_data_dir/boot.id" 2>/dev/null)
    if [ -n "$ssh_admin_current_boot_id" ] &&
       [ "$ssh_admin_current_boot_id" = "$ssh_admin_previous_boot_id" ]; then
        printf '%s\n' "$TOOLS_ADMIN_BOOT_CONFIRMED"
    else
        printf '%s\n' "$TOOLS_ADMIN_BOOT_PENDING"
    fi
}

ssh_admin_password_state() {
    ssh_admin_passwd_dir=${SSH_ADMIN_PASSWD_DIR:-/etc}
    ssh_admin_state=$(awk -F: '$1=="root" {found=1; if ($2=="x") print "shadow"; else if ($2=="") print "empty"; else if ($2 ~ /^[!*]/) print "locked"; else print "set"; exit} END {if (!found) print "unknown"}' "$ssh_admin_passwd_dir/passwd" 2>/dev/null)
    if [ "$ssh_admin_state" = shadow ]; then
        ssh_admin_state=$(awk -F: '$1=="root" {found=1; if ($2=="") print "empty"; else if ($2 ~ /^[!*]/) print "locked"; else print "set"; exit} END {if (!found) print "unknown"}' "$ssh_admin_passwd_dir/shadow" 2>/dev/null)
    fi
    case "$ssh_admin_state" in
    set) printf '%s\n' "$TOOLS_ADMIN_PASSWORD_SET" ;;
    empty) printf '%s\n' "$TOOLS_ADMIN_PASSWORD_EMPTY" ;;
    locked) printf '%s\n' "$TOOLS_ADMIN_PASSWORD_LOCKED" ;;
    *) printf '%s\n' "$TOOLS_ADMIN_PASSWORD_UNKNOWN" ;;
    esac
}

ssh_admin_password_store_writable() {
    ssh_admin_passwd_dir=${SSH_ADMIN_PASSWD_DIR:-/etc}
    [ -f "$ssh_admin_passwd_dir/passwd" ] || return 1
    (: >>"$ssh_admin_passwd_dir/passwd") 2>/dev/null || return 1
    if [ -f "$ssh_admin_passwd_dir/shadow" ]; then
        (: >>"$ssh_admin_passwd_dir/shadow") 2>/dev/null || return 1
    fi
    ssh_admin_probe=$(mktemp "$ssh_admin_passwd_dir/.shellcrash-passwd.XXXXXX" 2>/dev/null) || return 1
    rm -f "$ssh_admin_probe"
}

ssh_admin_valid_port() {
    case "$1" in
    '' | *[!0-9]*) return 1 ;;
    esac
    [ "${#1}" -le 5 ] || return 1
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

ssh_admin_port_listening() {
    ssh_admin_sockets=''
    if command -v ss >/dev/null 2>&1; then
        ssh_admin_sockets=$(ss -ltn 2>/dev/null) || ssh_admin_sockets=''
    fi
    if [ -z "$ssh_admin_sockets" ] && command -v netstat >/dev/null 2>&1; then
        ssh_admin_sockets=$(netstat -ltn 2>/dev/null) || ssh_admin_sockets=''
    fi
    # Some embedded systems provide neither command. In that case rely on the daemon exit status.
    [ -z "$ssh_admin_sockets" ] && return 0
    printf '%s\n' "$ssh_admin_sockets" | awk -v port="$ssh_admin_port" '
        $4 ~ (":" port "$") && $4 !~ /^(127\.|localhost:|\[::1\]:|::1:)/ {found=1}
        END {if (!found) exit 1}
    '
}

ssh_admin_service() {
    [ "$#" -eq 0 ] && set -- sshd ssh dropbear
    SSH_ADMIN_SERVICE=''
    SSH_ADMIN_SERVICE_MODE=''
    if command -v systemctl >/dev/null 2>&1 && [ "$(cat /proc/1/comm 2>/dev/null)" = systemd ]; then
        for service in "$@"; do
            if systemctl cat "$service.service" >/dev/null 2>&1; then
                SSH_ADMIN_SERVICE=$service
                SSH_ADMIN_SERVICE_MODE=systemd
                return 0
            fi
        done
    fi
    for service in "$@"; do
        if [ -x "/etc/init.d/$service" ]; then
            SSH_ADMIN_SERVICE=$service
            SSH_ADMIN_SERVICE_MODE=init
            return 0
        fi
    done
    return 1
}

ssh_admin_start_service() {
    ssh_admin_service "$@" || return 1
    if [ "$SSH_ADMIN_SERVICE_MODE" = systemd ]; then
        systemctl enable "$SSH_ADMIN_SERVICE.service" >/dev/null 2>&1 || SSH_ADMIN_RUNTIME_ONLY=1
        systemctl restart "$SSH_ADMIN_SERVICE.service"
    else
        "/etc/init.d/$SSH_ADMIN_SERVICE" enable >/dev/null 2>&1 || SSH_ADMIN_RUNTIME_ONLY=1
        "/etc/init.d/$SSH_ADMIN_SERVICE" restart
    fi
}

ssh_admin_enable_dropbear() {
    if command -v uci >/dev/null 2>&1 && [ -x /etc/init.d/dropbear ] && [ -f /etc/config/dropbear ]; then
        ssh_admin_backup=$(mktemp /tmp/shellcrash-dropbear.XXXXXX) || return 1
        cp -p /etc/config/dropbear "$ssh_admin_backup" || { rm -f "$ssh_admin_backup"; return 1; }
        if ! uci -q get 'dropbear.@dropbear[0]' >/dev/null 2>&1 &&
           ! uci add dropbear dropbear >/dev/null; then
            rm -f "$ssh_admin_backup"
            return 1
        fi
        if ! uci set "dropbear.@dropbear[0].Port=$ssh_admin_port" ||
           ! uci set 'dropbear.@dropbear[0].PasswordAuth=on' ||
           ! uci set 'dropbear.@dropbear[0].RootPasswordAuth=on' ||
           ! uci commit dropbear; then
            cp -p "$ssh_admin_backup" /etc/config/dropbear
            rm -f "$ssh_admin_backup"
            return 1
        fi
        /etc/init.d/dropbear enable >/dev/null 2>&1 || SSH_ADMIN_RUNTIME_ONLY=1
        if ! /etc/init.d/dropbear restart || ! ssh_admin_port_listening; then
            cp -p "$ssh_admin_backup" /etc/config/dropbear
            /etc/init.d/dropbear restart >/dev/null 2>&1 || :
            rm -f "$ssh_admin_backup"
            msg_alert "\033[31m$TOOLS_ADMIN_NOT_LISTENING\033[0m"
            return 1
        fi
        rm -f "$ssh_admin_backup"
        return 0
    fi

    # Vendor firmware without UCI: start an independent listener for this boot.
    # Its boot scripts must be configured separately if persistence is needed.
    dropbear -R -p "$ssh_admin_port" || return 1
    ssh_admin_port_listening || { msg_alert "\033[31m$TOOLS_ADMIN_NOT_LISTENING\033[0m"; return 1; }
    SSH_ADMIN_RUNTIME_ONLY=1
}

ssh_admin_enable_openssh() {
    ssh_admin_config=${SSH_ADMIN_SSHD_CONFIG:-/etc/ssh/sshd_config}
    if [ ! -f "$ssh_admin_config" ] || [ ! -w "$ssh_admin_config" ]; then
        msg_alert "\033[31m$TOOLS_ADMIN_CONFIG_UNAVAILABLE\033[0m"
        return 1
    fi
    ssh_admin_backup=$(mktemp /tmp/shellcrash-sshd.XXXXXX) || return 1
    cp -p "$ssh_admin_config" "$ssh_admin_backup" || { rm -f "$ssh_admin_backup"; return 1; }
    ssh_admin_temp=$(mktemp /tmp/shellcrash-sshd.XXXXXX) || { rm -f "$ssh_admin_backup"; return 1; }
    {
        printf '# ShellCrash SSH settings\nPort %s\nPermitRootLogin yes\nPasswordAuthentication yes\n' "$ssh_admin_port"
        awk 'NR==1 && $0 == "# ShellCrash SSH settings" {skip=3;next} skip>0 {skip--;next} tolower($1)=="port" {next} {print}' "$ssh_admin_config"
    } >"$ssh_admin_temp"
    # Test before touching the active configuration.
    if ! sshd -t -f "$ssh_admin_temp" >/dev/null 2>&1; then
        rm -f "$ssh_admin_temp" "$ssh_admin_backup"
        msg_alert "\033[31m$TOOLS_ADMIN_CONFIG_INVALID\033[0m"
        return 1
    fi
    ssh_admin_effective=$(sshd -T -f "$ssh_admin_temp" -C user=root,host=localhost,addr=127.0.0.1 2>/dev/null)
    if [ "$?" -ne 0 ] || ! printf '%s\n' "$ssh_admin_effective" | awk -v port="$ssh_admin_port" '
        $1=="port" {count++; if ($2 != port) bad=1}
        $1=="permitrootlogin" && $2=="yes" {root=1}
        $1=="passwordauthentication" && $2=="yes" {password=1}
        END {if (count != 1 || bad || !root || !password) exit 1}
    '; then
        rm -f "$ssh_admin_temp" "$ssh_admin_backup"
        msg_alert "\033[31m$TOOLS_ADMIN_EFFECTIVE_INVALID\033[0m"
        return 1
    fi
    if ! cat "$ssh_admin_temp" >"$ssh_admin_config"; then
        cat "$ssh_admin_backup" >"$ssh_admin_config"
        rm -f "$ssh_admin_temp" "$ssh_admin_backup"
        return 1
    fi
    rm -f "$ssh_admin_temp"
    if ssh_admin_start_service sshd ssh && ssh_admin_port_listening; then
        rm -f "$ssh_admin_backup"
        return 0
    fi
    # Some embedded distributions ship sshd without a service manager.
    if ! ssh_admin_service sshd ssh && sshd -f "$ssh_admin_config" && ssh_admin_port_listening; then
        SSH_ADMIN_RUNTIME_ONLY=1
        rm -f "$ssh_admin_backup"
        return 0
    fi
    cat "$ssh_admin_backup" >"$ssh_admin_config"
    ssh_admin_start_service sshd ssh >/dev/null 2>&1 || :
    rm -f "$ssh_admin_backup"
    msg_alert "\033[31m$TOOLS_ADMIN_NOT_LISTENING\033[0m"
    return 1
}

ssh_admin_enable() {
    ssh_admin_root || return 1
    ssh_admin_valid_port "$ssh_admin_port" || { msg_alert "\033[31m$TOOLS_ADMIN_INVALID_PORT\033[0m"; return 1; }
    SSH_ADMIN_RUNTIME_ONLY=0
    ssh_admin_bundled_mode=0
    if command -v dropbear >/dev/null 2>&1 && { [ -f /etc/config/dropbear ] || ! command -v sshd >/dev/null 2>&1; }; then
        ssh_admin_enable_dropbear || { msg_alert "\033[31m$TOOLS_ADMIN_START_FAILED\033[0m"; return 1; }
    elif command -v sshd >/dev/null 2>&1; then
        ssh_admin_enable_openssh || return 1
    elif [ "$(uname -m)" = aarch64 ] &&
         [ -x "$CRASHDIR/assets/ssh/aarch64/dropbear" ] &&
         [ -x "$CRASHDIR/assets/ssh/aarch64/sftp-server" ]; then
        ssh_admin_bundled_mode=1
        [ ! -L "$ssh_admin_data_dir" ] || return 1
        (umask 077; mkdir -p "$ssh_admin_data_dir") || return 1
        chown 0:0 "$ssh_admin_data_dir" && chmod 700 "$ssh_admin_data_dir" || return 1
        [ ! -L "$ssh_admin_data_dir/port" ] || return 1
        ssh_admin_previous_port=''
        [ -f "$ssh_admin_data_dir/port" ] && IFS= read -r ssh_admin_previous_port <"$ssh_admin_data_dir/port"
        printf '%s\n' "$ssh_admin_port" >"$ssh_admin_data_dir/port" || return 1
        chown 0:0 "$ssh_admin_data_dir/port" || return 1
        chmod 600 "$ssh_admin_data_dir/port"
        if ! ssh_admin_restore_shadow ||
           ! ssh_admin_start_bundled ||
           ! ssh_admin_port_listening; then
            if [ -n "$ssh_admin_previous_port" ]; then
                printf '%s\n' "$ssh_admin_previous_port" >"$ssh_admin_data_dir/port"
            else
                rm -f "$ssh_admin_data_dir/port"
            fi
            msg_alert "\033[31m$TOOLS_ADMIN_START_FAILED\033[0m"
            return 1
        fi
        if [ -n "$ssh_admin_previous_port" ] && [ "$ssh_admin_previous_port" != "$ssh_admin_port" ]; then
            ssh_admin_old_pidfile="$ssh_admin_data_dir/dropbear.$ssh_admin_previous_port.pid"
            if [ -s "$ssh_admin_old_pidfile" ]; then
                IFS= read -r ssh_admin_old_pid <"$ssh_admin_old_pidfile"
                case "$ssh_admin_old_pid" in
                    '' | *[!0-9]*) ;;
                    *) kill "$ssh_admin_old_pid" 2>/dev/null || : ;;
                esac
            fi
        fi
    else
        msg_alert "\033[31m$TOOLS_ADMIN_NO_SERVER\033[0m"
        return 1
    fi
    setconfig ssh_admin_port "$ssh_admin_port"
    if [ "$ssh_admin_bundled_mode" = 1 ]; then
        if ssh_admin_install_boot_hook; then
            msg_alert "\033[32m$TOOLS_ADMIN_BOOT_INSTALLED\033[0m"
        else
            SSH_ADMIN_RUNTIME_ONLY=1
            msg_alert "\033[33m$TOOLS_ADMIN_BOOT_INSTALL_FAILED\033[0m"
        fi
    fi
    msg_alert "\033[32m$TOOLS_ADMIN_ENABLED $ssh_admin_port\033[0m"
    [ "$SSH_ADMIN_RUNTIME_ONLY" = 1 ] && msg_alert "\033[33m$TOOLS_ADMIN_RUNTIME_ONLY\033[0m"
    msg_alert "\033[33m$TOOLS_ADMIN_FIREWALL_NOTE\033[0m"
}

ssh_admin_diagnostics() {
    comp_box "\033[30;47m$TOOLS_ADMIN_DIAG_TITLE\033[0m" \
        "$TOOLS_ADMIN_KERNEL $(uname -r)" \
        "$TOOLS_ADMIN_DIAG_ARCH $(uname -m)" \
        "$TOOLS_ADMIN_DIAG_PASSWORD $(ssh_admin_password_state)" \
        "$TOOLS_ADMIN_DIAG_NO_PLAINTEXT"
    for ssh_admin_command in busybox dropbear sshd passwd chpasswd mkpasswd openssl opkg apk apt-get mount; do
        ssh_admin_path=$(command -v "$ssh_admin_command" 2>/dev/null || :)
        if [ -n "$ssh_admin_path" ]; then
            content_line "$ssh_admin_command: $ssh_admin_path"
        fi
    done
    if command -v busybox >/dev/null 2>&1; then
        ssh_admin_applets=$(busybox --list 2>/dev/null | grep -E '^(passwd|chpasswd|mkpasswd|mount)$' | tr '\n' ' ' || :)
        if [ -n "$ssh_admin_applets" ]; then
            content_line "$TOOLS_ADMIN_DIAG_APPLETS $ssh_admin_applets"
        fi
    fi
    for ssh_admin_dir in ${SSH_ADMIN_DIAG_DIRS:-/etc /home/root /data /overlay}; do
        [ -d "$ssh_admin_dir" ] || continue
        ssh_admin_probe=$(mktemp "$ssh_admin_dir/.shellcrash-test.XXXXXX" 2>/dev/null)
        if [ -n "$ssh_admin_probe" ]; then
            rm -f "$ssh_admin_probe"
            content_line "$ssh_admin_dir: $TOOLS_ADMIN_DIAG_WRITABLE"
        else
            content_line "$ssh_admin_dir: $TOOLS_ADMIN_DIAG_READONLY"
        fi
    done
    if [ -r /proc/mounts ]; then
        content_line "$TOOLS_ADMIN_DIAG_ROOTFS $(awk '$2=="/" {print $3 " " $4; exit}' /proc/mounts)"
    fi
    if [ -r /proc/mounts ]; then
        ssh_admin_etc_mount=$(awk '$2=="/etc" {print $3 " " $4; exit}' /proc/mounts)
        if [ -n "$ssh_admin_etc_mount" ]; then
            content_line "$TOOLS_ADMIN_DIAG_ETCFS $ssh_admin_etc_mount"
        fi
    fi
    for ssh_admin_file in /etc/passwd /etc/shadow; do
        if [ -e "$ssh_admin_file" ]; then
            content_line "$(ls -l "$ssh_admin_file" 2>/dev/null)"
        fi
    done
    btm_box "0) $COMMON_BACK"
    read -r -p "$COMMON_INPUT> " ssh_admin_diagnostic_done
}

ssh_admin_run_command() {
    ssh_admin_root || return 1
    comp_box "\033[30;47m$TOOLS_ADMIN_COMMAND_TITLE\033[0m" \
        "$TOOLS_ADMIN_COMMAND_NOTICE"
    read -r -p "$TOOLS_ADMIN_COMMAND_PROMPT" ssh_admin_command_line
    [ -z "$ssh_admin_command_line" ] && return 0
    line_break
    /bin/sh -c "$ssh_admin_command_line"
    ssh_admin_command_status=$?
    unset ssh_admin_command_line
    separator_line "="
    content_line "$TOOLS_ADMIN_COMMAND_EXIT $ssh_admin_command_status"
    btm_box "0) $COMMON_BACK"
    read -r -p "$COMMON_INPUT> " ssh_admin_command_done
}

ssh_admin_menu() {
    ssh_admin_port=${ssh_admin_port:-22}
    while true; do
        comp_box "\033[30;47m$TOOLS_ADMIN_TITLE\033[0m" \
            "$TOOLS_ADMIN_KERNEL $(uname -r)" \
            "$TOOLS_ADMIN_PORT $ssh_admin_port" \
            "$TOOLS_ADMIN_PERSISTENCE $(ssh_admin_persistence_state)" \
            "$TOOLS_ADMIN_BOOT_STATUS $(ssh_admin_boot_state)"
        btm_box "1) $TOOLS_ADMIN_SET_PORT" \
            "2) $TOOLS_ADMIN_CHANGE_PASSWORD" \
            "3) $TOOLS_ADMIN_ENABLE" \
            "4) $TOOLS_ADMIN_DIAG_ITEM" \
            "5) $TOOLS_ADMIN_COMMAND_ITEM" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " ssh_admin_choice
        case "$ssh_admin_choice" in
        '' | 0) break ;;
        1)
            read -r -p "$TOOLS_ADMIN_PORT_PROMPT" ssh_admin_new_port
            if ssh_admin_valid_port "$ssh_admin_new_port"; then
                ssh_admin_port=$ssh_admin_new_port
            else
                msg_alert "\033[31m$TOOLS_ADMIN_INVALID_PORT\033[0m"
            fi
            ;;
        2)
            if ssh_admin_root; then
                if ! ssh_admin_password_store_writable; then
                    msg_alert "$TOOLS_ADMIN_PASSWORD_READONLY"
                    ssh_admin_set_readonly_password &&
                        msg_alert "\033[32m$TOOLS_ADMIN_PASSWORD_CHANGED\033[0m" ||
                        msg_alert "\033[31m$TOOLS_ADMIN_PASSWORD_FAILED\033[0m"
                else
                    msg_alert "$TOOLS_ADMIN_PASSWORD_PROMPT"
                    passwd root && msg_alert "\033[32m$TOOLS_ADMIN_PASSWORD_CHANGED\033[0m" || msg_alert "\033[31m$TOOLS_ADMIN_PASSWORD_FAILED\033[0m"
                fi
            fi
            ;;
        3) ssh_admin_enable ;;
        4) ssh_admin_diagnostics ;;
        5) ssh_admin_run_command ;;
        *) errornum ;;
        esac
    done
}
