#!/bin/bash
# setup-cluster.sh
# Usage:
#   On first node (cluster init):
#     sudo ./setup-cluster.sh master-init 192.168.68.100
#   On second/third node:
#     sudo ./setup-cluster.sh master-join 192.168.68.100 <ANY-EXISTING-MASTER-IP>

set -e

ROLE=$1         # master-init | master-join
VIP=$2          # Virtual IP for the cluster
JOIN_IP=$3      # IP of existing master (only for join)

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (use sudo)"
  exit 1
fi

echo "=== [1/4] Updating system ==="
apt-get update -y && apt-get upgrade -y
apt-get install -y curl keepalived

echo "=== [2/4] Installing k3s ==="
if [ "$ROLE" == "master-init" ]; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --cluster-init" sh -
elif [ "$ROLE" == "master-join" ]; then
  if [ -z "$JOIN_IP" ]; then
    echo "Usage: ./setup-cluster.sh master-join <VIP> <JOIN_IP>"
    exit 1
  fi
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --server https://$JOIN_IP:6443" sh -
else
  echo "❌ Invalid role: $ROLE (use master-init or master-join)"
  exit 1
fi

echo "=== [3/4] Configuring Keepalived ==="
# Priorities: highest wins VIP
if [[ "$HOSTNAME" == *"58" ]]; then
  PRIORITY=150
elif [[ "$HOSTNAME" == *"71" ]]; then
  PRIORITY=140
else
  PRIORITY=130
fi

cat >/etc/keepalived/keepalived.conf <<EOF
vrrp_instance VI_1 {
  state BACKUP
  interface eth0
  virtual_router_id 51
  priority $PRIORITY
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass mysecret
  }
  virtual_ipaddress {
    $VIP/24 dev eth0
  }
}
EOF

systemctl enable keepalived
systemctl restart keepalived

echo "=== [4/4] Finished ==="
echo "🎉 Role: $ROLE"
echo "✅ You can SSH or kubectl at $VIP"
