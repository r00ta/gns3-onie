#!/bin/bash
# Runs INSIDE the Debian 10 build container (after a full build).
# Produces an "embed-default" recovery ISO: identical to the normal recovery
# ISO but with the GRUB menu defaulting to "ONIE: Embed ONIE" so that booting
# it installs ONIE to disk unattended (used to bake the appliance qcow2).
set -eux
ONIE_DIR="${ONIE_DIR:-/home/build/onie}"
MACHINE=kvm_x86_64
cd "$ONIE_DIR/build-config"
export PATH=/sbin:/usr/sbin:$PATH

IMAGES="$ONIE_DIR/build/images"
NORMAL_ISO="$IMAGES/onie-recovery-x86_64-${MACHINE}-r0.iso"
EMBED_ISO="$IMAGES/onie-recovery-x86_64-${MACHINE}-r0-embed.iso"

# Preserve the normal (rescue-default) ISO if present.
[ -f "$NORMAL_ISO" ] && cp -f "$NORMAL_ISO" "$IMAGES/onie-recovery-x86_64-${MACHINE}-r0-rescue.iso"

# Force just the recovery-iso step to rebuild with embed as the default entry.
find "$ONIE_DIR/build" -path '*stamp*' -name 'recovery-iso' -delete || true
make MACHINE=$MACHINE RECOVERY_DEFAULT_ENTRY=embed recovery-iso

cp -f "$NORMAL_ISO" "$EMBED_ISO"

# Restore the normal rescue-default ISO as the canonical recovery ISO.
[ -f "$IMAGES/onie-recovery-x86_64-${MACHINE}-r0-rescue.iso" ] && \
    cp -f "$IMAGES/onie-recovery-x86_64-${MACHINE}-r0-rescue.iso" "$NORMAL_ISO"

ls -la "$IMAGES"/onie-recovery-*.iso
