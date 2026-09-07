#!/bin/bash
# Runs on the GNS3 host (ubuntu@server).
# Bakes a GNS3-ready ONIE appliance disk (qcow2) by booting the embed-default
# recovery ISO under legacy BIOS (SeaBIOS). ONIE detects BIOS firmware and
# installs a legacy-BIOS (i386-pc) GRUB to the disk, so the resulting image
# boots directly in GNS3's default (non-UEFI) QEMU nodes. With -no-reboot,
# QEMU exits automatically when ONIE reboots after embedding.
set -eux
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
[ -f "$HERE/../lib.sh" ] && . "$HERE/../lib.sh"

WORKDIR="${ONIE_WORKDIR:-$HOME/onie-build}"
MACHINE="${ONIE_MACHINE:-kvm_x86_64}"
IMAGES="${IMAGES:-${ONIE_SRC:-$WORKDIR/onie}/build/images}"
RECOVERY_ISO="${RECOVERY_ISO:-$IMAGES/onie-recovery-x86_64-${MACHINE}-r0-embed.iso}"
OUT="${OUT:-$WORKDIR/onie-${MACHINE}.qcow2}"
SIZE="${SIZE:-${APPLIANCE_DISK_SIZE:-40G}}"
LOG="${LOG:-$WORKDIR/embed.log}"

[ -f "$RECOVERY_ISO" ] || { echo "Missing recovery ISO: $RECOVERY_ISO"; exit 1; }

rm -f "$OUT"
qemu-img create -f qcow2 "$OUT" "$SIZE"

# Use KVM acceleration only if the device is writable to us.
ACCEL=""
[ -w /dev/kvm ] && ACCEL="-enable-kvm"

echo "Embedding ONIE into $OUT (this reboots-and-exits when done)..."
timeout 600 qemu-system-x86_64 $ACCEL -m 1024 -machine pc \
    -drive file="$OUT",if=virtio,format=qcow2,index=0,media=disk \
    -cdrom "$RECOVERY_ISO" -boot d -no-reboot \
    -nographic -serial mon:stdio 2>&1 | tee "$LOG" || true

echo "=== Embed finished. Disk info: ==="
qemu-img info "$OUT"
echo "=== Sanity: does the disk contain an ONIE GRUB/partition? ==="
qemu-img convert -f qcow2 -O raw "$OUT" /tmp/onie-check.raw 2>/dev/null || true
{ command -v file >/dev/null && file /tmp/onie-check.raw; } || true
{ sudo /sbin/parted -s /tmp/onie-check.raw print 2>/dev/null || \
  fdisk -l /tmp/onie-check.raw 2>/dev/null; } | head -20
rm -f /tmp/onie-check.raw
