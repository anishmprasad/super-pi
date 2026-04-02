#!/bin/bash

echo "🚀 Starting FULL AUTO CLUSTER..."

USER_HOME=$(eval echo ~$USER)

# =========================
# INSTALL BASE
# =========================
sudo apt update -y
sudo apt install -y unzip curl python3-venv python3-pip redis-server avahi-daemon avahi-utils

# =========================
# START AVAHI
# =========================
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

# =========================
# AUTO HOSTNAME
# =========================
RAND=$(date +%s)
HOSTNAME="superpi-$RAND"

sudo hostnamectl set-hostname $HOSTNAME

echo "📡 Hostname set: $HOSTNAME.local"

sleep 5

# =========================
# DISCOVER NODES (superpi-*)
# =========================
echo "🔍 Discovering nodes..."

NODES=($(avahi-browse -rt _workstation._tcp | grep superpi | awk '{print $NF}' | sed 's/.local//'))

# include self if missing
if [[ ! " ${NODES[@]} " =~ "$HOSTNAME" ]]; then
  NODES+=("$HOSTNAME")
fi

echo "Found nodes: ${NODES[@]}"

# =========================
# RESOLVE TO IPS
# =========================
IPS=()

for node in "${NODES[@]}"; do
  IP=$(getent hosts "$node.local" | awk '{print $1}')
  [ ! -z "$IP" ] && IPS+=("$IP")
done

echo "Resolved IPs: ${IPS[@]}"

CURRENT_IP=$(hostname -I | awk '{print $1}')

# =========================
# INSTALL CONSUL
# =========================
CONSUL_VERSION="1.17.0"

curl -sLO https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_arm64.zip
unzip -o consul_${CONSUL_VERSION}_linux_arm64.zip
sudo mv consul /usr/local/bin/
rm consul_${CONSUL_VERSION}_linux_arm64.zip

# =========================
# CONSUL CONFIG
# =========================
sudo mkdir -p /etc/consul.d

JOIN_CONFIG=""
for ip in "${IPS[@]}"; do
  JOIN_CONFIG+="\"$ip\","
done

cat <<EOF | sudo tee /etc/consul.d/config.json
{
  "node_name": "$HOSTNAME",
  "bind_addr": "$CURRENT_IP",
  "data_dir": "/tmp/consul",
  "server": true,
  "bootstrap_expect": 3,
  "retry_join": [${JOIN_CONFIG%,}],
  "client_addr": "0.0.0.0"
}
EOF

# =========================
# CONSUL SERVICE
# =========================
cat <<EOF | sudo tee /etc/systemd/system/consul.service
[Unit]
Description=Consul Agent
After=network.target

[Service]
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable consul
sudo systemctl restart consul

# =========================
# PYTHON ENV
# =========================
python3 -m venv $USER_HOME/cluster-env
source $USER_HOME/cluster-env/bin/activate
pip install celery redis requests

# =========================
# REDIS SETUP
# =========================
sudo sed -i "s/^bind .*/bind 0.0.0.0/" /etc/redis/redis.conf
sudo systemctl restart redis-server
sudo systemctl enable redis-server

# =========================
# REGISTER REDIS IN CONSUL
# =========================
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

sudo systemctl restart consul

# =========================
# BUILD WORKER
# =========================
cat <<EOF > $USER_HOME/worker.py
import requests
import random
from celery import Celery

def get_redis():
    try:
        r = requests.get("http://127.0.0.1:8500/v1/health/service/redis?passing=true")
        nodes = r.json()
        if nodes:
            node = random.choice(nodes)
            ip = node["Service"]["Address"] or node["Node"]["Address"]
            return f"redis://{ip}:6379/0"
    except:
        pass
    return "redis://127.0.0.1:6379/0"

broker = get_redis()

app = Celery('cluster', broker=broker, backend=broker)

app.conf.update(
    task_acks_late=True,
    worker_prefetch_multiplier=1
)

@app.task(bind=True, autoretry_for=(Exception,), retry_backoff=5)
def work(self, x):
    return x * 2
EOF

# =========================
# CELERY SERVICE
# =========================
cat <<EOF | sudo tee /etc/systemd/system/celery-worker.service
[Unit]
Description=Celery Worker
After=network.target consul.service redis-server.service

[Service]
User=$USER
WorkingDirectory=$USER_HOME
ExecStartPre=/bin/sleep 10
ExecStart=$USER_HOME/cluster-env/bin/celery -A worker worker --loglevel=info --concurrency=2
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable celery-worker
sudo systemctl restart celery-worker

echo ""
echo "🔥 FULL AUTO CLUSTER READY!"
echo "Node: $HOSTNAME"
echo "Cluster nodes: ${IPS[@]}"
echo ""
echo "Test:"
echo "source $USER_HOME/cluster-env/bin/activate"
echo "python3 -c \"from worker import work; print(work.delay(5).get())\""
