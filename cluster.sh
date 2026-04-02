#!/bin/bash

echo "🚀 Starting FINAL STABLE AUTO CLUSTER..."

USER_HOME=$(eval echo ~$USER)

# =========================
# INSTALL
# =========================
sudo apt update -y
sudo apt install -y unzip curl python3-venv python3-pip redis-server avahi-daemon avahi-utils

# =========================
# AVAHI
# =========================
sudo systemctl enable avahi-daemon
sudo systemctl restart avahi-daemon

# =========================
# HOSTNAME
# =========================
RAND=$(date +%s)
HOSTNAME="superpi-$RAND"
sudo hostnamectl set-hostname $HOSTNAME

echo "📡 Hostname: $HOSTNAME.local"

sleep 5

# =========================
# GET IPv4 ONLY
# =========================
CURRENT_IP=$(hostname -I | awk '{print $1}')
echo "Using IP: $CURRENT_IP"

# =========================
# INSTALL CONSUL
# =========================
CONSUL_VERSION="1.17.0"

curl -sLO https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_arm64.zip
unzip -o consul_${CONSUL_VERSION}_linux_arm64.zip
sudo mv consul /usr/local/bin/
rm consul_${CONSUL_VERSION}_linux_arm64.zip

# =========================
# CONSUL CONFIG (SAFE)
# =========================
sudo mkdir -p /etc/consul.d

cat <<EOF | sudo tee /etc/consul.d/config.json
{
  "node_name": "$HOSTNAME",
  "bind_addr": "$CURRENT_IP",
  "data_dir": "/tmp/consul",
  "server": true,
  "bootstrap_expect": 1,
  "retry_join": ["127.0.0.1"],
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

sleep 3

# =========================
# AUTO JOIN (IPv4 ONLY FIX)
# =========================
cat <<EOF > $USER_HOME/auto-join.sh
#!/bin/bash

while true; do
  NODES=\$(avahi-browse -rt _workstation._tcp | grep superpi | awk '{print \$NF}' | sed 's/.local//')

  for node in \$NODES; do
    IP=\$(getent ahostsv4 "\$node.local" | awk '{print \$1}' | head -n 1)

    if [ ! -z "\$IP" ]; then
      consul join \$IP >/dev/null 2>&1
    fi
  done

  sleep 10
done
EOF

chmod +x $USER_HOME/auto-join.sh

# =========================
# AUTO JOIN SERVICE
# =========================
cat <<EOF | sudo tee /etc/systemd/system/consul-auto-join.service
[Unit]
Description=Consul Auto Join
After=consul.service

[Service]
User=$USER
ExecStart=$USER_HOME/auto-join.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable consul-auto-join
sudo systemctl start consul-auto-join

# =========================
# PYTHON ENV
# =========================
python3 -m venv $USER_HOME/cluster-env
source $USER_HOME/cluster-env/bin/activate
pip install celery redis requests

# =========================
# REDIS
# =========================
sudo sed -i "s/^bind .*/bind 0.0.0.0/" /etc/redis/redis.conf
sudo systemctl restart redis-server
sudo systemctl enable redis-server

# =========================
# REGISTER REDIS
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
# WORKER
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
echo "🔥 FINAL CLUSTER READY (IPv4 FIXED)"
echo ""
echo "Check:"
echo "consul members"
