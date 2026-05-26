import paramiko
import time

def run_verification(host, port, username, password):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        print(f"Connecting to {host}:{port}...")
        client.connect(host, port=port, username=username, password=password, timeout=10)
        print("Connected successfully!\n")

        commands = [
            # 1. Delete ui_auth.json to force first-time password generation
            "rm -f /opt/aimilivpn/vpngate_data/ui_auth.json",
            
            # 2. Restart service
            "systemctl restart aimilivpn",
            "sleep 4",
            
            # 3. Print the newly generated complex password
            "cat /opt/aimilivpn/vpngate_data/ui_auth.json",
            
            # 4. Wait for automatic connection to complete
            "sleep 15",
            
            # 5. Query state JSON using authenticated call
            "python3 -c 'import json, hashlib, urllib.request; cfg = json.load(open(\"/opt/aimilivpn/vpngate_data/ui_auth.json\")); token = hashlib.sha256((cfg.get(\"password\", \"\") + \"aimilivpn_secure_salt_2026\").encode()).hexdigest(); req = urllib.request.Request(\"http://127.0.0.1:8787/EJsW2EeBo9lY/api/nodes\", headers={\"Cookie\": f\"session={token}\"}); res = json.loads(urllib.request.urlopen(req).read().decode()); print(json.dumps(res[\"state\"], indent=2))'",
            
            # 6. Run ml status to check CLI output (with region and latency)
            "ml status",
            
            # 7. Check journal logs
            "journalctl -u aimilivpn --no-pager -n 40"
        ]

        for cmd in commands:
            print("="*60)
            print(f"Running command: {cmd}")
            print("="*60)
            stdin, stdout, stderr = client.exec_command(cmd)
            out = stdout.read().decode('utf-8', errors='replace')
            err = stderr.read().decode('utf-8', errors='replace')
            if out:
                print(out)
            if err:
                print("stderr:")
                print(err)
            print("\n")

    except Exception as e:
        print(f"Error: {e}")
    finally:
        client.close()

if __name__ == "__main__":
    import json
    import os
    config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "服务器连接配置_不要上传到GITHUB.json")
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
        
    run_verification(config["host"], config["port"], config["username"], config["password"])
