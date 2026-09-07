#!/bin/bash
# Quick boot test of the baked ONIE appliance qcow2 under legacy BIOS (SeaBIOS)
# with a virtio disk (== GNS3 "virtio" disk interface). Captures serial output
# so we can confirm ONIE boots from disk and finds /dev/vda.
set -eux
OUT="${OUT:-$HOME/onie-build/onie-kvm_x86_64.qcow2}"
LOG="${LOG:-$HOME/onie-build/bootcheck.log}"
ACCEL=""
[ -w /dev/kvm ] && ACCEL="-enable-kvm"
# Work on a copy so the test boot doesn't mutate the golden image.
cp -f "$OUT" /tmp/onie-boot-test.qcow2
timeout 90 qemu-system-x86_64 $ACCEL -m 1024 -machine pc \
    -drive file=/tmp/onie-boot-test.qcow2,if=virtio,format=qcow2 \
    -boot c -no-reboot -nographic -serial mon:stdio 2>&1 | tee "$LOG" || true
rm -f /tmp/onie-boot-test.qcow2
echo "=== markers ==="
grep -aE "ONIE:|/dev/vda|install block device|Install OS|discover|GRUB" "$LOG" | head -30
