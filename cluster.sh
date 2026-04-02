#!/bin/bash

# =============================================================
#  SUPER PI CLUSTER — Zero-Config Setup
#
#  Run on every Pi with no arguments. The script will:
#    1. Scan the subnet for an existing Consul cluster
#    2. If found  → join as a client
#    3. If not    → bootstrap as the seed server
#
#  Node identity: superpi-{unix_timestamp}
# =============================================================

set -euo pipefail

USER_HOME=$(eval echo ~"$USER")
CONSUL_VERSION="1.17.0"
NODE_ID="superpi-$(date +%s)"

# =========================
# DETECT LOCAL IP + SUBNET
# =========================
CURRENT_IP=$(hostname -I | awk '{print $1}')
SUBNET=$(echo "$CURRENT_IP" | awk -F. '{print $1"."$2"."$3}')

echo "🚀 Setting up $NODE_ID"
echo "   IP     : $CURRENT_IP"
echo "   Subnet : $SUBNET.0/24"
echo ""

# =========================
# INSTALL PACKAGES
# =========================
echo "📦 Installing packages..."
sudo apt update -y
sudo apt install -y curl unzip python3-venv python3-pip redis-server

# =========================
# INSTALL CONSUL
# =========================
if ! command -v consul &>/dev/null; then
    echo "📥 Installing Consul ${CONSUL_VERSION}..."
    ARCH=$(dpkg --print-architecture)
    curl -sLO "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_${ARCH}.zip"
    unzip -o "consul_${CONSUL_VERSION}_linux_${ARCH}.zip"
    sudo mv consul /usr/local/bin/
    rm "consul_${CONSUL_VERSION}_linux_${ARCH}.zip"
else
    echo "✅ Consul already installed"
fi

# =========================
# STOP EXISTING CONSUL
# =========================
sudo systemctl stop consul 2>/dev/null || true
sudo rm -rf /tmp/consul

# =========================
# SCAN SUBNET FOR EXISTING CLUSTER
# =========================
echo "🔍 Scanning subnet for existing cluster..."

SEED_IP=""
for i in $(seq 1 254); do
    IP="${SUBNET}.${i}"
    [[ "$IP" == "$CURRENT_IP" ]] && continue

    if curl -sf --connect-timeout 1 --max-time 2 "http://${IP}:8500/v1/status/leader" >/dev/null 2>&1; then
        SEED_IP="$IP"
        echo "   ✅ Found cluster via $SEED_IP"
        break
    fi
done

if [[ -z "$SEED_IP" ]]; then
    IS_SEED=true
    echo "   No cluster found — this node will bootstrap"
else
    IS_SEED=false
fi

echo ""

# =========================
# CONSUL CONFIG
# =========================
sudo mkdir -p /etc/consul.d

if $IS_SEED; then
    cat <<EOF | sudo tee /etc/consul.d/config.json
{
  "node_name": "$NODE_ID",
  "bind_addr": "$CURRENT_IP",
  "data_dir": "/tmp/consul",
  "server": true,
  "bootstrap_expect": 1,
  "client_addr": "0.0.0.0",
  "ui_config": { "enabled": true }
}
EOF
else
    cat <<EOF | sudo tee /etc/consul.d/config.json
{
  "node_name": "$NODE_ID",
  "bind_addr": "$CURRENT_IP",
  "data_dir": "/tmp/consul",
  "server": false,
  "client_addr": "0.0.0.0",
  "retry_join": ["$SEED_IP"],
  "retry_interval": "5s"
}
EOF
fi

# =========================
# CONSUL SYSTEMD SERVICE
# =========================
cat <<EOF | sudo tee /etc/systemd/system/consul.service
[Unit]
Description=Consul Agent
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable consul
sudo systemctl start consul

echo "⏳ Waiting for Consul..."
sleep 5

# =========================
# AUTO DISCOVERY SERVICE
# =========================
cat <<'DISCOVERY' > "$USER_HOME/auto-discover.sh"
#!/bin/bash
SELF_IP=$(hostname -I | awk '{print $1}')
SUBNET=$(echo "$SELF_IP" | awk -F. '{print $1"."$2"."$3}')

while true; do
    for i in $(seq 1 254); do
        IP="${SUBNET}.${i}"
        [[ "$IP" == "$SELF_IP" ]] && continue
        ping -c 1 -W 1 "$IP" >/dev/null 2>&1 && \
            consul join "$IP" >/dev/null 2>&1 || true
    done
    sleep 30
done
DISCOVERY
chmod +x "$USER_HOME/auto-discover.sh"

cat <<EOF | sudo tee /etc/systemd/system/consul-auto-join.service
[Unit]
Description=Consul Auto Discovery
After=consul.service

[Service]
User=$USER
ExecStart=$USER_HOME/auto-discover.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable consul-auto-join
sudo systemctl start consul-auto-join

# =========================
# REDIS SETUP
# =========================
echo "🔧 Configuring Redis..."
sudo sed -i "s/^bind .*/bind 0.0.0.0/" /etc/redis/redis.conf
sudo sed -i "s/^protected-mode yes/protected-mode no/" /etc/redis/redis.conf
sudo systemctl restart redis-server
sudo systemctl enable redis-server

cat <<EOF | sudo tee /etc/consul.d/redis.json
{
  "service": {
    "name": "redis",
    "port": 6379,
    "check": {
      "tcp": "localhost:6379",
      "interval": "5s"
    }
  }
}
EOF

consul reload 2>/dev/null || sudo systemctl restart consul

# =========================
# PYTHON VENV + CELERY
# =========================
echo "🐍 Setting up Python environment..."
python3 -m venv "$USER_HOME/cluster-env"
source "$USER_HOME/cluster-env/bin/activate"
pip install celery redis requests

# =========================
# WORKER CODE
# =========================
cat <<'WORKER' > "$USER_HOME/worker.py"
import requests
import random
import socket
from celery import Celery, group

def get_redis():
    try:
        r = requests.get(
            "http://127.0.0.1:8500/v1/health/service/redis?passing=true",
            timeout=3
        )
        nodes = r.json()
        if nodes:
            node = random.choice(nodes)
            ip = node["Service"]["Address"] or node["Node"]["Address"]
            return f"redis://{ip}:6379/0"
    except Exception:
        pass
    return "redis://127.0.0.1:6379/0"

broker = get_redis()
app = Celery("cluster", broker=broker, backend=broker)
app.conf.worker_hijack_root_logger = False

@app.task
def square(x):
    host = socket.gethostname()
    result = x * x
    return {"host": host, "input": x, "result": result}

@app.task
def add(x, y):
    return x + y

@app.task
def distributed_compute(n):
    job = group(square.s(i) for i in range(n))
    results = job.apply_async().get(timeout=30)
    total = sum(r["result"] for r in results)
    hosts = set(r["host"] for r in results)
    return {
        "total": total,
        "tasks": n,
        "workers_used": list(hosts)
    }
WORKER

# =========================
# CELERY SYSTEMD SERVICE
# =========================
cat <<EOF | sudo tee /etc/systemd/system/celery-worker.service
[Unit]
Description=Celery Worker
After=network-online.target consul.service redis-server.service
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$USER_HOME
Environment="PATH=$USER_HOME/cluster-env/bin:/usr/local/bin:/usr/bin:/bin"
ExecStartPre=/bin/sleep 5
ExecStart=$USER_HOME/cluster-env/bin/celery -A worker worker \
    --loglevel=info \
    --concurrency=2 \
    --hostname=$NODE_ID@%h
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable celery-worker
sudo systemctl restart celery-worker

# =========================
# DONE
# =========================
echo ""
echo "============================================"
if $IS_SEED; then
    echo "  🌱 $NODE_ID — SEED (server)"
else
    echo "  🔗 $NODE_ID — WORKER (joined $SEED_IP)"
fi
echo ""
echo "  Check cluster:"
echo "    consul members"
echo ""
echo "  Consul UI:"
if $IS_SEED; then
    echo "    http://$CURRENT_IP:8500"
else
    echo "    http://$SEED_IP:8500"
fi
echo ""
echo "  Test distributed compute:"
echo "    source ~/cluster-env/bin/activate"
echo "    python3 -c \""
echo "      from worker import distributed_compute"
echo "      print(distributed_compute.delay(20).get(timeout=30))"
echo "    \""
echo "============================================"
