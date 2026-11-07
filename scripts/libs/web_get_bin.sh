. "$CRASHDIR"/libs/web_get.sh

get_bin() { #专用于项目内部文件的下载
    # The fork currently publishes all install/update artifacts on dev.
    bin_url="https://raw.githubusercontent.com/Rockbirds/ShellCrashdev/dev/$2"
    webget "$1" "$bin_url" "$3" "$4" "$5" "$6"
}
