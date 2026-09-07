# Building ONIE

The ONIE `kvm_x86_64` emulation target is built in a reproducible Debian 10
container so the host toolchain is irrelevant.

> These are the individual steps behind **Generator 1**. To run the whole
> appliance build (compile → embed ISO → bake disk → render `.gns3a`) in one
> command, use [`build/make-onie-appliance.sh`](../build/make-onie-appliance.sh).

## Scripts

| Script | Runs on | Purpose |
|--------|---------|---------|
| `build/Dockerfile` | host | Debian 10 build environment (repoints apt at `archive.debian.org`). |
| `build/run-build.sh` | host | Builds the image and compiles ONIE against `ONIE_SRC`. |
| `build/build-onie.sh` | container | `signing-keys → shim-self-sign → all demo recovery-iso`. |
| `build/run-embed-iso.sh` | host | Runs `build-embed-iso.sh` in the container. |
| `build/build-embed-iso.sh` | container | Rebuilds the recovery ISO defaulting to **Embed ONIE**. |
| `build/boot-check.sh` | host | Sanity boot of the baked qcow2. |

## Procedure

```bash
git clone https://github.com/opencomputeproject/onie ~/onie-build/onie
cd ~/onie-build/build
bash run-build.sh        # first run ~30-40 min (toolchain + demo NOS + recovery ISO)
bash run-embed-iso.sh    # produces onie-recovery-...-embed.iso
```

Build products land in `$ONIE_SRC/build/images/`, including:

* `onie-recovery-x86_64-kvm_x86_64-r0.iso` — normal recovery ISO;
* `onie-recovery-x86_64-kvm_x86_64-r0-embed.iso` — embed-default ISO used to bake
  the appliance disk;
* `demo-installer-x86_64-kvm_x86_64-r0.bin` — ONIE demo NOS installer.

## Baking the appliance disk

`appliance/make-appliance-disk.sh` boots the embed ISO under SeaBIOS on a blank
virtio qcow2. ONIE detects BIOS firmware and installs a legacy `i386-pc` GRUB to
the disk, then reboots — `-no-reboot` makes QEMU exit, leaving a bootable image:

```bash
bash appliance/make-appliance-disk.sh    # -> ~/onie-build/onie-kvm_x86_64.qcow2
```

Key variables (from `config.env`): `APPLIANCE_DISK_SIZE` (default 40 GB; must be
≥ 34 GB for SONiC), `ONIE_MACHINE`, `ONIE_SRC`.

## Resuming a build

`build-onie.sh` cleans the build tree by default so a stale, half-built stamp
cannot make `make` skip a step. Set `SKIP_CLEAN=1` to resume an existing tree
after a late-stage fix (keeps existing signing keys so the shim is not re-signed):

```bash
SKIP_CLEAN=1 bash run-build.sh
```
