#!/bin/bash
# Runs on the GNS3 host. Publishes the baked ONIE qcow2 into the GNS3 image
# store, renders the .gns3a appliance descriptor (with real md5/size), then
# registers the template and builds the base topology via the GNS3 API.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"

WORKDIR="${ONIE_WORKDIR:-$HOME/onie-build}"
QCOW2="${QCOW2:-$WORKDIR/onie-kvm_x86_64.qcow2}"
IMAGES="${IMAGES:-${ONIE_SRC:-$WORKDIR/onie}/build/images}"
GNS3_IMG_DIR="${GNS3_IMAGE_DIR:-/opt/gns3/images/QEMU}"
DEST_NAME="onie-kvm_x86_64.qcow2"

[ -f "$QCOW2" ] || { echo "Missing appliance disk: $QCOW2" >&2; exit 1; }

# 1. Publish the disk (and recovery ISO, if present) into the image store.
sudo install -o gns3 -g gns3 -m 644 "$QCOW2" "$GNS3_IMG_DIR/$DEST_NAME"
RECOVERY="$IMAGES/onie-recovery-x86_64-${ONIE_MACHINE:-kvm_x86_64}-r0.iso"
[ -f "$RECOVERY" ] && sudo install -o gns3 -g gns3 -m 644 "$RECOVERY" "$GNS3_IMG_DIR/$(basename "$RECOVERY")"

# 2. Render the .gns3a descriptor with the real checksum + size.
MD5=$(md5sum "$QCOW2" | awk '{print $1}')
SIZE=$(stat -c%s "$QCOW2")
sed -e "s/__MD5__/$MD5/" -e "s/__SIZE__/$SIZE/" \
    -e "s/__RAM__/${APPLIANCE_RAM:-8192}/" \
    -e "s/__ADAPTERS__/${APPLIANCE_ADAPTERS:-9}/" \
    "$HERE/ONIE-kvm_x86_64.gns3a.template" > "$HERE/ONIE-kvm_x86_64.gns3a"
echo "Wrote $HERE/ONIE-kvm_x86_64.gns3a (md5=$MD5 size=$SIZE)"

# 3. Register the template + build the topology.
python3 "$HERE/setup-gns3.py"
