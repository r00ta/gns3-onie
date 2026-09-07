# Architecture and design notes

## Topology

```
   NAT ── eth0(server)                 internet (apt + downloads)
          eth1(server) ── adapter0(onie-switch)   management LAN 172.31.0.0/24
                          adapter1(onie-switch) ── PC1
                          adapter2(onie-switch) ── PC2
```

* **server** — a Linux VM turned into the provisioning server: static
  `172.31.0.1/24` on its LAN NIC, `dnsmasq` DHCP, and a small HTTP server that
  offers the NOS installer.
* **onie-switch** — the ONIE appliance. It boots ONIE in "OS install" mode,
  leases an address, and probes the DHCP server on port 80 for `onie-installer*`
  (the ONIE discovery "waterfall"); DHCP option 114 also points straight at the
  image. After a NOS is installed it boots that NOS from disk.
* **PC1 / PC2** — VPCS hosts used to validate Layer-2 switching.

## Port map (1 management + 8 data)

The GNS3 node has 9 NICs (`APPLIANCE_ADAPTERS=9`). SONiC-vs maps guest NICs to
front-panel ports in order; the HwSKU is `Force10-S6000` (32 ports internally,
4-lane spacing), so only the first 8 are backed by a NIC and the port names step
by four:

| GNS3 adapter | Guest NIC | SONiC port    | Role |
|--------------|-----------|---------------|------|
| 0 | eth0 | `Management0` | management / ONIE provisioning |
| 1 | eth1 | `Ethernet0`   | data port 1 |
| 2 | eth2 | `Ethernet4`   | data port 2 |
| 3 | eth3 | `Ethernet8`   | data port 3 |
| 4 | eth4 | `Ethernet12`  | data port 4 |
| 5 | eth5 | `Ethernet16`  | data port 5 |
| 6 | eth6 | `Ethernet20`  | data port 6 |
| 7 | eth7 | `Ethernet24`  | data port 7 |
| 8 | eth8 | `Ethernet28`  | data port 8 |

Ports without a connected link stay operationally down; confirm the mapping on a
live node with `show interfaces status`.

## How ONIE finds the installer

`dnsmasq` advertises itself as the DHCP server (option 54), so ONIE probes
`http://<LAN_IP>/onie-installer` automatically. The provisioning setup also:

* serves the installer under the machine-specific waterfall names
  (`onie-installer-x86_64`, `-x86_64-kvm_x86_64`, …), and
* sets DHCP option 114 (`default-url`) to the exact image URL.

## Design decisions

* **Debian 10 build host.** The ONIE `kvm_x86_64` target requires Debian 10
  "buster". Buster is EOL, so the build container uses `archive.debian.org` with
  the release-date check disabled. The build user's UID/GID match the host user
  so the bind-mounted source tree stays writable.
* **virtio disk.** ONIE's `kvm_x86_64` `install_device_platform` looks for
  `/dev/vda` (virtio) or `/dev/sda` (SATA); a legacy IDE disk is not detected, so
  both the baking step and the GNS3 template use virtio.
* **Legacy BIOS.** GNS3's default QEMU node boots via SeaBIOS. Baking the disk
  under SeaBIOS makes ONIE install a legacy `i386-pc` GRUB, so the image boots
  directly in GNS3 with no UEFI/OVMF firmware — even though ONIE itself is built
  with Secure Boot enabled.
* **Secure Boot ⇒ password login.** With Secure Boot on, the ONIE console uses
  `/bin/login` and a machine password file, hence `root`/`onie`. Building with
  `SECURE_BOOT_EXT=no` would give a password-less root shell instead.
* **9 NICs from the start.** The template ships with 1 management + 8 data ports.
  During provisioning only the management port is wired; the extra data ports are
  harmless and are wired to test hosts afterwards, so the appliance is a switch
  out of the box.
