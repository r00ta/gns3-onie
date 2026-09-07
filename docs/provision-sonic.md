# Provisioning SONiC via ONIE

ONIE installs a NOS from a self-extracting `*.bin` installer. A **direct-boot**
`sonic-vs` disk image (a pre-installed qcow2) is not such an installer, so its
payload is repackaged into a genuine `sonic-vs.bin` ONIE installer using SONiC's
own packaging tools, then served through the same DHCP/HTTP pipeline as the demo
OS.

## Why reconstruction works

A SONiC ONIE installer is assembled by `onie-mk-demo.sh` from
`installer/install.sh` + `installer/sharch_body.sh` +
`installer/default_platform.conf` and a payload (`fs.zip`), plus a
separately-shipped `dockerfs.tar.gz`. All of those payload pieces already exist
inside an installed SONiC disk under `/host/image-<ver>/`:

| On-disk (SONiC-OS partition) | Repackaged into |
|------------------------------|-----------------|
| `image-<ver>/fs.squashfs` | `fs.zip` (stored) |
| `image-<ver>/boot/` | `fs.zip` (stored) |
| `image-<ver>/platform/` | `platform.tar.gz` inside `fs.zip` |
| `image-<ver>/docker/` | `dockerfs.tar.gz` (shipped alongside the payload) |

`sonic/build-sonic-installer.sh` mounts the image, rebuilds those artifacts, and
runs `onie-mk-demo.sh` to emit `sonic-vs.bin`. The upstream packaging scripts are
vendored in `sonic-ref/` (see its README for provenance).

## Procedure

```bash
# 1. Mount the SONiC-OS partition of the direct-boot image read-only
sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd0 --read-only "$SONIC_IMG"
sudo mkdir -p /mnt/sonic && sudo mount -o ro /dev/nbd0p3 /mnt/sonic

# 2. Build the ONIE installer from the payload
bash sonic/build-sonic-installer.sh        # -> ~/onie-build/sonic-pkg/target/sonic-vs.bin

# 3. Publish it on the provisioning HTTP server (replaces the demo installer)
bash sonic/push-sonic-installer.sh

# 4. Reboot the ONIE node to install SONiC
WATCH_SECS=600 bash gns3/test-provisioning.sh

# 5. Clean up the mount
sudo umount /mnt/sonic && sudo qemu-nbd --disconnect /dev/nbd0
```

## Requirements imposed by SONiC

* **Appliance disk ≥ 34 GB.** SONiC's installer requests a 32 GB SONiC-OS
  partition (`ONIE_IMAGE_PART_SIZE=32768`); the disk is baked at 40 GB
  (`APPLIANCE_DISK_SIZE`) so the partition fits with a clean GPT.
* **RAM ≥ 8 GB.** SONiC-vs runs ~40 containers; less RAM OOMs on first boot
  (`APPLIANCE_RAM=8192`).
* **Server VM disk ≥ 34 GB.** The ~2.5 GB installer must fit on the server VM's
  root filesystem; grow the cloud image (`qemu-img resize` + cloud-init
  `growpart`).
* **`install.sh` must be executable** inside the sharch payload — the build
  script `chmod +x`es `install.sh`/`sharch_body.sh` before packaging, otherwise
  ONIE fails with `Permission denied`.
* **`installer/platforms_asic`** lists `x86_64-kvm_x86_64-r0` so the installer
  does not stop for an interactive "different ASIC type" confirmation.

## Verified install markers

```
ONIE: Executing installer: http://172.31.0.1/onie-installer
Verifying image checksum ... OK.
Installing SONiC in ONIE
Creating new SONiC-OS partition /dev/vda3 ...
Booting `SONiC-OS-<version>'
sonic login:  ->  admin@sonic:~$   (show version: SONiC.<version>)
```

## Reverting to the demo OS

Re-publish the demo installer as `/srv/onie/onie-installer` on the server VM
(`provision/provision-server.sh`) and reboot the ONIE node.
