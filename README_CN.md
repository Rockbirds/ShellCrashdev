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
  <strong>一款在 Shell 环境下便捷部署与管理 mihomo/sing-box 内核的脚本工具</strong>
</p>

<p align="center">
  简体中文 | <a href="README.md">English</a>
</p>

---

## :rocket: 核心特性

- **多内核支持**：在 Shell 环境下便捷管理及切换 **mihomo** 与 **sing-box** 内核。
- **灵活配置管理**：支持在线导入订阅连结及配置文件，简化配置流程。
- **自动化任务**：支持配置定时任务，实现配置文件与规则的自动定时更新。
- **图形化面板**：支持在线安装并使用本地 Web 面板（Dashboard），直观管理内置规则与流量。
- **多模式运行**：支持路由模式、本机模式等多种流量转发模式切换。
- **一键维护**：内置脚本在线更新功能，保持版本与功能的及时更迭。

## :computer: 设备支持

ShellCrash 旨在兼容绝大多数基于 Linux 内核的网络设备：

* **路由器设备**：支持各种基于 OpenWrt 或其二次开发固件（如 小米路由、网件路由等设备）。
* **Linux 服务器**：支持运行标准 Linux/GNU发行版（如 Debian、CentOS、Armbian、Ubuntu 等）的设备。
* **第三方固件**：兼容 Padavan（保守模式）、潘多拉固件以及华硕/梅林固件。
* **其他设备**：兼容各种基于Linux/GNU或者Linux/busybox开发的设备。
* **Docker**：部分可能不兼容的设备（如群辉、PVE），支持docker环境运行。

> 更多设备支持，请提交 [Issue](https://github.com/Rockbirds/ShellCrashdev/issues) 或前往 [Telegram 群组](https://t.me/ShellClash) 反馈（请附上设备型号及 `uname -a` 命令的输出信息）。

---

## :hammer_and_wrench: 安装指南

> [!TIP]
> 若遇到连接失败或SSL相关问题，请尝试切换至其他安装镜像站。

### 前置条件
1. 在设备上取得 **Root 终端**（可使用管理界面的 Web 终端）。
2. 安装并开启 SSH 后，可使用 PuTTY、JuiceSSH 或系统终端远程连接。

### :penguin: Linux 与路由器安装

请使用设备上的 root 终端。此仓库仅从 `dev` 分支提供安装与更新文件。

```sh
curl -fL https://raw.githubusercontent.com/Rockbirds/ShellCrashdev/dev/install.sh -o /tmp/install.sh
if command -v bash >/dev/null 2>&1; then bash /tmp/install.sh; else sh /tmp/install.sh; fi
```

安装后运行 `crash`，进入「工具与优化 → 9) 设备SSH与root管理」。选项 2 修改 root 密码：在可写 UBIFS 系统上使用系统的 `passwd`，在账户目录只读的 UDX710 系统上使用随包提供的静态 AArch64 哈希工具，保存受限的 SHA-512 shadow 副本并 bind mount 到 `/etc/shadow`。选项 3 使用随包提供的静态 AArch64 Dropbear 和 OpenSSH `sftp-server` 开启 SSH/SFTP，root 密码登录使用同一端口。主机密钥和端口写入持久化存储：已有 `/data` 的设备用 `/data/shellcrash-ssh`，以 `/mnt/userdata` 为用户数据卷的设备用 `/mnt/userdata/shellcrash-ssh`。已确认通过 `/home/root/loader.sh` 启动 Web 终端的 UDX710 固件，会备份该脚本并追加独立 SSH 恢复入口；其他可写 SysV 固件使用 `/etc/rcS.d/S99shellcrash-ssh`。开机时先恢复密码挂载，再启动 SSH/SFTP。菜单显示开机恢复状态；在可写 UBIFS 上，root 密码状态显示系统账户文件已写入并提示重启验证。选项 4 显示诊断，选项 5 执行一条自定义命令。当前密码明文无法读取。更新后需在目标设备上实际重启并测试 SSH 与 SFTP；外网访问还须检查防火墙与上级路由器。静态程序来源、构建方式和 SFTP 下载测试见[构建工作流](.github/workflows/build-dropbear-aarch64.yml)。

### :cloud: 虚拟机
- **Alpine Linux 虚拟机**：强烈建议使用 Alpine 镜像以获得最佳兼容性
```sh
# 安装必要依赖
apk add --no-cache wget openrc ca-certificates tzdata nftables iproute2 dcron

# 执行安装命令
export url='https://raw.githubusercontent.com/Rockbirds/ShellCrashdev/dev' \
  && wget -q --no-check-certificate -O /tmp/install.sh $url/install.sh \
  && sh /tmp/install.sh \
  && . /etc/profile &> /dev/null
```

 ### :whale: Docker 

 请访问官方 Docker 镜像：

- [ShellCrash on Docker Hub](https://hub.docker.com/r/juewuy/shellcrash)


### :package: 本地安装

若无法进行在线安装，请参照以下指南执行本地安装：

- [本地安装ShellCrash教程 | Juewuy's Blog](https://juewuy.github.io/bdaz)

---

## :book: 使用说明

安装完成后，在终端输入以下指令即可启动管理界面：

```shell
crash        # 启动脚本交互选单
crash -h     # 查看命令帮助列表
```

### 运行依赖说明
| 依赖组件 | 必要性 | 说明 |
| :--- | :--- | :--- |
| curl / wget | 必须 | 缺少时将无法进行节点保存、在线安装及更新操作 |
| iptables / nftables | 重要 | 缺少时仅能运行于纯淨模式 |
| crontab | 较低 | 缺少时定时任务功能将失效 |
| net-tools | 极低 | 缺少时无法自动检测端口占用 |
| ubus / iproute-doc | 极低 | 缺少时无法自动获取本机 Host 地址 |

---

## :link: 相关链接
- 常见问题：[Juewuy's Blog](https://juewuy.github.io/chang-jian-wen-ti/)
- 更新日志：[Release History](https://github.com/Rockbirds/ShellCrashdev/releases)
- 交流反馈：[Telegram 讨论组](https://t.me/ShellClash)

---

## :scroll: 许可协议

本项目采用[GNU通用公共许可证第3.0版](LICENSE.txt)授权。

---

## :airplane: 机场推荐

- [**大米**](https://1s.bigmeok.me/user#/register?code=2PuWY9I7)，群友力荐，流媒体解锁，月付推荐。
