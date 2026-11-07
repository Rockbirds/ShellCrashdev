#!/bin/sh
set -e

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../scripts" && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
CRASHDIR="$test_dir/source"
export CRASHDIR
mkdir -p "$CRASHDIR/libs"
cp "$source_dir/libs/web_get.sh" "$source_dir/libs/web_get_bin.sh" "$CRASHDIR/libs/"
printf 'setproxy() { :; }\n' >"$CRASHDIR/libs/set_proxy.sh"
. "$CRASHDIR/libs/web_get.sh"
calls=0
wget() {
    if [ "$1" = --help ]; then
        echo show-progress
        return 0
    fi
    calls=$((calls + 1))
    for last; do :; done
    printf '%s\n' "$last" >>"$test_dir/urls"
    [ "$calls" -eq 2 ]
}
pidof() { return 1; }

webget "$test_dir/version" 'https://raw.githubusercontent.com/Rockbirds/ShellCrashdev/dev/version' echooff
[ "$(sed -n '1p' "$test_dir/urls")" = 'https://raw.githubusercontent.com/Rockbirds/ShellCrashdev/dev/version' ]
[ "$(sed -n '2p' "$test_dir/urls")" = 'https://testingcf.jsdelivr.net/gh/Rockbirds/ShellCrashdev@dev/version' ]

. "$CRASHDIR/libs/web_get_bin.sh"
webget() { printf '%s\n' "$2"; }
[ "$(get_bin "$test_dir/version" version)" = 'https://raw.githubusercontent.com/Rockbirds/ShellCrashdev/dev/version' ]

echo 'Update source tests: OK'
