#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CRASHDIR="$repo_dir/scripts"
. "$repo_dir/scripts/menus/ssh_admin.sh"
. "$repo_dir/scripts/lang/chs/8_tools.lang"

for port in 1 22 10022 65535; do
    ssh_admin_valid_port "$port"
done
for port in '' 0 65536 abc 22a 9999999999999999999; do
    if ssh_admin_valid_port "$port"; then
        printf 'Accepted invalid port: %s\n' "$port" >&2
        exit 1
    fi
done

ssh_admin_port=10022
ss() { printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\nLISTEN 0 128 0.0.0.0:10022 0.0.0.0:*\n'; }
ssh_admin_port_listening
ss() { printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\nLISTEN 0 128 127.0.0.1:10022 0.0.0.0:*\n'; }
if ssh_admin_port_listening; then
    echo 'Accepted a loopback-only listener' >&2
    exit 1
fi
ssh_admin_port_listening() { return 0; }

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
mkdir "$test_dir/accounts"
cat >"$test_dir/accounts/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
cat >"$test_dir/accounts/shadow" <<'EOF'
root:$6$test-hash:19000:0:99999:7:::
EOF
SSH_ADMIN_PASSWD_DIR="$test_dir/accounts"
TOOLS_ADMIN_PASSWORD_SET='set'
TOOLS_ADMIN_PASSWORD_EMPTY='empty'
TOOLS_ADMIN_PASSWORD_LOCKED='locked'
TOOLS_ADMIN_PASSWORD_UNKNOWN='unknown'
[ "$(ssh_admin_password_state)" = set ]
ssh_admin_password_store_writable
printf 'root:!:0:0:root:/root:/bin/sh\n' >"$test_dir/accounts/passwd"
[ "$(ssh_admin_password_state)" = locked ]
rm "$test_dir/accounts/passwd"
if ssh_admin_password_store_writable; then
    echo 'Accepted a missing password file' >&2
    exit 1
fi

mkdir "$test_dir/readonly-etc"
mkdir -p "$test_dir/assets/ssh/aarch64"
cat >"$test_dir/assets/ssh/aarch64/hash_password" <<'EOF'
#!/bin/sh
exec openssl passwd -6 -stdin
EOF
chmod 755 "$test_dir/assets/ssh/aarch64/hash_password"
CRASHDIR="$test_dir"
uname() { printf 'aarch64\n'; }
openssl() { echo 'Called device OpenSSL instead of bundled helper' >&2; return 1; }
printf 'root:x:0:0:root:/root:/bin/sh\n' >"$test_dir/readonly-etc/passwd"
printf 'root:oldhash:19000:0:99999:7:::\n' >"$test_dir/readonly-etc/shadow"
SSH_ADMIN_ETC_DIR="$test_dir/readonly-etc"
ssh_admin_data_dir="$test_dir/readonly-data"
TOOLS_ADMIN_NEW_PASSWORD_PROMPT='new> '
TOOLS_ADMIN_REPEAT_PASSWORD_PROMPT='again> '
stty() { :; }
chown() { :; }
ssh_admin_shadow_mounted() { return 1; }
mount() { [ "$1" = -o ] && [ "$2" = bind ] && cp "$3" "$4"; }
printf 'new-secret\nnew-secret\n' | ssh_admin_set_readonly_password
awk -F: '$1=="root" && $2 ~ /^\$6\$/ {ok=1} END {exit !ok}' "$test_dir/readonly-etc/shadow"
cmp "$test_dir/readonly-etc/shadow" "$test_dir/readonly-data/shadow"
[ "$(cat "$test_dir/readonly-data/shadow.enabled")" = 1 ]
! grep -q 'new-secret' "$test_dir/readonly-data/shadow"
cp "$test_dir/readonly-data/shadow" "$test_dir/unchanged-shadow"
if printf 'one\ntwo\n' | ssh_admin_set_readonly_password; then
    echo 'Accepted mismatched passwords' >&2
    exit 1
fi
cmp "$test_dir/unchanged-shadow" "$test_dir/readonly-data/shadow"
rm "$test_dir/readonly-data/shadow.enabled"
ssh_admin_shadow_source_is_ours() { return 0; }
id() { printf '0\n'; }
ssh_admin_runtime_restore
unset -f id
[ "$(cat "$test_dir/readonly-data/shadow.enabled")" = 1 ]
rm "$test_dir/readonly-data/shadow.enabled"
printf 'different-shadow\n' >"$test_dir/readonly-etc/shadow"
if ssh_admin_repair_shadow_persistence; then
    echo 'Enabled persistence for a mismatched shadow file' >&2
    exit 1
fi
[ ! -e "$test_dir/readonly-data/shadow.enabled" ]
unset -f uname openssl
CRASHDIR="$repo_dir/scripts"

SSH_ADMIN_SSHD_CONFIG="$test_dir/sshd_config"
export SSH_ADMIN_SSHD_CONFIG
cat >"$SSH_ADMIN_SSHD_CONFIG" <<'EOF'
# Existing device configuration
Port 2222
PermitRootLogin no
Match User guest
    PasswordAuthentication no
EOF
cp "$SSH_ADMIN_SSHD_CONFIG" "$test_dir/original"

msg_alert() { :; }
TOOLS_ADMIN_CONFIG_INVALID='invalid config'
TOOLS_ADMIN_EFFECTIVE_INVALID='invalid effective config'
TOOLS_ADMIN_NOT_LISTENING='not listening'
TOOLS_ADMIN_START_FAILED='start failed'
sshd() {
    if [ "$1" = -T ]; then
        printf 'port %s\npermitrootlogin yes\npasswordauthentication yes\n' "$ssh_admin_port"
        [ "${SSH_TEST_BAD_EFFECTIVE:-0}" = 1 ] && echo 'port 2222'
        return 0
    fi
    [ "${SSH_TEST_FAIL:-0}" = 0 ]
}
ssh_admin_start_service() { return 0; }
ssh_admin_port=10022

SSH_TEST_FAIL=1
if ssh_admin_enable_openssh; then
    echo 'Accepted invalid sshd configuration' >&2
    exit 1
fi
cmp "$test_dir/original" "$SSH_ADMIN_SSHD_CONFIG"

SSH_TEST_FAIL=0
SSH_TEST_BAD_EFFECTIVE=1
if ssh_admin_enable_openssh; then
    echo 'Accepted an extra SSH port' >&2
    exit 1
fi
cmp "$test_dir/original" "$SSH_ADMIN_SSHD_CONFIG"

SSH_TEST_BAD_EFFECTIVE=0
ssh_admin_enable_openssh
ssh_admin_enable_openssh
[ "$(grep -c '^# ShellCrash SSH settings$' "$SSH_ADMIN_SSHD_CONFIG")" -eq 1 ]
grep -q '^Port 10022$' "$SSH_ADMIN_SSHD_CONFIG"
! grep -q '^Port 2222$' "$SSH_ADMIN_SSHD_CONFIG"
grep -q '^PermitRootLogin yes$' "$SSH_ADMIN_SSHD_CONFIG"
grep -q '^PasswordAuthentication yes$' "$SSH_ADMIN_SSHD_CONFIG"
grep -q '^Match User guest$' "$SSH_ADMIN_SSHD_CONFIG"
grep -q '^    PasswordAuthentication no$' "$SSH_ADMIN_SSHD_CONFIG"

ssh_admin_root() { return 0; }
comp_box() { :; }
line_break() { :; }
separator_line() { :; }
content_line() { printf '%s\n' "$1"; }
btm_box() { :; }
COMMON_BACK='back'
COMMON_INPUT='select'
TOOLS_ADMIN_COMMAND_TITLE='command'
TOOLS_ADMIN_COMMAND_NOTICE='root command'
TOOLS_ADMIN_COMMAND_PROMPT='command> '
TOOLS_ADMIN_COMMAND_EXIT='exit:'
output=$(printf 'printf shellcrash-command-ok\n0\n' | ssh_admin_run_command)
case "$output" in
*shellcrash-command-ok*) : ;;
*) echo 'Command runner did not execute the entered command' >&2; exit 1 ;;
esac
printf 'root:x:0:0:root:/root:/bin/sh\n' >"$test_dir/accounts/passwd"
SSH_ADMIN_DIAG_DIRS="$test_dir/accounts"
diagnostics=$(printf '0\n' | ssh_admin_diagnostics)
case "$diagnostics" in
*"$test_dir/accounts: $TOOLS_ADMIN_DIAG_WRITABLE"*) : ;;
*) echo 'Diagnostics did not report the writable directory' >&2; exit 1 ;;
esac
case "$diagnostics" in
*test-hash*) echo 'Diagnostics exposed a password hash' >&2; exit 1 ;;
esac

TOOLS_ADMIN_PERSISTENCE_SYSTEM='system UBIFS; reboot pending'
TOOLS_ADMIN_PERSISTENCE_NONE='not configured'
SSH_ADMIN_MOUNTS_FILE="$test_dir/mounts"
printf 'ubi0:system / ubifs rw,relatime 0 0\n' >"$SSH_ADMIN_MOUNTS_FILE"
[ "$(ssh_admin_persistence_state)" = "$TOOLS_ADMIN_PERSISTENCE_SYSTEM" ]
printf 'tmpfs / tmpfs rw,relatime 0 0\n' >"$SSH_ADMIN_MOUNTS_FILE"
[ "$(ssh_admin_persistence_state)" = "$TOOLS_ADMIN_PERSISTENCE_NONE" ]
printf 'ubi0:system / ubifs rw,relatime 0 0\ntmpfs /etc tmpfs rw,relatime 0 0\n' >"$SSH_ADMIN_MOUNTS_FILE"
[ "$(ssh_admin_persistence_state)" = "$TOOLS_ADMIN_PERSISTENCE_NONE" ]

echo 'SSH admin tests: OK'
