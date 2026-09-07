#!/usr/bin/env bash
# Generator 1: build the ONIE appliance disk (qcow2) and its GNS3 .gns3a
# descriptor from source, end to end. Runs on the GNS3 host.
#
# Steps:
#   1. compile ONIE for kvm_x86_64 in a Debian 10 container (run-build.sh)
#   2. rebuild the recovery ISO so it defaults to "Embed ONIE" (run-embed-iso.sh)
#   3. bake the appliance qcow2 from that ISO (make-appliance-disk.sh)
#   4. render the .gns3a descriptor with the disk's real md5/size
#
# Outputs (under $ONIE_WORKDIR, default ~/onie-build):
#   onie-kvm_x86_64.qcow2   the GNS3-ready appliance disk
#   onie-kvm_x86_64.gns3a   the importable appliance descriptor
#
# Env:
#   ONIE_WORKDIR       work/output dir              [~/onie-build]
#   ONIE_DIR           ONIE source tree             [$ONIE_WORKDIR/onie]
#   SKIP_ONIE_BUILD=1  reuse an existing ONIE build (skip step 1)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck disable=SC1091
. "$REPO/lib.sh"

WORKDIR="${ONIE_WORKDIR:-$HOME/onie-build}"
ONIE_DIR="${ONIE_DIR:-$WORKDIR/onie}"
ONIE_REPO="${ONIE_REPO:-https://github.com/opencomputeproject/onie}"

mkdir -p "$WORKDIR"
if [ ! -d "$ONIE_DIR" ]; then
    echo "==> Cloning ONIE source into $ONIE_DIR"
    git clone "$ONIE_REPO" "$ONIE_DIR"
fi

if [ "${SKIP_ONIE_BUILD:-}" != "1" ]; then
    echo "==> [1/4] Compiling ONIE (this can take 30-40 min on first run)"
    ONIE_DIR="$ONIE_DIR" bash "$REPO/build/run-build.sh"
else
    echo "==> [1/4] Skipping ONIE compile (SKIP_ONIE_BUILD=1)"
fi

echo "==> [2/4] Building the embed-default recovery ISO"
ONIE_DIR="$ONIE_DIR" bash "$REPO/build/run-embed-iso.sh"

echo "==> [3/4] Baking the appliance disk"
bash "$REPO/appliance/make-appliance-disk.sh"

echo "==> [4/4] Rendering the .gns3a descriptor"
GNS3A="$(bash "$REPO/appliance/render-gns3a.sh")"

MACHINE="${ONIE_MACHINE:-kvm_x86_64}"
echo
echo "=== ONIE appliance ready ==="
ls -l "$WORKDIR/onie-${MACHINE}.qcow2" "$GNS3A"
echo "Deploy it into GNS3 with:  bash gns3/deploy-appliance.sh"
