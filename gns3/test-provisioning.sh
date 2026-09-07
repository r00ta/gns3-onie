#!/bin/bash
# Runs on the GNS3 host. (Re)boots the ONIE node and captures its serial console
# while it performs DHCP discovery and installs the NOS from the server VM.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"

WATCH_SECS="${WATCH_SECS:-360}"
LOG="${LOG:-${ONIE_WORKDIR:-$HOME/onie-build}/onie-console.log}"
ONIE_NAME="${GNS3_ONIE_NAME:-onie-switch}"

read -r PID NID CONSOLE < <(GNS3_ONIE_NAME="$ONIE_NAME" python3 - "$HERE" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1]))
import gns3lib as g
pid = g.project_id(create=False)
node = g.find_node(pid, os.environ.get("GNS3_ONIE_NAME", "onie-switch"))
print(pid, node["node_id"], node["console"])
PY
)
echo "ONIE node=$NID console=$CONSOLE"

API="${GNS3_API:-http://localhost:3080/v2}"
curl -s -X POST "$API/projects/$PID/nodes/$NID/stop" >/dev/null || true
sleep 3
curl -s -X POST "$API/projects/$PID/nodes/$NID/start" >/dev/null
echo "Capturing ONIE console for ${WATCH_SECS}s -> $LOG"
python3 "$HERE/watch-console.py" 127.0.0.1 "$CONSOLE" "$WATCH_SECS" | tee "$LOG" || true

echo "=== Provisioning markers ==="
grep -iE "discover|dhcp|installer|Installing|ONIE:|NOS install|successful" "$LOG" | tail -40 || true
