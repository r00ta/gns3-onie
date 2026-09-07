#!/bin/bash
# Runs INSIDE the Debian 10 build container.
# Builds ONIE for the kvm_x86_64 emulation target: recovery ISO + demo NOS installer.
set -eux

ONIE_DIR="${ONIE_DIR:-/home/build/onie}"
MACHINE=kvm_x86_64
JOBS="$(nproc)"

cd "$ONIE_DIR/build-config"
export PATH=/sbin:/usr/sbin:$PATH

# Start from a clean build tree so a previous partial/failed build can't leave
# stale stamps (e.g. a half-built toolchain) that make would wrongly skip.
# Preserve build/download so upstream tarballs aren't re-fetched.
# Set SKIP_CLEAN=1 to resume an existing tree (e.g. after a late-stage fix).
if [ -z "${SKIP_CLEAN:-}" ] && [ -d "$ONIE_DIR/build" ]; then
    find "$ONIE_DIR/build" -mindepth 1 -maxdepth 1 ! -name download -exec rm -rf {} +
fi

# Make key generation idempotent: a prior failed run may leave a partial keys
# dir without the completion marker, which makes the target refuse to re-run.
# On a resume (SKIP_CLEAN=1) keep existing keys so the shim isn't re-signed.
if [ -z "${SKIP_CLEAN:-}" ]; then
    rm -rf "$ONIE_DIR/encryption/machines/$MACHINE"
fi

# 1. Generate the cryptographic signing keys (Secure Boot is on by default for KVM).
make MACHINE=$MACHINE signing-keys-generate

# 2. Build a self-signed shim EFI bootloader (required by the KVM target build).
make MACHINE=$MACHINE -j"$JOBS" shim-self-sign

# 3. Build ONIE itself, the demo NOS installer, and the recovery ISO.
make MACHINE=$MACHINE -j"$JOBS" all demo recovery-iso

echo "=== Build products ==="
ls -la "$ONIE_DIR/build/images/"
