#!/usr/bin/env bash
set -e
export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 1. Check root permissions
if [[ "$(id -u)" != "0" ]]; then
    echo -e "${RED}错误: 必须以 root 权限运行此脚本。请使用: sudo bash $0${PLAIN}"
    exit 1
fi

# 2. Check OS distribution (Ubuntu only)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        echo -e "${RED}错误: 本系统不是 Ubuntu！目前 AimiliVPN 仅支持 Ubuntu 系统。${PLAIN}"
        exit 1
    fi
else
    echo -e "${RED}错误: 无法确定操作系统版本，缺少 /etc/os-release 文件。${PLAIN}"
    exit 1
fi

echo -e "${BLUE}==========================================================${PLAIN}"
echo -e "${BLUE}        欢迎使用 AimiliVPN 一键源码部署与管理脚本${PLAIN}"
echo -e "${BLUE}==========================================================${PLAIN}"

# 3. Configure GitHub Repository URL
# Default to the official repository (baoweise-bot/aimili-vpngate)
DEFAULT_USER="baoweise-bot"
DEFAULT_REPO="aimili-vpngate"

# Allow custom repository override via command line arguments
GITHUB_USER="${1:-${DEFAULT_USER}}"
GITHUB_REPO="${2:-${DEFAULT_REPO}}"

GITHUB_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

echo -e "\n${YELLOW}[1/4] 正在安装系统基础依赖 (openvpn, curl, git, iptables...)${PLAIN}"
apt-get update -q || true
apt-get install -y openvpn curl git ca-certificates iptables iproute2 psmisc python3

# 4. Clone or pull the repository
INSTALL_DIR="/opt/aimilivpn"
echo -e "\n${YELLOW}[2/4] 正在从 GitHub 部署源代码到 ${INSTALL_DIR}...${PLAIN}"
if [ -d "${INSTALL_DIR}" ]; then
    echo -e "目录 ${INSTALL_DIR} 已存在，正在更新源码..."
    cd "${INSTALL_DIR}"
    git reset --hard || true
    if git pull; then
        echo -e "${GREEN}源码更新成功！${PLAIN}"
    else
        echo -e "${YELLOW}警告: git pull 失败，将保留当前本地源码并继续安装。${PLAIN}"
    fi
else
    echo -e "正在克隆仓库 ${GITHUB_URL} ..."
    if git clone "${GITHUB_URL}" "${INSTALL_DIR}"; then
        echo -e "${GREEN}克隆成功！${PLAIN}"
    else
        echo -e "${RED}错误: 无法克隆仓库 ${GITHUB_URL}，请检查用户名是否正确及 VPS 访问 GitHub 网络！${PLAIN}"
        exit 1
    fi
fi

# 5. Configure Systemd Service (direct python3 run)
echo -e "\n${YELLOW}[3/4] 正在配置 systemd 系统服务...${PLAIN}"
cat > /lib/systemd/system/aimilivpn.service <<EOF
[Unit]
Description=AimiliVPN OpenVPN Manager with HTTP/SOCKS5 Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 vpngate_manager.py
Restart=always
RestartSec=5
EnvironmentFile=-/etc/default/aimilivpn

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable aimilivpn.service

# 6. Configure global command shortcut "ml"
echo -e "\n${YELLOW}[4/4] 正在创建全局命令快捷接口 'ml'...${PLAIN}"
cat > /usr/bin/ml <<'EOF'
#!/usr/bin/env python3
import sys
import os
import socket
import subprocess
import time
import tty
import termios

INSTALL_DIR = "/opt/aimilivpn"
LOG_FILE = "/opt/aimilivpn/vpngate_data/vpngate.log"

def load_ui_cfg():
    import json
    path = "/opt/aimilivpn/vpngate_data/ui_auth.json"
    cfg = {"host": "0.0.0.0", "port": 8787, "secret_path": "EJsW2EeBo9lY", "password": ""}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for k, v in data.items():
                    cfg[k] = v
        except Exception:
            pass
    return cfg

def save_ui_cfg(cfg):
    import json
    path = "/opt/aimilivpn/vpngate_data/ui_auth.json"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        return True
    except Exception:
        return False

def load_state():
    import json
    path = "/opt/aimilivpn/vpngate_data/state.json"
    state = {"active_openvpn_node_id": "", "last_check_message": ""}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for k, v in data.items():
                    state[k] = v
        except Exception:
            pass
    return state

def get_active_node_ip():
    import json
    path = "/opt/aimilivpn/vpngate_data/nodes.json"
    state = load_state()
    active_id = state.get("active_openvpn_node_id")
    if not active_id:
        return None
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                nodes = json.load(f)
                for n in nodes:
                    if n.get("active") or n.get("id") == active_id:
                        return n.get("ip") or n.get("remote_host")
        except Exception:
            pass
    return None

def ping_ip(ip):
    if not ip:
        return None
    try:
        # Run standard linux ping command with 1 packet and 2 seconds timeout
        res = subprocess.run(["ping", "-c", "1", "-W", "2", ip], capture_output=True, text=True, timeout=3)
        if res.returncode == 0:
            out = res.stdout
            lines = out.splitlines()
            for line in lines:
                if "rtt" in line or "min/avg" in line:
                    parts = line.split("=")[1].strip().split("/")
                    if len(parts) >= 2:
                        avg_rtt = float(parts[1])
                        return f"{int(avg_rtt)} ms"
            return "已响应"
        else:
            return "检测超时"
    except Exception:
        return "无法连接"

def check_port_listening(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.2)
    try:
        s.connect(("127.0.0.1", port))
        s.close()
        return True
    except Exception:
        return False

def check_service_active(service_name="aimilivpn.service"):
    try:
        res = subprocess.run(["systemctl", "is-active", service_name], capture_output=True, text=True, timeout=2)
        return res.stdout.strip() == "active"
    except Exception:
        return False

def check_openvpn_process():
    try:
        res = subprocess.run(["pgrep", "openvpn"], capture_output=True, text=True, timeout=2)
        return bool(res.stdout.strip())
    except Exception:
        return False

def get_service_pid(service_name="aimilivpn.service"):
    try:
        res = subprocess.run(["systemctl", "show", service_name, "--property=MainPID"], capture_output=True, text=True, timeout=2)
        out = res.stdout.strip()
        if out.startswith("MainPID="):
            pid = out.split("=")[1]
            if pid and pid != "0":
                return pid
    except Exception:
        pass
    return None

def print_status():
    cfg = load_ui_cfg()
    ui_port = cfg.get("port", 8787)
    secret_path = cfg.get("secret_path", "EJsW2EeBo9lY")
    
    gateway_ok = check_port_listening(7928)
    service_ok = check_service_active("aimilivpn.service")
    openvpn_ok = check_openvpn_process()
    pid = get_service_pid("aimilivpn.service")
    
    active_ip = get_active_node_ip()
    latency = ping_ip(active_ip) if active_ip else None
    
    green = "\033[1;32m"
    red = "\033[1;31m"
    reset = "\033[0m"
    bold = "\033[1m"
    yellow = "\033[1;33m"
    
    gateway_status = f"{green}[已激活]{reset}" if gateway_ok else f"{red}[未启动]{reset}"
    backend_status = f"{green}[已激活] (PID: {pid}){reset}" if (service_ok and pid) else f"{red}[未启动]{reset}"
    openvpn_status = f"{green}[已连接]{reset}" if openvpn_ok else f"{red}[未连接]{reset}"
    
    print("=======================================================")
    print(f"               {bold}AimiliVPN 管理终端 v2.0{reset}                  ")
    print("=======================================================")
    print("【核心服务状态】")
    print(f"  ● 代理网关 (Port 7928)    :  {gateway_status}")
    print(f"  ● 管理后台 (Port {ui_port})    :  {backend_status}")
    print(f"  ● 连接核心 (OpenVPN)       :  {openvpn_status}")
    
    login_ip = "127.0.0.1" if cfg.get("host") == "127.0.0.1" else "您的服务器公网IP"
    print(f"  ● 网页登录地址            :  {yellow}http://{login_ip}:{ui_port}/{secret_path}/{reset}")
    print()
    print("【活动节点状态】")
    if active_ip:
        print(f"  ● 节点 IP                 :  {active_ip}")
        print(f"  ● 节点延迟 (直连测试)     :  {latency or '测试中...'}")
    else:
        print("  ● 节点状态                 :  无活动连接")
    print("=======================================================")

def start_service():
    print("正在启动 AimiliVPN 服务...", flush=True)
    subprocess.run(["systemctl", "start", "aimilivpn.service"])
    print("已发送启动指令。")
    time.sleep(1)

def stop_service():
    print("正在停止 AimiliVPN 服务...", flush=True)
    subprocess.run(["systemctl", "stop", "aimilivpn.service"])
    print("已发送停止指令。")
    time.sleep(1)

def restart_service():
    print("正在重启 AimiliVPN 服务...", flush=True)
    subprocess.run(["systemctl", "restart", "aimilivpn.service"])
    print("已发送重启指令。")
    time.sleep(1)

def show_logs():
    print("正在查看 AimiliVPN 日志 (按 Ctrl+C 退出)...", flush=True)
    if os.path.exists(LOG_FILE):
        try:
            subprocess.run(["tail", "-f", "-n", "50", LOG_FILE])
        except KeyboardInterrupt:
            pass
    else:
        print(f"日志文件不存在: {LOG_FILE}")
        time.sleep(2)

def update_service():
    print("正在一键更新 AimiliVPN 至最新版本并清理旧代码...", flush=True)
    if os.path.exists(INSTALL_DIR):
        try:
            os.chdir(INSTALL_DIR)
            subprocess.run(["git", "fetch", "--all"], check=True)
            res = subprocess.run(["git", "symbolic-ref", "--short", "-q", "HEAD"], capture_output=True, text=True)
            branch = res.stdout.strip() or "main"
            subprocess.run(["git", "reset", "--hard", f"origin/{branch}"], check=True)
            print("代码拉取成功，正在重新运行安装脚本...", flush=True)
            subprocess.run(["bash", "install.sh"])
        except Exception as e:
            print(f"更新失败: {e}")
            time.sleep(3)
    else:
        print(f"未找到安装目录: {INSTALL_DIR}")
        time.sleep(2)

def uninstall_service():
    confirm = input("确定要完全卸载 AimiliVPN 吗？(y/N): ")
    if confirm.lower() == 'y':
        print("正在完全卸载 AimiliVPN...", flush=True)
        subprocess.run(["systemctl", "stop", "aimilivpn.service"])
        subprocess.run(["systemctl", "disable", "aimilivpn.service"])
        try:
            os.unlink("/lib/systemd/system/aimilivpn.service")
        except Exception:
            pass
        try:
            os.unlink("/usr/bin/ml")
        except Exception:
            pass
        subprocess.run(["rm", "-rf", INSTALL_DIR])
        print("AimiliVPN 已卸载！")
        sys.exit(0)
    else:
        print("已取消卸载。")
        time.sleep(1)

def ask_restart():
    ans = input("配置已保存。是否立即重启服务生效？(Y/n): ").strip().lower()
    if ans in ('', 'y', 'yes'):
        print("正在重启 AimiliVPN 服务...", flush=True)
        subprocess.run(["systemctl", "restart", "aimilivpn.service"])
        print("服务已重启。")
        time.sleep(1.5)

def configure_web():
    cfg = load_ui_cfg()
    while True:
        print("\033[H\033[J", end="")
        print("=======================================================")
        print("               网页绑定与地址后缀配置                  ")
        print("=======================================================")
        print(f"  [1] 切换绑定地址 (当前: {cfg.get('host', '0.0.0.0')})")
        print(f"  [2] 修改登录后缀 (当前: {cfg.get('secret_path', '')})")
        print("  [3] 返回主菜单")
        print("=======================================================")
        print("请按数字键 [1-3] 快速执行：")
        
        key = get_key()
        if key == '1':
            print("\033[H\033[J", end="")
            print("选择网页登录绑定地址：")
            print("  1. 仅允许本地登录 (127.0.0.1 - 更安全)")
            print("  2. 允许公网IP登录 (0.0.0.0 - 方便远程)")
            sel = input("请选择 (1 或 2, 默认2): ").strip()
            if sel == '1':
                cfg['host'] = "127.0.0.1"
            else:
                cfg['host'] = "0.0.0.0"
            save_ui_cfg(cfg)
            print(f"绑定地址已更新为: {cfg['host']}")
            ask_restart()
            break
        elif key == '2':
            print("\033[H\033[J", end="")
            new_path = input("请输入新的网页安全登录后缀 (不可为空, 建议使用随机字母数字): ").strip()
            if new_path:
                cfg['secret_path'] = new_path
                save_ui_cfg(cfg)
                print(f"安全登录后缀已更新为: {new_path}")
                print(f"新的访问路径为: http://{cfg['host']}:{cfg['port']}/{new_path}/")
                ask_restart()
            else:
                print("输入为空，未作任何修改。")
                time.sleep(1.5)
            break
        elif key == '3' or key == 'q' or key == 'ctrl+c':
            break

def configure_port():
    cfg = load_ui_cfg()
    print("\033[H\033[J", end="")
    print("=======================================================")
    print("                      管理端口配置                     ")
    print("=======================================================")
    print(f"当前网页管理端口为: {cfg.get('port', 8787)}")
    try:
        val = input("请输入新的管理端口 (1-65535, 按回车取消): ").strip()
        if val:
            port = int(val)
            if 1 <= port <= 65535:
                cfg['port'] = port
                save_ui_cfg(cfg)
                print(f"管理端口已更新为: {port}")
                ask_restart()
            else:
                print("错误: 端口范围必须在 1 至 65535 之间。")
                time.sleep(2)
    except ValueError:
        print("错误: 输入必须是数字。")
        time.sleep(2)

def configure_password():
    cfg = load_ui_cfg()
    while True:
        print("\033[H\033[J", end="")
        print("=======================================================")
        print("                      管理密码管理                     ")
        print("=======================================================")
        curr_pwd = cfg.get('password', '')
        masked_pwd = curr_pwd if len(curr_pwd) <= 4 else curr_pwd[:3] + "********" + curr_pwd[-2:]
        print(f"当前管理密码为: {masked_pwd}")
        print("  [1] 随机重置密码 (12位随机数字，自动保存)")
        print("  [2] 自定义管理密码")
        print("  [3] 返回主菜单")
        print("=======================================================")
        print("请按数字键 [1-3] 快速执行：")
        
        key = get_key()
        if key == '1':
            print("\033[H\033[J", end="")
            import random
            new_pwd = "".join(random.choices("0123456789", k=12))
            cfg['password'] = new_pwd
            save_ui_cfg(cfg)
            print("密码重置成功！")
            print(f"您的全新12位安全密码为: {new_pwd}")
            print("此密码已保存在本地，不需要重启服务，刷新浏览器即可登录。")
            input("\n按任意键返回主菜单...")
            break
        elif key == '2':
            print("\033[H\033[J", end="")
            new_pwd = input("请输入自定义管理密码 (不可为空): ").strip()
            if new_pwd:
                cfg['password'] = new_pwd
                save_ui_cfg(cfg)
                print("密码更新成功！")
                print(f"新的管理密码为: {new_pwd}")
                print("刷新浏览器即可使用新密码登录。")
                input("\n按任意键返回主菜单...")
            else:
                print("输入为空，未作任何修改。")
                time.sleep(1.5)
            break
        elif key == '3' or key == 'q' or key == 'ctrl+c':
            break

def getch():
    fd = sys.stdin.fileno()
    try:
        old_settings = termios.tcgetattr(fd)
    except termios.error:
        return sys.stdin.read(1)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch

def get_key():
    ch = getch()
    if ch == '\x1b':
        ch2 = getch()
        if ch2 == '[':
            ch3 = getch()
            if ch3 == 'A':
                return 'up'
            elif ch3 == 'B':
                return 'down'
    elif ch == '\r' or ch == '\n':
        return 'enter'
    elif ch == '\x03':
        return 'ctrl+c'
    return ch

def main():
    if os.geteuid() != 0:
        print("错误: 必须以 root 权限运行此命令。")
        sys.exit(1)
        
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        if cmd == "start":
            start_service()
        elif cmd == "stop":
            stop_service()
        elif cmd == "restart":
            restart_service()
        elif cmd == "status":
            print_status()
        elif cmd == "logs":
            show_logs()
        elif cmd == "update":
            update_service()
        elif cmd == "uninstall":
            uninstall_service()
        elif cmd == "web":
            configure_web()
        elif cmd == "port":
            configure_port()
        elif cmd == "password":
            configure_password()
        else:
            print("未知命令。可用命令: start, stop, restart, status, logs, update, uninstall, web, port, password")
        sys.exit(0)
        
    options = [
        ("启动服务 (ml start)", start_service),
        ("停止服务 (ml stop)", stop_service),
        ("重启服务 (ml restart)", restart_service),
        ("日志监控 (ml logs)", show_logs),
        ("网页配置 (ml web)", configure_web),
        ("端口配置 (ml port)", configure_port),
        ("密码管理 (ml password)", configure_password),
        ("一键更新 (ml update)", update_service),
        ("完全卸载 (ml uninstall)", uninstall_service),
        ("退出终端 (exit)", None)
    ]
    
    selected_idx = 0
    while True:
        print("\033[H\033[J", end="")
        print_status()
        
        print("请使用 [↑/↓] 键选择并按回车确认，或直接输入数字键 [0-9] 快速执行：")
        print()
        for i, (name, _) in enumerate(options):
            num_char = str((i + 1) % 10)
            if i == selected_idx:
                print(f" \033[1;32m> [{num_char}] {name}\033[0m")
            else:
                print(f"   [{num_char}] {name}")
        print()
        
        try:
            key = get_key()
        except KeyboardInterrupt:
            break
            
        if key == 'up':
            selected_idx = (selected_idx - 1) % len(options)
        elif key == 'down':
            selected_idx = (selected_idx + 1) % len(options)
        elif key == 'enter':
            _, func = options[selected_idx]
            if func is None:
                break
            print("\033[H\033[J", end="")
            func()
            if func in (start_service, stop_service, restart_service):
                continue
            break
        elif key in ('1', '2', '3', '4', '5', '6', '7', '8', '9', '0'):
            mapping = {
                '1': 0, '2': 1, '3': 2, '4': 3, '5': 4,
                '6': 5, '7': 6, '8': 7, '9': 8, '0': 9
            }
            selected_idx = mapping[key]
            _, func = options[selected_idx]
            if func is None:
                break
            print("\033[H\033[J", end="")
            func()
            if func in (start_service, stop_service, restart_service):
                continue
            break
        elif key == 'ctrl+c' or key == 'q':
            break

if __name__ == "__main__":
    main()
EOF
chmod +x /usr/bin/ml

# 7. Start service
echo -e "\n正在启动 AimiliVPN 服务并检测网络..."
systemctl restart aimilivpn.service || true

# Wait for database/auth files generation
sleep 2

SECRET_PATH="EJsW2EeBo9lY"
AUTH_FILE="${INSTALL_DIR}/vpngate_data/ui_auth.json"
if [ -f "$AUTH_FILE" ]; then
    SECRET_PATH=$(python3 -c "import json; print(json.load(open('$AUTH_FILE'))['secret_path'])" 2>/dev/null || echo "EJsW2EeBo9lY")
fi

# Get VPS public IP
echo -e "正在获取 VPS 公网 IP..."
PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://ifconfig.me || curl -s --max-time 3 icanhazip.com || echo "你的VPS公网IP")

echo -e "\n${GREEN}==========================================================${PLAIN}"
echo -e "${GREEN}             AimiliVPN 源码一键部署已完成！${PLAIN}"
echo -e "${GREEN}==========================================================${PLAIN}"
echo -e "  * 网页控制面板 (Web UI): ${BLUE}http://${PUBLIC_IP}:8787/${SECRET_PATH}/${PLAIN}"
echo -e "  * HTTP/SOCKS5 代理端口:  ${BLUE}http://127.0.0.1:7928/${PLAIN}"
echo -e " --------------------------------------------------------"
echo -e "  * 快速状态指令:   ${YELLOW}ml status${PLAIN}  或  ${YELLOW}ml${PLAIN}"
echo -e "  * 查看实时日志:   ${YELLOW}ml logs${PLAIN}"
echo -e "  * 停止服务:       ${YELLOW}ml stop${PLAIN}"
echo -e "  * 重启服务:       ${YELLOW}ml restart${PLAIN}"
echo -e "=========================================================="
echo
