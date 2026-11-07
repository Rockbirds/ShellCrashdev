<h1 align="center">ShellCrash</h1>

<p align="center">
  <a target="_blank" href="https://github.com/MetaCubeX/mihomo/releases">
    <img src="https://img.shields.io/github/release/MetaCubeX/mihomo.svg?style=flat-square&label=Core">
  </a>
  <a target="_blank" href="https://github.com/Rockbirds/ShellCrashdev/releases">
    <img src="https://img.shields.io/github/release/Rockbirds/ShellCrashdev.svg?style=flat-square&label=ShellCrash&colorB=green">
  </a>
</p>

<p align="center">
  <strong>A powerful script tool for the convenient deployment and management of mihomo/sing-box kernels in Shell environments.</strong>
</p>

<p align="center">
  <a href="README_CN.md">简体中文</a> | English
</p>

---

## :rocket: Core Features

- **Multi-Kernel Support**: Easily manage and switch between **mihomo** and **sing-box** kernels directly within the Shell environment.
- **Flexible Configuration Management**: Supports online import of subscription links and configuration files to simplify the setup process.
- **Automated Tasks**: Configure scheduled tasks for automatic updates of configuration files and rules.
- **Graphical Dashboard**: Support for online installation and use of local Web Dashboards to intuitively manage built-in rules and traffic.
- **Multiple Operation Modes**: Supports switching between various traffic forwarding modes, including Router mode and Local mode.
- **One-Click Maintenance**: Built-in online update functionality to keep the script and features up to date.

## :computer: Device Support

ShellCrash is designed to be compatible with the vast majority of network devices based on the Linux kernel:

* **Router Devices**: Supports various firmwares based on OpenWrt or its derivatives (e.g., Xiaomi, Netgear etc.).
* **Linux Servers**: Supports devices running standard Linux/GNU distributions (e.g., Debian, CentOS, Armbian, Ubuntu, etc.).
* **Third-Party Firmware**: Compatible with Padavan (Conservative Mode), Pandora, and ASUS/Merlin firmware.
* **Other Devices**: Compatible with other devices based on Linux/GNU or Linux/busybox.
* **Docker**：Compatible with Docker environments (e.g., Synology, PVE, etc.).

> For additional device support, please submit an [Issue](https://github.com/Rockbirds/ShellCrashdev/issues) or provide feedback in the [Telegram Group](https://t.me/ShellClash) (please include the device model and the output of the `uname -a` command).

---

## :hammer_and_wrench: Installation Guide

> [!TIP]
> If you encounter connection failures or SSL-related issues, please try switching to an alternative installation mirror.

### Prerequisites
1. Obtain a **root terminal** on the device (a management UI terminal is sufficient).
2. After enabling SSH, connect remotely with PuTTY, JuiceSSH, or a system terminal.

### :penguin: Linux and Router Installation

Run these commands in a root terminal on the device. This fork publishes installation and updates from `dev` only.

```sh
curl -fL https://raw.githubusercontent.com/Rockbirds/ShellCrashdev/dev/install_en.sh -o /tmp/install.sh
if command -v bash >/dev/null 2>&1; then bash /tmp/install.sh; else sh /tmp/install.sh; fi
```

After installation, run `crash` and open **Tools & Optimization → 9) Device SSH and root management**. Option 2 changes the root password. It uses the system `passwd` on writable UBIFS systems. On read-only account files, the bundled static AArch64 hash helper stores a protected SHA-512 shadow copy and bind-mounts it at `/etc/shadow`. Option 3 starts bundled static AArch64 Dropbear and OpenSSH `sftp-server` for SSH/SFTP with root password login on the same port. The host key and port are stored persistently in `/data/shellcrash-ssh` when `/data` is mounted, or `/mnt/userdata/shellcrash-ssh` when that is the user-data volume. On UDX710 firmware known to start the Web terminal from `/home/root/loader.sh`, ShellCrash backs up that script and appends an independent SSH restore entry. Other writable SysV systems use `/etc/rcS.d/S99shellcrash-ssh`. At boot, the entry restores the shadow mount before starting SSH/SFTP. The menu reports boot restore status. Option 4 shows diagnostics; option 5 runs a custom command. The current plaintext password cannot be recovered. After updating, reboot the target device and test SSH and SFTP there; WAN access may require a firewall or upstream router rule. The [build workflow](.github/workflows/build-dropbear-aarch64.yml) documents binary provenance and an automated SFTP download test.

### :cloud: Virtual Machines
- **Alpine Linux VM**: It is highly recommended to use an Alpine image for optimal compatibility.
```sh
# Install necessary dependencies
apk add --no-cache wget openrc ca-certificates tzdata nftables iproute2 dcron
# Execute installation command
export url='https://raw.githubusercontent.com/Rockbirds/ShellCrashdev/dev' \
  && wget -q --no-check-certificate -O /tmp/install.sh $url/install_en.sh \
  && sh /tmp/install.sh \
  && . /etc/profile &> /dev/null
```

 ### :whale: Docker 

 Please visit the official Docker image:

- [ShellCrash on Docker Hub](https://hub.docker.com/r/juewuy/shellcrash)


### :package: Local Installation

If online installation is not possible, please follow the guide for local installation:

- [Local ShellCrash Installation Tutorial | Juewuy's Blog](https://juewuy.github.io/bdaz)

---

## :book: Usage Instructions

After installation, enter the following commands in the terminal to launch the management interface:

```shell
crash        # Launch the interactive script menu
crash -h     # View the list of command help
```

### Running Dependencies
| Component | Necessity | Description |
| :--- | :--- | :--- |
| curl / wget | Mandatory | Required for node saving, online installation, and update operations. |
| iptables / nftables | Critical | Without these, the script can only run in Pure Mode. |
| crontab | Low | Required for scheduled tasks; otherwise, they will not function. |
| net-tools | Very Low | Used for automatic port occupancy detection. |
| ubus / iproute-doc | Very Low | Used for automatically obtaining the local Host address. |

---

## :link: Related Links
- FAQ: [Juewuy's Blog](https://juewuy.github.io/chang-jian-wen-ti/)
- Changelog: [Release History](https://github.com/Rockbirds/ShellCrashdev/releases)
- Discussion: [Telegram Group](https://t.me/ShellClash)

## :scroll: License

This project is licensed under the [GNU General Public License v3.0](LICENSE.txt).
