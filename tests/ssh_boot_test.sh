#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
CRASHDIR="$test_dir/ShellCrash"
SSH_ADMIN_LOADER_PATH="$test_dir/loader.sh"
ssh_admin_data_dir="$test_dir/data"
SSH_ADMIN_DATA_DIR="$ssh_admin_data_dir"
export SSH_ADMIN_DATA_DIR
mkdir -p "$CRASHDIR/starts" "$CRASHDIR/libs" "$CRASHDIR/assets/ssh/aarch64" "$ssh_admin_data_dir"
cp "$repo_dir/scripts/starts/ssh_admin_boot.sh" "$CRASHDIR/starts/ssh_admin_boot.sh"
chmod 755 "$CRASHDIR/starts/ssh_admin_boot.sh"
printf '#!/bin/sh\necho existing-startup\n' >"$SSH_ADMIN_LOADER_PATH"
cp "$SSH_ADMIN_LOADER_PATH" "$test_dir/original-loader.sh"
. "$repo_dir/scripts/libs/ssh_admin_runtime.sh"
chown() { :; }
ssh_admin_install_loader_hook
ssh_admin_install_loader_hook
[ "$(grep -c '# ShellCrash SSH boot' "$SSH_ADMIN_LOADER_PATH")" -eq 1 ]
cmp "$test_dir/original-loader.sh" "$ssh_admin_data_dir/loader.sh.before-shellcrash"
grep -q 'existing-startup' "$SSH_ADMIN_LOADER_PATH"

SSH_ADMIN_LOADER_PATH="$test_dir/no-loader.sh"
SSH_ADMIN_RCS_DIR="$test_dir/rcS.d"
mkdir "$SSH_ADMIN_RCS_DIR"
ssh_admin_install_boot_hook
ssh_admin_install_boot_hook
[ "$(grep -c '# ShellCrash SSH boot' "$SSH_ADMIN_RCS_DIR/S99shellcrash-ssh")" -eq 1 ]
grep -Fq "$CRASHDIR/starts/ssh_admin_boot.sh" "$SSH_ADMIN_RCS_DIR/S99shellcrash-ssh"
sh -n "$SSH_ADMIN_RCS_DIR/S99shellcrash-ssh"

printf '#!/bin/sh\nexit 0\n' >"$CRASHDIR/assets/ssh/aarch64/sftp-server"
chmod 755 "$CRASHDIR/assets/ssh/aarch64/sftp-server"
SSH_ADMIN_SFTP_DIR="$test_dir/sftp-dir"
ssh_admin_prepare_sftp
[ "$(readlink "$SSH_ADMIN_SFTP_DIR/sftp-server")" = "$CRASHDIR/assets/ssh/aarch64/sftp-server" ]
SSH_ADMIN_SFTP_DIR="$test_dir/sftp-symlink"
ln -s "$test_dir" "$SSH_ADMIN_SFTP_DIR"
if ssh_admin_prepare_sftp; then
    echo 'Accepted an unsafe SFTP directory symlink' >&2
    exit 1
fi

cat >"$CRASHDIR/libs/ssh_admin_runtime.sh" <<'EOF'
ssh_admin_data_dir=$SSH_ADMIN_DATA_DIR
ssh_admin_select_data_dir() { :; }
ssh_admin_restore_shadow() { printf 'shadow\n' >>"$SSH_ADMIN_TEST_ORDER"; }
ssh_admin_start_bundled() { printf 'ssh\n' >>"$SSH_ADMIN_TEST_ORDER"; }
ssh_admin_bundled_running() { return 0; }
EOF
printf '22\n' >"$ssh_admin_data_dir/port"
printf '1\n' >"$ssh_admin_data_dir/shadow.enabled"
touch "$CRASHDIR/assets/ssh/aarch64/dropbear"
chmod 755 "$CRASHDIR/assets/ssh/aarch64/dropbear"
printf 'test-boot-id\n' >"$test_dir/boot-id"
SSH_ADMIN_DATA_DIR="$ssh_admin_data_dir"
SSH_ADMIN_BOOT_ID_FILE="$test_dir/boot-id"
SSH_ADMIN_TEST_ORDER="$test_dir/order"
export SSH_ADMIN_DATA_DIR SSH_ADMIN_BOOT_ID_FILE SSH_ADMIN_TEST_ORDER
"$CRASHDIR/starts/ssh_admin_boot.sh"
[ "$(cat "$SSH_ADMIN_TEST_ORDER")" = "$(printf 'shadow\nssh')" ]
[ "$(cat "$ssh_admin_data_dir/boot.id")" = test-boot-id ]

echo 'SSH boot tests: OK'
