#!/bin/bash
# Runs on the GNS3 host. Copies a NOS installer and the provisioning setup
# script into the server VM (reached over the GNS3 NAT network) and runs it, so
# the server hands out DHCP and serves the installer over HTTP on its LAN NIC.
#
# By default it publishes the ONIE demo NOS installer (a quick end-to-end smoke
# test). To provision SONiC instead, build sonic-vs.bin and use
# sonic/push-sonic-installer.sh, or pass INSTALLER=/path/to/sonic-vs.bin here.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"

WORKDIR="${ONIE_WORKDIR:-$HOME/onie-build}"
IMAGES="${IMAGES:-${ONIE_SRC:-$WORKDIR/onie}/build/images}"
INSTALLER="${INSTALLER:-$IMAGES/demo-installer-x86_64-${ONIE_MACHINE:-kvm_x86_64}-r0.bin}"
SETUP="$HERE/setup-provisioning.sh"
USER="${SERVER_SSH_USER:-ubuntu}"
PASS="${SERVER_SSH_PASS:-ubuntu}"

[ -f "$INSTALLER" ] || { echo "Missing installer: $INSTALLER" >&2; exit 1; }
command -v sshpass >/dev/null || sudo apt-get install -y sshpass

IP="${SERVER_IP:-$(wait_server_ip)}"
echo "Server VM IP: $IP"

run_ssh() { sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$IP" "$@"; }
run_scp() { sshpass -p "$PASS" scp $SSH_OPTS "$@"; }

for i in $(seq 1 30); do run_ssh true 2>/dev/null && break; echo "waiting for sshd... ($i)"; sleep 5; done

run_scp "$INSTALLER" "$USER@$IP:/home/$USER/nos-installer.bin"
run_scp "$SETUP" "$USER@$IP:/home/$USER/setup-provisioning.sh"
run_ssh "chmod +x setup-provisioning.sh && \
    INSTALLER_SRC=/home/$USER/nos-installer.bin \
    LAN_IP='${LAN_IP:-172.31.0.1}' LAN_CIDR='${LAN_CIDR:-24}' \
    DHCP_FROM='${DHCP_FROM:-172.31.0.50}' DHCP_TO='${DHCP_TO:-172.31.0.150}' \
    sudo -E bash setup-provisioning.sh"

echo "=== Provisioning server configured on $IP ==="
