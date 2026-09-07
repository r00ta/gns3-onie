#!/usr/bin/env bash
# Render the GNS3 .gns3a appliance descriptor from the template, filling in the
# real md5/size of the baked qcow2. Prints the output path.
#
# Env (defaults in brackets):
#   QCOW2      baked appliance disk   [$ONIE_WORKDIR/onie-<machine>.qcow2]
#   TEMPLATE   descriptor template    [gns3/ONIE-kvm_x86_64.gns3a.template]
#   GNS3A_OUT  output descriptor      [<qcow2 dir>/onie-<machine>.gns3a]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck disable=SC1091
. "$REPO/lib.sh"

WORKDIR="${ONIE_WORKDIR:-$HOME/onie-build}"
MACHINE="${ONIE_MACHINE:-kvm_x86_64}"
QCOW2="${QCOW2:-$WORKDIR/onie-${MACHINE}.qcow2}"
TEMPLATE="${TEMPLATE:-$REPO/gns3/ONIE-kvm_x86_64.gns3a.template}"
GNS3A_OUT="${GNS3A_OUT:-$(dirname "$QCOW2")/onie-${MACHINE}.gns3a}"

[ -f "$QCOW2" ]    || { echo "Missing appliance disk: $QCOW2" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "Missing template: $TEMPLATE" >&2; exit 1; }

MD5="$(md5sum "$QCOW2" | awk '{print $1}')"
SIZE="$(stat -c%s "$QCOW2")"
sed -e "s/__MD5__/$MD5/" -e "s/__SIZE__/$SIZE/" \
    -e "s/__RAM__/${APPLIANCE_RAM:-8192}/" \
    -e "s/__ADAPTERS__/${APPLIANCE_ADAPTERS:-9}/" \
    "$TEMPLATE" > "$GNS3A_OUT"
echo "$GNS3A_OUT"
