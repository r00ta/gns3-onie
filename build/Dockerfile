# ONIE build environment for the kvm_x86_64 emulation target.
# kvm_x86_64 (master branch) requires a Debian 10 "buster" build host.
# Buster has reached EOL and moved to archive.debian.org, so we repoint apt.
FROM debian:10

# Point apt at the Debian archive (buster is EOL) and relax the release date check.
RUN set -eux; \
    printf '%s\n' \
      'deb http://archive.debian.org/debian buster main contrib non-free' \
      'deb http://archive.debian.org/debian buster-updates main contrib non-free' \
      'deb http://archive.debian.org/debian-security buster/updates main contrib non-free' \
      > /etc/apt/sources.list; \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid; \
    echo 'APT::Get::AllowUnauthenticated "true";' >> /etc/apt/apt.conf.d/99no-check-valid

# ONIE build host packages (from build-config/Makefile DEBIAN_BUILD_HOST_PACKAGES)
# plus a few tools used by the build (qemu-utils for qcow2 handling is added on host).
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential stgit u-boot-tools util-linux \
    gperf device-tree-compiler python-all-dev xorriso \
    autoconf automake bison flex texinfo libtool libtool-bin \
    gawk libncurses5 libncurses5-dev bc \
    dosfstools mtools pkg-config git wget help2man libexpat1 \
    libexpat1-dev fakeroot python-sphinx rst2pdf \
    libefivar-dev libnss3-tools libnss3-dev libpopt-dev \
    libssl-dev sbsigntool uuid-runtime uuid-dev cpio \
    bsdmainutils unzip curl sudo ca-certificates rsync file \
    gnupg2 gnupg-agent efitools tree locales \
    python3-distutils python3-dev gettext autopoint libelf-dev \
    && rm -rf /var/lib/apt/lists/*

# uClibc-ng's locale table generator requires a UTF-8 locale on the build host.
RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en

# ONIE refuses to build as root; create an unprivileged build user with sudo.
# UID/GID are configurable so they can match the host user owning the bind mount.
ARG BUILD_UID=1001
ARG BUILD_GID=1001
RUN groupadd -g "$BUILD_GID" build && \
    useradd -m -s /bin/bash -u "$BUILD_UID" -g "$BUILD_GID" build && \
    adduser build sudo && \
    echo 'build ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/build && \
    echo 'export PATH=/sbin:/usr/sbin:$PATH' >> /home/build/.bashrc

USER build
WORKDIR /home/build
# Patch steps use git am / stgit, which require a configured identity.
RUN git config --global user.email "build@onie.local" && \
    git config --global user.name "onie build" && \
    git config --global init.defaultBranch master
CMD ["/bin/bash", "--login"]
