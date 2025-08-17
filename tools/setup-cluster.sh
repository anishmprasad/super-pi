#!/bin/bash
set -e

# ===== CONFIG =====
VIP="192.168.68.100"   # Virtual shared IP
NETMASK="24"           # Subnet mask
INTERFACE=""
NODE_IP=""
PRIORITY=""

# Gateway & fallback for health-check
GATEWAY_IP="192.168.68.1"
PING_TARGET="8.8.8.8"

# Log file path
LOG_FILE="/var/log/keepalived-vip.log"

# ===== Detect active interface =====
detect_interface() {
  if ip link show eth0 | grep -q "state UP"; then
    INTERFACE="eth0"
  elif ip link show wlan0 | grep -q "state UP"; then
    INTERFACE="wlan0"
  else
    echo "❌ No active network interface found (eth0/wlan0)."
    exit 1
  fi
}

# ===== Detect node IP =====
detect_ip() {
  NODE_IP=$(hostname -I | awk '{print $1}')
  if [ -z "$NODE_IP" ]; then
    echo "❌ Could not detect node IP."
    exit 1
  fi
}

# ===== Auto-calculate priority =====
detect_priority() {
  LAST_OCTET=$(echo "$NODE_IP" | awk -F. '{print $4}')
  PRIORITY=$((255 - LAST_OCTET))
  if [ "$PRIORITY" -lt 50 ]; then
    PRIORITY=50   # floor priority
  fi
}

# ===== Install keepalived =====
install_keepalived() {
  sudo apt-get update
  sudo apt-get install -y keepalived
  sudo systemctl enable keepalived
}

# ===== Configure keepalived =====
configure_keepalived() {
  sudo mkdir -p /etc/keepalived

  # keepalived.conf
  cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
vrrp_script chk_network {
    script "/etc/keepalived/check_network.sh"
    interval 2
    weight -20
    fall 2
    rise 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface $INTERFACE
    virtual_router_id 51
    priority $PRIORITY
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 42secret
    }
    virtual_ipaddress {
        $VIP/$NETMASK
    }
    track_script {
        chk_network
    }

    notify_master "/etc/keepalived/notify.sh master"
    notify_backup "/etc/keepalived/notify.sh backup"
    notify_fault  "/etc/keepalived/notify.sh fault"
}
EOF

  # health-check script
  cat <<EOF | sudo tee /etc/keepalived/check_network.sh
#!/bin/bash
if ping -c1 -W1 $GATEWAY_IP > /dev/null 2>&1; then
  exit 0
fi
if ping -c1 -W1 $PING_TARGET > /dev/null 2>&1; then
  exit 0
fi
exit 1
EOF
  sudo chmod +x /etc/keepalived/check_network.sh

  # notify script (logging)
  cat <<'EOF' | sudo tee /etc/keepalived/notify.sh
#!/bin/bash
LOG_FILE="/var/log/keepalived-vip.log"
EVENT=$1
DATE=$(date '+%Y-%m-%d %H:%M:%S')
NODE_IP=$(hostname -I | awk '{print $1}')

case $EVENT in
  master)
    echo "[$DATE] Node $NODE_IP became MASTER (VIP active)" >> $LOG_FILE
    ;;
  backup)
    echo "[$DATE] Node $NODE_IP became BACKUP (VIP released)" >> $LOG_FILE
    ;;
  fault)
    echo "[$DATE] Node $NODE_IP FAULT (network or service issue)" >> $LOG_FILE
    ;;
  *)
    echo "[$DATE] Unknown event: $EVENT" >> $LOG_FILE
    ;;
esac
EOF
  sudo chmod +x /etc/keepalived/notify.sh

  # log rotation - delete after 1 day
  cat <<EOF | sudo tee /etc/logrotate.d/keepalived-vip
/var/log/keepalived-vip.log {
    daily
    missingok
    rotate 1
    notifempty
    create 0640 root adm
}
EOF
}

# ===== Restart keepalived =====
restart_keepalived() {
  sudo systemctl restart keepalived
  sleep 2
  systemctl status keepalived --no-pager
}

# ===== Main =====
main() {
  detect_interface
  detect_ip
  detect_priority
  install_keepalived
  configure_keepalived
  restart_keepalived

  echo "✅ Node setup complete."
  echo "   Node IP: $NODE_IP"
  echo "   Interface: $INTERFACE"
  echo "   Priority: $PRIORITY"
  echo "   Virtual IP: $VIP"
  echo "   Logs: $LOG_FILE (rotates daily, kept 1 day)"
}

main
