#!/bin/bash
# Runs on the GNS3 host. Invokes build-embed-iso.sh inside the Debian 10
# build container to produce an "embed-default" recovery ISO.
set -eux

HERE="$(cd "$(dirname "$0")" && pwd)"
ONIE_DIR="${ONIE_DIR:-$HOME/onie-build/onie}"
IMAGE=onie-build-env:deb10

sudo docker run --rm \
  -v "$ONIE_DIR":/home/build/onie \
  -v "$HERE/build-embed-iso.sh":/home/build/build-embed-iso.sh:ro \
  -e ONIE_DIR=/home/build/onie \
  "$IMAGE" \
  bash --login /home/build/build-embed-iso.sh
