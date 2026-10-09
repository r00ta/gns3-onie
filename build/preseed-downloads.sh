#!/usr/bin/env bash
# Pre-seed ONIE's download cache so a build survives the dead OCP mirror
# (mirror.opencompute.org, removed from DNS) and several stale upstream
# fallback URLs it exposes.
#
# Two problem classes, both fixed the same way -- stage a sha1-verified copy
# into $DOWNLOADDIR, where fetch-package then logs "Using cached ..." and skips
# the network:
#
#   1. crosstool-NG companion tools (autoconf, gcc, binutils, ...). xtools.make
#      fetches these with ONLY $(CROSSTOOL_ONIE_MIRROR) -- no upstream fallback
#      -- so a mirror outage aborts the toolchain build outright.
#
#   2. ONIE's own packages whose committed upstream fallback is now broken:
#      popt (rpm5.org 429), util-linux (kernel.org path moved), lvm2
#      (fedorahosted retired), efibootmgr/efivar (release URL template 404s),
#      dosfstools (host gone), dmidecode/parted/grub (ftp/host unreachable).
#
# Every file is checked against the sha1 ONIE commits under upstream/, so a
# wrong, truncated, or HTML-error-page "download" is rejected.
#
# One package (mtd-utils) is a cgit git snapshot with no surviving byte-identical
# copy; it is rebuilt deterministically from its pinned commit and its sha1 is
# repinned -- see seed_mtdutils below.
#
# Usage:
#   ONIE_DIR=~/onie-build/onie bash build/preseed-downloads.sh
#
# Env:
#   ONIE_DIR   path to the ONIE source tree (default: ~/onie-build/onie)
#   GCC_VERSION  toolchain gcc version to seed for (default: 8.3.0, the
#                kvm_x86_64 default). Only 8.3.0 is wired up here.
set -euo pipefail

ONIE_DIR="${ONIE_DIR:-$HOME/onie-build/onie}"
GCC_VERSION="${GCC_VERSION:-8.3.0}"

DOWNLOADDIR="$ONIE_DIR/build/download"
UPSTREAMDIR="$ONIE_DIR/upstream"

[ -d "$ONIE_DIR" ] || { echo "ERROR: ONIE source tree not found: $ONIE_DIR" >&2; exit 1; }
[ -d "$UPSTREAMDIR" ] || { echo "ERROR: ONIE upstream/ dir not found: $UPSTREAMDIR" >&2; exit 1; }
mkdir -p "$DOWNLOADDIR"

# <tarball> <url1> [url2 ...]
# The sha1 committed in $UPSTREAMDIR/<tarball>.sha1 is the source of truth;
# URLs are candidates tried in order until one verifies.
COMPONENTS=(
"autoconf-2.69.tar.xz https://mirrors.kernel.org/gnu/autoconf/autoconf-2.69.tar.xz https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz"
"automake-1.15.1.tar.xz https://mirrors.kernel.org/gnu/automake/automake-1.15.1.tar.xz https://ftp.gnu.org/gnu/automake/automake-1.15.1.tar.xz"
"duma_2_5_15.tar.gz https://downloads.sourceforge.net/project/duma/duma/2.5.15/duma_2_5_15.tar.gz https://phoenixnap.dl.sourceforge.net/project/duma/duma/2.5.15/duma_2_5_15.tar.gz"
"gettext-0.19.8.1.tar.xz https://mirrors.kernel.org/gnu/gettext/gettext-0.19.8.1.tar.xz https://ftp.gnu.org/gnu/gettext/gettext-0.19.8.1.tar.xz"
"libelf-0.8.13.tar.gz https://fossies.org/linux/misc/old/libelf-0.8.13.tar.gz https://distfiles.gentoo.org/distfiles/libelf-0.8.13.tar.gz"
"libiconv-1.15.tar.gz https://mirrors.kernel.org/gnu/libiconv/libiconv-1.15.tar.gz https://ftp.gnu.org/gnu/libiconv/libiconv-1.15.tar.gz"
"libtool-2.4.6.tar.xz https://mirrors.kernel.org/gnu/libtool/libtool-2.4.6.tar.xz https://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.xz"
"ltrace_0.7.3.orig.tar.bz2 http://deb.debian.org/debian/pool/main/l/ltrace/ltrace_0.7.3.orig.tar.bz2 https://snapshot.debian.org/archive/debian/20160101T034014Z/pool/main/l/ltrace/ltrace_0.7.3.orig.tar.bz2"
"m4-1.4.18.tar.xz https://mirrors.kernel.org/gnu/m4/m4-1.4.18.tar.xz https://ftp.gnu.org/gnu/m4/m4-1.4.18.tar.xz"
"make-4.2.1.tar.bz2 https://mirrors.kernel.org/gnu/make/make-4.2.1.tar.bz2 https://ftp.gnu.org/gnu/make/make-4.2.1.tar.bz2"
"ncurses-6.0.tar.gz https://mirrors.kernel.org/gnu/ncurses/ncurses-6.0.tar.gz https://ftp.gnu.org/gnu/ncurses/ncurses-6.0.tar.gz"
)

if [ "$GCC_VERSION" = "8.3.0" ]; then
    COMPONENTS+=(
"binutils-2.32.tar.bz2 https://mirrors.kernel.org/gnu/binutils/binutils-2.32.tar.bz2 https://ftp.gnu.org/gnu/binutils/binutils-2.32.tar.bz2"
"expat-2.2.6.tar.bz2 https://github.com/libexpat/libexpat/releases/download/R_2_2_6/expat-2.2.6.tar.bz2 https://downloads.sourceforge.net/project/expat/expat/2.2.6/expat-2.2.6.tar.bz2"
"gcc-8.3.0.tar.xz https://mirrors.kernel.org/gnu/gcc/gcc-8.3.0/gcc-8.3.0.tar.xz https://ftp.gnu.org/gnu/gcc/gcc-8.3.0/gcc-8.3.0.tar.xz"
"gdb-7.12.1.tar.xz https://mirrors.kernel.org/gnu/gdb/gdb-7.12.1.tar.xz https://ftp.gnu.org/gnu/gdb/gdb-7.12.1.tar.xz"
"gmp-6.1.2.tar.xz https://mirrors.kernel.org/gnu/gmp/gmp-6.1.2.tar.xz https://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz https://gmplib.org/download/gmp/gmp-6.1.2.tar.xz"
"isl-0.20.tar.xz https://libisl.sourceforge.io/isl-0.20.tar.xz https://sourceware.org/pub/gcc/infrastructure/isl-0.20.tar.bz2"
"mpc-1.1.0.tar.gz https://mirrors.kernel.org/gnu/mpc/mpc-1.1.0.tar.gz https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz"
"mpfr-4.1.0.tar.xz https://mirrors.kernel.org/gnu/mpfr/mpfr-4.1.0.tar.xz https://ftp.gnu.org/gnu/mpfr/mpfr-4.1.0.tar.xz https://www.mpfr.org/mpfr-4.1.0/mpfr-4.1.0.tar.xz"
"strace-4.26.tar.xz https://github.com/strace/strace/releases/download/v4.26/strace-4.26.tar.xz https://strace.io/files/4.26/strace-4.26.tar.xz"
"zlib-1.2.11.tar.xz https://downloads.sourceforge.net/project/libpng/zlib/1.2.11/zlib-1.2.11.tar.xz https://sourceforge.net/projects/libpng/files/zlib/1.2.11/zlib-1.2.11.tar.xz/download"
    )
else
    echo "ERROR: GCC_VERSION=$GCC_VERSION not supported by this seed list (only 8.3.0)." >&2
    exit 1
fi

# ONIE's own packages whose committed upstream fallback URL is dead/stale.
# Sources below were each verified to match the sha1 under upstream/.
COMPONENTS+=(
"popt-1.16.tar.gz https://sources.buildroot.net/popt/popt-1.16.tar.gz"
"util-linux-2.37.2.tar.xz https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.37/util-linux-2.37.2.tar.xz https://mirrors.kernel.org/pub/linux/utils/util-linux/v2.37/util-linux-2.37.2.tar.xz"
"lvm2-2_02_105.tar.xz https://web.archive.org/web/2id_/http://mirror.opencompute.org/onie/lvm2-2_02_105.tar.xz"
"efibootmgr-16.tar.bz2 https://github.com/rhboot/efibootmgr/releases/download/16/efibootmgr-16.tar.bz2"
"efivar-37.tar.bz2 https://github.com/rhboot/efivar/releases/download/37/efivar-37.tar.bz2"
"dosfstools-3.0.26.tar.xz https://web.archive.org/web/2id_/http://mirror.opencompute.org/onie/dosfstools-3.0.26.tar.xz"
"dmidecode-3.1.tar.xz https://web.archive.org/web/2id_/http://download.savannah.gnu.org/releases/dmidecode/dmidecode-3.1.tar.xz"
"parted-3.1.tar.xz https://mirrors.kernel.org/gnu/parted/parted-3.1.tar.xz https://ftp.gnu.org/gnu/parted/parted-3.1.tar.xz"
"grub-2.04.tar.xz https://mirrors.kernel.org/gnu/grub/grub-2.04.tar.xz https://ftp.gnu.org/gnu/grub/grub-2.04.tar.xz"
)

# mtd-utils is fetched by ONIE as a cgit git snapshot. The OCP mirror held a
# frozen copy; live cgit regenerates non-deterministically and no byte-identical
# copy survives, so ONIE's pinned sha1 can't be reproduced from any live source.
# The pinned commit is still reachable on GitHub though, and because we fetch by
# commit hash (content-addressed) and repack deterministically, the result is
# reproducible on every machine. We rebuild the tarball and repin ONIE's sha1 to
# match -- the build only needs the correct source tree under mtd-utils-e4c8885/.
MTDUTILS_COMMIT=e4c8885bddac201ba0ef88560d6444f39e1ff870
MTDUTILS_TARBALL="$MTDUTILS_COMMIT.tar.gz"
MTDUTILS_TOPDIR=mtd-utils-e4c8885
MTDUTILS_SRC_URLS=(
"https://codeload.github.com/lgirdk/mtd-utils/tar.gz/$MTDUTILS_COMMIT"
"http://git.infradead.org/mtd-utils.git/snapshot/$MTDUTILS_COMMIT.tar.gz"
)

verify_sha1() {
    # $1 = file path, $2 = expected tarball name (for the .sha1 under upstream/)
    local file="$1" name="$2" sha1file="$UPSTREAMDIR/$2.sha1"
    [ -f "$sha1file" ] || { echo "    no sha1 reference ($sha1file); cannot verify"; return 2; }
    local expected
    expected="$(awk '{print $1}' "$sha1file")"
    local actual
    actual="$(sha1sum "$file" | awk '{print $1}')"
    [ "$expected" = "$actual" ]
}

# Rebuild the mtd-utils snapshot from its pinned commit and repin ONIE's sha1.
seed_mtdutils() {
    local dest="$DOWNLOADDIR/$MTDUTILS_TARBALL"
    if [ -f "$dest" ] && verify_sha1 "$dest" "$MTDUTILS_TARBALL"; then
        echo "== $MTDUTILS_TARBALL: already staged and verified, skipping"
        skipped=$((skipped + 1)); return 0
    fi
    local work; work="$(mktemp -d)"
    local got=no
    for url in "${MTDUTILS_SRC_URLS[@]}"; do
        echo "== $MTDUTILS_TARBALL: rebuilding from commit tree $url"
        if ! wget --no-verbose --tries=2 --timeout=20 -O "$work/src.tar.gz" "$url"; then
            echo "   download failed, trying next"; continue
        fi
        if ! tar -xzf "$work/src.tar.gz" -C "$work" 2>/dev/null; then
            echo "   not a valid tarball (rate-limit page?), trying next"; rm -f "$work/src.tar.gz"; continue
        fi
        local top; top="$(cd "$work" && ls -d mtd-utils-* 2>/dev/null | head -1)"
        if [ -z "$top" ] || [ ! -f "$work/$top/Makefile" ]; then
            echo "   unexpected archive layout, trying next"; rm -rf "$work/mtd-utils-"* "$work/src.tar.gz"; continue
        fi
        rm -rf "$work/$MTDUTILS_TOPDIR"; mv "$work/$top" "$work/$MTDUTILS_TOPDIR"
        # Deterministic repack so the sha1 is reproducible across machines/runs.
        ( cd "$work" && tar --sort=name --mtime='@0' --owner=0 --group=0 \
            --numeric-owner -cf - "$MTDUTILS_TOPDIR" | gzip -n > "$work/out.tar.gz" )
        local sha; sha="$(sha1sum "$work/out.tar.gz" | awk '{print $1}')"
        printf '%s  %s\n' "$sha" "$MTDUTILS_TARBALL" > "$UPSTREAMDIR/$MTDUTILS_TARBALL.sha1"
        mv -f "$work/out.tar.gz" "$dest"
        echo "   OK -> $dest (sha1 repinned to $sha)"
        got=yes; break
    done
    rm -rf "$work"
    if [ "$got" = yes ]; then
        ok=$((ok + 1))
    else
        echo "   !! FAILED to rebuild $MTDUTILS_TARBALL"
        failed=$((failed + 1)); failed_names+=("$MTDUTILS_TARBALL")
    fi
}

ok=0 skipped=0 failed=0
failed_names=()

for entry in "${COMPONENTS[@]}"; do
    # shellcheck disable=SC2206
    parts=($entry)
    name="${parts[0]}"
    urls=("${parts[@]:1}")
    dest="$DOWNLOADDIR/$name"

    if [ -f "$dest" ] && verify_sha1 "$dest" "$name"; then
        echo "== $name: already staged and verified, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    got=no
    for url in "${urls[@]}"; do
        echo "== $name: fetching $url"
        tmp="$(mktemp "$DOWNLOADDIR/.$name.XXXXXX")"
        if wget --no-verbose --tries=2 --timeout=20 -O "$tmp" "$url"; then
            if verify_sha1 "$tmp" "$name"; then
                mv -f "$tmp" "$dest"
                echo "   OK -> $dest"
                got=yes
                break
            else
                echo "   sha1 mismatch from $url, trying next"
            fi
        else
            echo "   download failed from $url, trying next"
        fi
        rm -f "$tmp"
    done

    if [ "$got" = yes ]; then
        ok=$((ok + 1))
    else
        echo "   !! FAILED to obtain a verified $name"
        failed=$((failed + 1))
        failed_names+=("$name")
    fi
done

# mtd-utils: rebuilt from its pinned commit (no surviving frozen copy).
seed_mtdutils

echo
echo "=== preseed summary: $ok fetched, $skipped already present, $failed failed ==="
if [ "$failed" -gt 0 ]; then
    printf '   missing: %s\n' "${failed_names[*]}"
    echo "   place verified tarball(s) in: $DOWNLOADDIR" >&2
    exit 1
fi
