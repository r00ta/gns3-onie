#!/bin/bash
# Runs on the GNS3 host. Copies the reconstructed SONiC ONIE installer
# (sonic-vs.bin) into the server VM and publishes it as the ONIE discovery
# target, replacing any previous installer. ONIE then installs SONiC.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"

WORKDIR="${ONIE_WORKDIR:-$HOME/onie-build}"
BIN="${BIN:-$WORKDIR/sonic-pkg/target/sonic-vs.bin}"
USER="${SERVER_SSH_USER:-ubuntu}"
PASS="${SERVER_SSH_PASS:-ubuntu}"
WEBROOT="${WEBROOT:-/srv/onie}"

[ -f "$BIN" ] || { echo "Missing installer: $BIN" >&2; exit 1; }
command -v sshpass >/dev/null || sudo apt-get install -y sshpass

IP="$(wait_server_ip)"
echo "Server VM IP: $IP"
run_ssh() { sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$IP" "$@"; }

echo "=== VM free space before ==="
run_ssh "df -h / $WEBROOT 2>/dev/null; free -h"

run_ssh "sudo install -d -o $USER -g $USER $WEBROOT"
sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$IP" "cat > /tmp/sonic-vs.bin" < "$BIN"
run_ssh "sudo mv /tmp/sonic-vs.bin $WEBROOT/onie-installer && sudo chmod 644 $WEBROOT/onie-installer && ls -la $WEBROOT"

echo "=== Verify HTTP serves it ==="
run_ssh "curl -sI http://${LAN_IP:-172.31.0.1}/onie-installer | head -5"
echo "=== SONiC installer published as $WEBROOT/onie-installer ==="
