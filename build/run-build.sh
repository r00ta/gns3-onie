#!/bin/bash
# Runs on the GNS3 host (ubuntu@server). Builds the Debian 10 image and
# compiles ONIE for kvm_x86_64 inside it, sharing the ONIE source tree.
set -eux

HERE="$(cd "$(dirname "$0")" && pwd)"
ONIE_DIR="${ONIE_DIR:-$HOME/onie-build/onie}"
IMAGE=onie-build-env:deb10

if [ ! -d "$ONIE_DIR" ]; then
  echo "ONIE source not found at $ONIE_DIR" >&2
  exit 1
fi

# Restrict ONIE network discovery to the management port (eth0), like a real
# switch: `dhcp=eth0` on the kernel cmdline makes net_intf() return only eth0
# instead of probing every wired data port (see onie .../networking.sh). Idempotent.
MACHINE_MK="$ONIE_DIR/machine/kvm_x86_64/machine.make"
if [ -f "$MACHINE_MK" ] && ! grep -q 'dhcp=eth0' "$MACHINE_MK"; then
  echo 'EXTRA_CMDLINE_LINUX = dhcp=eth0' >> "$MACHINE_MK"
fi

# Stage the crosstool-NG companion tarballs into ONIE's download cache first.
# Unlike ONIE's own packages, xtools.make fetches these from the OCP mirror
# ONLY (no upstream fallback), so a mirror outage otherwise aborts the build.
ONIE_DIR="$ONIE_DIR" bash "$HERE/preseed-downloads.sh"

# Build the build-environment image, matching the host user's UID/GID so the
# bind-mounted source tree is writable inside the container.
sudo docker build -t "$IMAGE" \
  --build-arg BUILD_UID="$(id -u)" \
  --build-arg BUILD_GID="$(id -g)" \
  "$HERE"

# Compile ONIE. The source tree is bind-mounted; build products land in
# $ONIE_DIR/build/images on the host. Runs as uid 1000 (== ubuntu == build).
sudo docker run --rm \
  -v "$ONIE_DIR":/home/build/onie \
  -v "$HERE/build-onie.sh":/home/build/build-onie.sh:ro \
  -e ONIE_DIR=/home/build/onie \
  -e SKIP_CLEAN="${SKIP_CLEAN:-}" \
  "$IMAGE" \
  bash --login /home/build/build-onie.sh
