#!/bin/bash

echo "🚀 Setting up ZERO-CONFIG SELF-HEALING CLUSTER..."

# =========================
# AUTO DISCOVER NODES
# =========================
echo "🔍 Discovering cluster nodes..."

SUBNET=$(hostname -I | awk -F. '{print $1"."$2"."$3}')
NODES=()

for i in {1..254}; do
  IP="$SUBNET.$i"
  ping -c 1 -W 1 $IP &>/dev/null && NODES+=("$IP")
done

echo "Found nodes: ${NODES[@]}"

MASTER_IP=${NODES[0]}
CURRENT_IP=$(hostname -I | awk '{print $1}')

# =========================
# INSTALL
# =========================
sudo apt update -y
sudo apt install -y redis-server python3-pip net-tools

pip3 install celery redis

# =========================
# REDIS CONFIG
# =========================
sudo sed -i "s/^bind .*/bind 0.0.0.0/" /etc/redis/redis.conf
sudo sed -i "s/^protected-mode yes/protected-mode no/" /etc/redis/redis.conf

# Persistence
sudo sed -i '/^# appendonly yes/a appendonly yes' /etc/redis/redis.conf
sudo sed -i '/^appendonly yes/a appendfsync everysec' /etc/redis/redis.conf

# Replica setup
if [ "$CURRENT_IP" != "$MASTER_IP" ]; then
  sudo sed -i '/^replicaof/d' /etc/redis/redis.conf
  echo "replicaof $MASTER_IP 6379" | sudo tee -a /etc/redis/redis.conf
fi

sudo systemctl restart redis
sudo systemctl enable redis

# =========================
# SENTINEL CONFIG
# =========================
sudo mkdir -p /etc/redis-sentinel

cat <<EOF | sudo tee /etc/redis-sentinel/sentinel.conf
port 26379
sentinel monitor mymaster $MASTER_IP 6379 2
sentinel down-after-milliseconds mymaster 3000
sentinel failover-timeout mymaster 15000
sentinel parallel-syncs mymaster 1
EOF

# =========================
# SENTINEL SERVICE
# =========================
cat <<EOF | sudo tee /etc/systemd/system/redis-sentinel.service
[Unit]
Description=Redis Sentinel
After=network.target

[Service]
ExecStart=/usr/bin/redis-server /etc/redis-sentinel/sentinel.conf --sentinel
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# =========================
# GENERATE SENTINEL LIST
# =========================
SENTINELS=""
for IP in "${NODES[@]}"; do
  SENTINELS+="sentinel://$IP:26379;"
done

# =========================
# CELERY WORKER
# =========================
cat <<EOF > /home/pi/worker.py
from celery import Celery

app = Celery(
    'cluster',
    broker='${SENTINELS}0',
    backend='redis://$MASTER_IP:6379/0'
)

app.conf.broker_transport_options = {
    'master_name': 'mymaster'
}

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
After=network.target redis.service redis-sentinel.service

[Service]
User=pi
WorkingDirectory=/home/pi
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/celery -A worker worker --loglevel=info --concurrency=2
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# =========================
# ENABLE SERVICES
# =========================
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

sudo systemctl enable redis
sudo systemctl enable redis-sentinel
sudo systemctl enable celery-worker

sudo systemctl restart redis
sudo systemctl restart redis-sentinel
sudo systemctl restart celery-worker

echo ""
echo "🔥 ZERO-CONFIG CLUSTER READY!"
echo "Nodes: ${NODES[@]}"
echo ""
echo "Test:"
echo "python3 -c \"from worker import work; print(work.delay(10).get())\""
