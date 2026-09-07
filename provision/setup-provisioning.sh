#!/bin/bash
# Runs INSIDE the GNS3 "server" Ubuntu VM.
# Turns it into an ONIE provisioning server on its LAN-facing NIC:
#   - static IP on the LAN interface
#   - dnsmasq DHCP handing out addresses + the ONIE installer URL
#   - HTTP server offering the NOS installer via the ONIE discovery "waterfall"
#
# ONIE discovers the installer with zero extra config because dnsmasq advertises
# itself as the DHCP server (option 54); ONIE then probes that IP:80 for a list
# of default file names ending in the catch-all "onie-installer". We also set
# DHCP option 114 (default-url) to point straight at the image.
set -eux

LAN_IP=${LAN_IP:-172.31.0.1}
LAN_CIDR=${LAN_CIDR:-24}
DHCP_FROM=${DHCP_FROM:-172.31.0.50}
DHCP_TO=${DHCP_TO:-172.31.0.150}
WEBROOT=${WEBROOT:-/srv/onie}
INSTALLER_SRC=${INSTALLER_SRC:-/home/ubuntu/demo-installer.bin}

# --- Pick the LAN interface: the ethernet NIC WITHOUT the default route ---
WAN_IF=$(ip -o route show default | awk '{print $5; exit}')
LAN_IF=""
for i in $(ls /sys/class/net | grep -E '^(en|eth)'); do
    [ "$i" = "$WAN_IF" ] && continue
    LAN_IF="$i"; break
done
if [ -z "$LAN_IF" ]; then echo "No LAN interface found (WAN=$WAN_IF)"; exit 1; fi
echo "WAN_IF=$WAN_IF  LAN_IF=$LAN_IF"

# --- Install packages (needs WAN/internet) ---
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update -y
sudo -E apt-get install -y dnsmasq

# --- Static IP on the LAN interface via netplan ---
sudo tee /etc/netplan/99-onie-lan.yaml >/dev/null <<EOF
network:
  version: 2
  ethernets:
    $LAN_IF:
      dhcp4: false
      addresses: [$LAN_IP/$LAN_CIDR]
EOF
sudo chmod 600 /etc/netplan/99-onie-lan.yaml
sudo netplan apply
sleep 2
ip -br addr show "$LAN_IF"

# --- Publish the installer under all names ONIE looks for ---
sudo mkdir -p "$WEBROOT"
sudo cp "$INSTALLER_SRC" "$WEBROOT/onie-installer"
# Most-specific waterfall names for the kvm_x86_64 target (belt and suspenders):
for n in onie-installer-x86_64 onie-installer-x86_64-kvm_x86_64 \
         onie-installer-x86_64-kvm_x86_64-r0 onie-installer-kvm_x86_64; do
    sudo ln -sf onie-installer "$WEBROOT/$n"
done
ls -l "$WEBROOT"

# --- HTTP server (systemd unit, python3 stdlib, no extra packages) ---
sudo tee /etc/systemd/system/onie-http.service >/dev/null <<EOF
[Unit]
Description=ONIE installer HTTP server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 -m http.server 80 --directory $WEBROOT --bind $LAN_IP
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- dnsmasq: DHCP only on the LAN interface, plus ONIE default-url ---
sudo tee /etc/dnsmasq.d/onie.conf >/dev/null <<EOF
interface=$LAN_IF
bind-interfaces
except-interface=$WAN_IF
dhcp-range=$DHCP_FROM,$DHCP_TO,12h
dhcp-option=3,$LAN_IP
dhcp-option=6,$LAN_IP
# ONIE default-url (DHCP option 114) -> exact installer image
dhcp-option=114,http://$LAN_IP/onie-installer
log-dhcp
EOF
# Avoid dnsmasq fighting systemd-resolved on :53 (DHCP is what we need).
sudo sed -i 's/^#\?port=.*/port=0/' /etc/dnsmasq.conf || true
grep -q '^port=0' /etc/dnsmasq.conf || echo 'port=0' | sudo tee -a /etc/dnsmasq.conf

sudo systemctl daemon-reload
sudo systemctl enable --now onie-http.service
sudo systemctl restart dnsmasq
sudo systemctl --no-pager --full status dnsmasq | head -n 8 || true

echo "=== Provisioning server ready on $LAN_IF ($LAN_IP) ==="
echo "HTTP:  http://$LAN_IP/onie-installer"
echo "DHCP:  $DHCP_FROM-$DHCP_TO"
