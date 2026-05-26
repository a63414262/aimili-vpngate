# AimiliVPN 🌐

Bilingual: [中文](#中文) | [English](#english)

---

## 中文

[![Telegram](https://img.shields.io/badge/TG交流群-arestemple-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/arestemple)
[![Forum](https://img.shields.io/badge/交流论坛-339936.xyz-orange?style=flat-square&logo=discourse&logoColor=white)](https://339936.xyz)
[![Email](https://img.shields.io/badge/Bug反馈-yaohunse7@gmail.com-red?style=flat-square&logo=gmail&logoColor=white)](mailto:yaohunse7@gmail.com)

---

**AimiliVPN** 是一个专为 Linux VPS（如 Ubuntu）设计的智能 VPN 代理网关管理器。它能够自动采集 VPNGate 开放节点，进行多线程可用性测试与延迟过滤，利用 OpenVPN 隧道与策略路由（Policy Routing）实现出站网络，并在本地提供高性能的 HTTP/SOCKS5 代理网关服务，适合用作 Xray 的落地出站代理。

---

### 🚀 快速开始

在您的 **Ubuntu** VPS 机器上，复制并运行以下一行指令即可完成自动安装部署：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/baoweise-bot/aimili-vpngate/main/install.sh)
```

---

### 🛠️ 快捷命令行 (CLI)

安装成功后，系统会在全局注册 `ml` 快捷管理指令，直接运行 `ml` 可打开图形化交互终端，也可通过以下指令执行：
* **`ml status`** 或 **`ml`**：查看当前运行状态（代理端口、活动 VPN 节点、直连延迟、网页后台登录地址等）。
* **`ml start`**：启动 AimiliVPN 服务。
* **`ml stop`**：停止 AimiliVPN 服务（并自动清理策略路由与 OpenVPN 进程）。
* **`ml restart`**：重启服务。
* **`ml logs`**：查看实时的 Systemd 服务运行日志。
* **`ml web`**：切换网页绑定地址（127.0.0.1 仅本地，或 0.0.0.0 允许公网访问）与重置安全后缀。
* **`ml port`**：修改网页管理控制台监听端口。
* **`ml password`**：生成新的 12 位安全管理密码。
* **`ml uninstall`**：完全卸载服务并清理相关环境。

#### 💡 首次安装注意事项与常见报错解决（小白必看）

1. **全新/纯净系统依赖安装**
   在首次安装时，如果您的系统（Ubuntu 18/20/22/24/26 或 Debian）是全新安装的极简系统，可能会因为缺少 `curl` 或 SSL 证书组件（`ca-certificates`）导致一键脚本下载失败。
   请在运行安装脚本前，先执行以下命令安装依赖：
   ```bash
   apt-get update && apt-get install -y curl ca-certificates
   # 如果是非 root 用户，请加上 sudo：
   # sudo apt-get update && sudo apt-get install -y curl ca-certificates
   ```
   * **Debian 系统特别提示**：本脚本一键安装包默认限制了仅在 Ubuntu 系统中执行。Debian 用户如需运行，可先运行以下命令下载脚本，并使用 `sed` 临时将系统类型限制替换为 `"ubuntu"` 后再执行安装：
     ```bash
     curl -Ls https://raw.githubusercontent.com/baoweise-bot/aimili-vpngate/main/install.sh -o install.sh
     sed -i 's/"${ID:-}"/"ubuntu"/g' install.sh
     sudo bash install.sh
     ```

2. **包管理器被占用报错（锁冲突）**
   如果系统在刚启动或后台自动更新时运行安装脚本，可能会提示以下类似错误：
   * `Could not get lock /var/lib/dpkg/lock-frontend - open (11: Resource temporarily unavailable)`
   * `Unable to acquire the dpkg frontend lock (...), is another process using it?`
   * `E: 无法获得锁 /var/lib/dpkg/lock-frontend`

   **解决方法**：需要停止后台的自动更新服务，强制终止相关进程，清理锁文件，然后重新安装。依次输入并执行以下命令：
   ```bash
   # 1. 停止并禁用后台自动更新服务，防止它自动重启并重新加锁
   sudo systemctl stop unattended-upgrades 2>/dev/null
   
   # 2. 终止正在运行的 apt/dpkg 进程
   sudo killall apt apt-get dpkg 2>/dev/null
   
   # 3. 强制删除所有 apt 和 dpkg 锁文件
   sudo rm -f /var/lib/dpkg/lock-frontend
   sudo rm -f /var/lib/dpkg/lock
   sudo rm -f /var/lib/apt/lists/lock
   sudo rm -f /var/cache/apt/archives/lock
   
   # 4. 修复并重新配置受损的包
   sudo dpkg --configure -a
   
   # 5. 重新更新源并重试安装
   sudo apt-get update
   ```
   执行完上述命令后，再次运行安装脚本即可。

---

### ⚙️ 系统架构

```
   [ 3x-ui / Xray ] 
         │ (HTTP / SOCKS5)
         ▼
   [ 本地代理服务器 ] (Port 7928) ──(强制绑定 SO_BINDTODEVICE)──► [ tun0 虚拟网卡 ]
         │                                                            │
         │ (SSH, Web UI, etc. 依然走物理路由)                           │ (策略路由表 100)
         ▼                                                            ▼
   [ 物理网卡 eth0 ] ◄───────────────────────────────────────── [ OpenVPN 加密隧道 ]
         │                                                            │
         ▼ (真实服务器 IP 出站)                                         ▼ (VPNGate 落地节点出站)
    (国内直连流量)                                               (解锁流媒体、锁区网站)
```

---

## English

[![Telegram](https://img.shields.io/badge/Telegram-arestemple-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/arestemple)
[![Forum](https://img.shields.io/badge/Forum-339936.xyz-orange?style=flat-square&logo=discourse&logoColor=white)](https://339936.xyz)
[![Email](https://img.shields.io/badge/Bug%20Report-yaohunse7@gmail.com-red?style=flat-square&logo=gmail&logoColor=white)](mailto:yaohunse7@gmail.com)

---

**AimiliVPN** is an intelligent VPN proxy gateway manager designed specifically for Linux VPS (e.g. Ubuntu). It automatically collects open VPNGate nodes, conducts multi-threaded availability testing and latency filtering, establishes secure out-of-band routing via OpenVPN and policy routing to **prevent VPS lockouts**, and hosts a high-performance local SOCKS5/HTTP proxy gateway. It is highly optimized to serve as a residential/unlocked egress node for upstream proxies like 3x-ui / Xray.

### ✨ Key Features

1. ⚡ **Auto-Collection & Multi-Threaded Probing**:
   * Periodically fetches candidate nodes from VPNGate.
   * Performs concurrent ping latency and handshake tests to maintain a pool of high-quality nodes.
2. 🔒 **Anti-Lockout Routing (Policy Routing)**:
   * Directs traffic from the virtual adapter `tun0` to a customized routing table (Table 100) without altering the system's default gateway.
   * Keeps SSH sessions and server administration panels unaffected by the active VPN.
3. 🚫 **Fail-Safe Leak Protection**:
   * Outbound socket connections inside the local proxy server are strictly bound to `tun0` via `SO_BINDTODEVICE`.
   * If the VPN disconnects, proxy requests are instantly blocked with a `502 Bad Gateway` instead of falling back to the VPS physical IP address.
4. 🖥️ **Modern Web UI Panel**:
   * Sleek dark/light responsive console (default port `8787`).
   * Provides real-time geolocation, ISP, ASN, latency, and IP-type (residential/datacenter) detection.
   * Enables manual node selection, blacklist resets, proxy speed-testing, and logs query.
   * Secured by a random secret path suffix (e.g., `/EJsW2EeBo9lY/`) and password authentication.
5. 🛠️ **CLI Utility (ml)**:
   * Command-line helper tool `ml` with a menu-driven interface.
   * Provides quick statuses, starts/stops the daemon, resets passwords, and changes bind hosts.

---

### 🚀 Quick Start

To install and deploy AimiliVPN on your **Ubuntu** server, copy and paste the following command:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/baoweise-bot/aimili-vpngate/main/install.sh)
```

---

### 🛠️ CLI Helper Commands

Once installed, use the global command `ml` to launch the interactive helper menu, or use the shortcuts below:
* **`ml status`** or **`ml`**: Check running system status (active nodes, proxy ports, latency, URLs).
* **`ml start`**: Start the gateway service.
* **`ml stop`**: Stop the gateway service (and clean routing tables).
* **`ml restart`**: Restart the service.
* **`ml logs`**: View real-time Systemd output logs.
* **`ml web`**: Toggle Web UI accessibility (127.0.0.1 or 0.0.0.0) and reset suffix paths.
* **`ml port`**: Update the Web Console port.
* **`ml password`**: Regenerate a secure 12-character administration password.
* **`ml uninstall`**: Completely remove the service and repository files from your VPS.

#### 💡 Troubleshooting & First-Time Installation Tips

1. **Minimal / Clean OS Dependencies**
   On a brand new minimal Linux system (Ubuntu 18/20/22/24/26 or Debian), the installation might fail if tools like `curl` or SSL root certificates (`ca-certificates`) are missing.
   Run the following command to pre-install dependencies before running the setup script:
   ```bash
   apt-get update && apt-get install -y curl ca-certificates
   # Or with sudo if you are not running as root:
   # sudo apt-get update && sudo apt-get install -y curl ca-certificates
   ```
   * **Debian OS Special Note**: The installation script is restricted to Ubuntu by default. If you are on Debian, download the script first and run a simple `sed` replacement to bypass the OS restriction:
     ```bash
     curl -Ls https://raw.githubusercontent.com/baoweise-bot/aimili-vpngate/main/install.sh -o install.sh
     sed -i 's/"${ID:-}"/"ubuntu"/g' install.sh
     sudo bash install.sh
     ```

2. **Package Manager Locked / Busy Errors (`apt`/`dpkg` lock)**
   If the OS is performing unattended background upgrades or another apt process was interrupted, you may encounter error messages like:
   * `Could not get lock /var/lib/dpkg/lock-frontend - open (11: Resource temporarily unavailable)`
   * `Unable to acquire the dpkg frontend lock (...), is another process using it?`

   **Solution**: Stop the background auto-update service, force-terminate the blocking update processes, clear the stale lock files, and resume installation. Run the following commands sequentially:
   ```bash
   # 1. Stop background unattended upgrades service
   sudo systemctl stop unattended-upgrades 2>/dev/null
   
   # 2. Terminate running apt/dpkg processes
   sudo killall apt apt-get dpkg 2>/dev/null
   
   # 3. Force delete apt/dpkg lock files
   sudo rm -f /var/lib/dpkg/lock-frontend
   sudo rm -f /var/lib/dpkg/lock
   sudo rm -f /var/lib/apt/lists/lock
   sudo rm -f /var/cache/apt/archives/lock
   
   # 4. Reconfigure interrupted packages
   sudo dpkg --configure -a
   
   # 5. Refresh package list
   sudo apt-get update
   ```
   After performing these steps, re-run the installation command.
