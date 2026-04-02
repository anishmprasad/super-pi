#!/bin/bash

echo "🚀 Setting up ULTIMATE self-healing cluster..."

USER_HOME=$(eval echo ~$USER)

# =========================
# INSTALL BASE
# =========================
sudo apt update -y
sudo apt install -y unzip curl python3-venv python3-pip redis-server

# =========================
# INSTALL CONSUL
# =========================
echo "🧠 Installing Consul..."

CONSUL_VERSION="1.17.0"

curl -LO https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_arm64.zip
unzip consul_${CONSUL_VERSION}_linux_arm64.zip
sudo mv consul /usr/local/bin/
rm consul_${CONSUL_VERSION}_linux_arm64.zip

# =========================
# CONSUL CONFIG
# =========================
sudo mkdir -p /etc/consul.d

CURRENT_IP=$(hostname -I | awk '{print $1}')

cat <<EOF | sudo tee /etc/consul.d/config.json
{
  "node_name": "$(hostname)",
  "bind_addr": "$CURRENT_IP",
  "data_dir": "/tmp/consul",
  "server": true,
  "bootstrap_expect": 3,
  "retry_join": ["provider=lan"],
  "client_addr": "0.0.0.0",
  "ui": false
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

# =========================
# START CONSUL
# =========================
sudo systemctl daemon-reload
sudo systemctl enable consul
sudo systemctl start consul

# =========================
# PYTHON ENV
# =========================
python3 -m venv $USER_HOME/cluster-env
source $USER_HOME/cluster-env/bin/activate

pip install celery redis

# =========================
# REDIS CONFIG (LOCAL ONLY)
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
# WORKER (DYNAMIC REDIS DISCOVERY)
# =========================
cat <<EOF > $USER_HOME/worker.py
import requests
from celery import Celery

def get_redis():
    try:
        r = requests.get("http://127.0.0.1:8500/v1/catalog/service/redis")
        data = r.json()
        if data:
            ip = data[0]["ServiceAddress"] or data[0]["Address"]
            return f"redis://{ip}:6379/0"
    except:
        pass
    return "redis://127.0.0.1:6379/0"

broker_url = get_redis()

app = Celery('cluster', broker=broker_url, backend=broker_url)

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

# =========================
# ENABLE EVERYTHING
# =========================
sudo systemctl daemon-reload
sudo systemctl enable celery-worker
sudo systemctl start celery-worker

echo ""
echo "🔥 ULTIMATE CLUSTER READY!"
echo ""
echo "Test:"
echo "source $USER_HOME/cluster-env/bin/activate"
echo "python3 -c \"from worker import work; print(work.delay(5).get())\""
