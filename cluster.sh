#!/bin/bash

echo "🚀 Setting up FINAL CLUSTER (Production Stable)..."

USER_HOME=$(eval echo ~$USER)

# =========================
# INSTALL PACKAGES
# =========================
sudo apt update -y
sudo apt install -y curl unzip python3-venv python3-pip redis-server

# =========================
# GET LOCAL IP + SUBNET
# =========================
CURRENT_IP=$(hostname -I | awk '{print $1}')
SUBNET=$(echo $CURRENT_IP | awk -F. '{print $1"."$2"."$3}')

echo "IP: $CURRENT_IP"
echo "Subnet: $SUBNET.0/24"

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

cat <<EOF | sudo tee /etc/consul.d/config.json
{
  "node_name": "node-$CURRENT_IP",
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
# AUTO JOIN (SUBNET GOSSIP)
# =========================
cat <<EOF > $USER_HOME/auto-join.sh
#!/bin/bash

SUBNET="$SUBNET"
SELF_IP="$CURRENT_IP"

while true; do
  for i in {1..254}; do
    IP="$SUBNET.\$i"

    if [[ "\$IP" == "\$SELF_IP" ]]; then
      continue
    fi

    ping -c 1 -W 1 \$IP >/dev/null 2>&1 && consul join \$IP >/dev/null 2>&1
  done

  sleep 30
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
# WORKER (DISTRIBUTED ENGINE)
# =========================
cat <<EOF > $USER_HOME/worker.py
import requests
import random
from celery import Celery, group

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

@app.task
def square(x):
    return x * x

@app.task
def sum_results(results):
    return sum(results)

@app.task
def distributed_compute(n):
    tasks = group(square.s(i) for i in range(n))
    result = tasks.apply_async()
    return sum_results.delay(result.get())
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
echo "🔥 CLUSTER READY!"
echo ""
echo "Wait 30 seconds, then:"
echo "consul members"
echo ""
echo "Test distributed compute:"
echo "python3 -c \"from worker import distributed_compute; print(distributed_compute.delay(20).get())\""
