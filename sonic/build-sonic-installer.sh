#!/bin/bash
# Runs on the GNS3 host. Builds a SONiC ONIE installer (sonic-vs.bin) from a
# direct-boot sonic-vs disk image, using SONiC's own onie-mk-demo.sh +
# installer/install.sh packaging. A direct-boot image cannot be installed by
# ONIE directly; this repackages its payload (fs.squashfs, boot/, docker/,
# platform/) into the self-extracting ONIE installer that ONIE downloads over
# HTTP and writes to the appliance disk.
#
# Two ways to point it at the SONiC-OS partition of a sonic-vs disk image:
#   * set SONIC_IMG=/path/to/sonic-vs.img[.gz] and the script mounts it for you
#     (qemu-nbd, read-only) and unmounts on exit; or
#   * mount it yourself read-only at $IMG_MNT and leave SONIC_IMG unset
#     (see docs/provision-sonic.md for the manual qemu-nbd commands).
set -eux

WORK="${WORK:-$HOME/onie-build/sonic-pkg}"
REF="${REF:-$HOME/onie-build/sonic-ref}"          # install.sh, sharch_body.sh, default_platform.conf, onie-image.conf, onie-mk-demo.sh
IMG_MNT="${IMG_MNT:-/mnt/sonic}"                    # SONiC-OS partition mounted read-only

# --- optional: auto-mount a sonic-vs image instead of a pre-mounted IMG_MNT ---
SONIC_IMG="${SONIC_IMG:-}"
NBD="${NBD:-/dev/nbd0}"
SONIC_PART="${SONIC_PART:-3}"                       # SONiC-OS partition number
if [ -n "$SONIC_IMG" ]; then
    [ -f "$SONIC_IMG" ] || { echo "SONIC_IMG not found: $SONIC_IMG" >&2; exit 1; }
    RAW="$SONIC_IMG"; TMPRAW=""
    case "$SONIC_IMG" in
        *.gz) TMPRAW="$(mktemp --suffix=.img)"; echo "Decompressing $SONIC_IMG ..."
              zcat "$SONIC_IMG" > "$TMPRAW"; RAW="$TMPRAW";;
    esac
    sudo modprobe nbd max_part=16
    sudo qemu-nbd --disconnect "$NBD" >/dev/null 2>&1 || true
    sudo qemu-nbd --connect="$NBD" --read-only "$RAW"
    sudo mkdir -p "$IMG_MNT"
    for _i in $(seq 1 30); do [ -b "${NBD}p${SONIC_PART}" ] && break; sleep 1; done
    sudo mount -o ro "${NBD}p${SONIC_PART}" "$IMG_MNT"
    cleanup_mnt() {
        sudo umount "$IMG_MNT" 2>/dev/null || true
        sudo qemu-nbd --disconnect "$NBD" >/dev/null 2>&1 || true
        [ -n "$TMPRAW" ] && rm -f "$TMPRAW"
    }
    trap cleanup_mnt EXIT
fi

IMAGE_DIR_NAME="$(sudo bash -c "ls -d $IMG_MNT/image-* | xargs -n1 basename")"
IMAGE_VERSION="${IMAGE_VERSION:-${IMAGE_DIR_NAME#image-}}"
SRC="$IMG_MNT/$IMAGE_DIR_NAME"

ARCH=amd64
MACHINE=kvm_x86_64
PLATFORM=x86_64-kvm_x86_64-r0
PART_SIZE="${PART_SIZE:-32768}"                     # SONiC-OS partition size (MB); create_partition falls back to free space
OUT="${OUT:-$WORK/target/sonic-vs.bin}"

echo "IMAGE_VERSION=$IMAGE_VERSION  SRC=$SRC"

sudo rm -rf "$WORK"
mkdir -p "$WORK/installer" "$WORK/target"

# 1. installer/ payload-adjacent scripts (SONiC's own installer framework)
cp "$REF/install.sh" "$REF/sharch_body.sh" "$REF/default_platform.conf" "$WORK/installer/"
chmod +x "$WORK/installer/install.sh" "$WORK/installer/sharch_body.sh"
cp "$REF/onie-image.conf" "$WORK/"
cp "$REF/onie-mk-demo.sh" "$WORK/"
chmod +x "$WORK/onie-mk-demo.sh"

# platforms_asic: list the target platform so install.sh doesn't prompt for a
# mismatched-ASIC confirmation (which would hang the unattended install).
echo "$PLATFORM" > "$WORK/installer/platforms_asic"

# 2. platform.tar.gz  <- image-<ver>/platform/  (extracted by install.sh into image_dir/platform)
echo "Building platform.tar.gz ..."
sudo tar --numeric-owner -C "$SRC/platform" -czf "$WORK/platform.tar.gz" .

# 3. fs.zip (INSTALLER_PAYLOAD): fs.squashfs + boot/ + platform.tar.gz (stored, squashfs is already compressed)
echo "Building fs.zip ..."
sudo bash -c "cd '$SRC' && zip -0 -y -r '$WORK/fs.zip' fs.squashfs boot"
( cd "$WORK" && sudo zip -0 fs.zip platform.tar.gz )

# 4. dockerfs.tar.gz  <- image-<ver>/docker/  (shipped alongside payload; ~2GB, parallel gzip)
echo "Building dockerfs.tar.gz (large, using pigz) ..."
sudo bash -c "tar --numeric-owner -C '$SRC/docker' -cf - . | pigz -p $(nproc) > '$WORK/dockerfs.tar.gz'"

ls -la "$WORK"

# 5. Assemble the self-extracting ONIE installer.
#    Args: arch machine platform installer_dir platform_conf output demo_type image_version part_size payload
cd "$WORK"
./onie-mk-demo.sh "$ARCH" "$MACHINE" "$PLATFORM" \
    installer platform.conf "$OUT" OS "$IMAGE_VERSION" "$PART_SIZE" fs.zip

sudo chown "$USER:$USER" "$OUT"
echo "=== Built ONIE installer ==="
ls -la "$OUT"
