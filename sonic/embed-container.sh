#!/usr/bin/env bash
# Generator 3: embed a Docker container into a SONiC ONIE installer.
#
# Runs on the GNS3 host. Takes a finished SONiC installer (.bin, produced by
# sonic/build-sonic-installer.sh) plus a Docker build context, and emits a new
# installer that runs the container automatically on every boot of a freshly
# provisioned switch. Installer in -> installer out; the input is left untouched.
#
# It does NOT touch the ~2 GB dockerfs.tar.gz shipped inside the installer: the
# container image is added as a saved tarball inside the root filesystem
# (fs.squashfs) and loaded at boot by a generated systemd unit
# ("<name>.service", After=docker.service).
#
# Usage:
#   sonic/embed-container.sh [build-context-dir]
# Configurable via environment (defaults in brackets):
#   CONTEXT     docker build context      [sonic/embed-container/hello-world]
#   IMAGE       image name:tag            [hello-sonic:latest]
#   NAME        container + service name  [hello-sonic]
#   INSTALLER   target installer to embed [$HOME/onie-build/sonic-pkg/target/sonic-vs.bin]
#   OUT         output installer path     [<INSTALLER without .bin>-<NAME>.bin]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

CONTEXT="${1:-${CONTEXT:-$HERE/embed-container/hello-world}}"
IMAGE="${IMAGE:-hello-sonic:latest}"
NAME="${NAME:-hello-sonic}"
INSTALLER="${INSTALLER:-$HOME/onie-build/sonic-pkg/target/sonic-vs.bin}"
OUT="${OUT:-${INSTALLER%.bin}-$NAME.bin}"
SHARCH="${SHARCH:-$REPO/sonic-ref/sharch_body.sh}"

# --- sanity checks -----------------------------------------------------------
for t in docker unsquashfs mksquashfs zip unzip sha1sum tar; do
    command -v "$t" >/dev/null || { echo "Missing tool: $t" >&2; exit 1; }
done
[ -d "$CONTEXT" ]   || { echo "No build context: $CONTEXT" >&2; exit 1; }
[ -f "$INSTALLER" ] || { echo "No installer: $INSTALLER (run build-sonic-installer.sh first)" >&2; exit 1; }
[ -f "$SHARCH" ]    || { echo "Missing sharch template: $SHARCH" >&2; exit 1; }

DOCKER="docker"; docker info >/dev/null 2>&1 || DOCKER="sudo docker"
OUT="$(mkdir -p "$(dirname "$OUT")" && cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

BUILD="$(mktemp -d)"
cleanup() { sudo rm -rf "$BUILD"; }
trap cleanup EXIT

# --- 1. build the container and save it (legacy format for older dockerd) ----
echo "==> Building image $IMAGE from $CONTEXT"
DOCKER_BUILDKIT=0 $DOCKER build -t "$IMAGE" "$CONTEXT"
echo "==> Saving image to tarball"
$DOCKER save "$IMAGE" -o "$BUILD/image.tar"
sudo chown "$USER":"$USER" "$BUILD/image.tar"

# --- 2. extract the installer payload ----------------------------------------
echo "==> Extracting installer payload from $INSTALLER"
sed -e '1,/^exit_marker$/d' "$INSTALLER" | tar -x -C "$BUILD"
[ -f "$BUILD/installer/fs.zip" ] || { echo "installer/fs.zip not found in payload" >&2; exit 1; }

# --- 3. extract the root filesystem from the payload -------------------------
echo "==> Extracting fs.squashfs from installer/fs.zip"
( cd "$BUILD" && unzip -o installer/fs.zip fs.squashfs >/dev/null )
COMP="$(unsquashfs -s "$BUILD/fs.squashfs" | awk '/Compression/{print $2; exit}')"
COMP="${COMP:-zstd}"
echo "==> Unpacking rootfs (compressor: $COMP)"
sudo unsquashfs -d "$BUILD/squashfs-root" "$BUILD/fs.squashfs" >/dev/null

# --- 4. inject the image, a start script and an enabled systemd unit ---------
R="$BUILD/squashfs-root"
DEST="/usr/local/$NAME"
echo "==> Injecting $DEST + $NAME.service"
sudo mkdir -p "$R$DEST"
sudo cp "$BUILD/image.tar" "$R$DEST/$NAME.tar"

sudo tee "$R$DEST/start.sh" >/dev/null <<EOF
#!/bin/bash
# Loads and starts the embedded container. Idempotent across boots.
set -e
IMG=$IMAGE
TAR=$DEST/$NAME.tar
/usr/bin/docker image inspect "\$IMG" >/dev/null 2>&1 || /usr/bin/docker load -i "\$TAR"
/usr/bin/docker rm -f $NAME >/dev/null 2>&1 || true
exec /usr/bin/docker run -d --name $NAME --restart unless-stopped "\$IMG"
EOF
sudo chmod +x "$R$DEST/start.sh"

sudo tee "$R/etc/systemd/system/$NAME.service" >/dev/null <<EOF
[Unit]
Description=Embedded container: $NAME
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$DEST/start.sh
ExecStop=/usr/bin/docker rm -f $NAME
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF
sudo ln -sf "/etc/systemd/system/$NAME.service" \
    "$R/etc/systemd/system/multi-user.target.wants/$NAME.service"

# --- 5. repack the root filesystem back into the payload ---------------------
echo "==> Repacking rootfs (compressor: $COMP)"
sudo mksquashfs "$R" "$BUILD/fs.squashfs" -comp "$COMP" -noappend -no-progress >/dev/null
sudo chown "$USER":"$USER" "$BUILD/fs.squashfs"
( cd "$BUILD" && zip -0 installer/fs.zip fs.squashfs >/dev/null )

# --- 6. reassemble the self-extracting installer -----------------------------
echo "==> Assembling installer $OUT"
( cd "$BUILD" && tar -cf sharch.tar installer )
size="$(stat -c%s "$BUILD/sharch.tar")"
sha1="$(sha1sum "$BUILD/sharch.tar" | awk '{print $1}')"
sed -e "s/%%PAYLOAD_IMAGE_SIZE%%/$size/" \
    -e "s/%%IMAGE_SHA1%%/$sha1/" "$SHARCH" > "$OUT"
cat "$BUILD/sharch.tar" >> "$OUT"
chmod +x "$OUT"

echo
echo "=== Embedded installer ready ==="
ls -l "$OUT"
echo "Publish it with:  SERVER_IP=<vm-ip> BIN=$OUT bash sonic/push-sonic-installer.sh"
