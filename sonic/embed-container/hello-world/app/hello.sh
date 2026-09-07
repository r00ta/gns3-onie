#!/bin/sh
# Hello-world payload for the embedded SONiC container.
# Edit this file (and rebuild via sonic/embed-container.sh) to change what the
# container does. It only needs to be a long-running foreground process.
i=0
while true; do
  i=$((i + 1))
  echo "[hello-sonic] #$i hello from the embedded SONiC container at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sleep 15
done
