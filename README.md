# ONIE + SONiC switch appliance for GNS3

Build an [ONIE](https://opencomputeproject.github.io/onie/) (Open Network Install
Environment) virtual appliance from source, import it into
[GNS3](https://www.gns3.com/), provision it over the network with a network
operating system, and run it as a Layer-2 switch. The repository automates the
whole pipeline end to end:

1. **Build ONIE** for the `kvm_x86_64` emulation target in a reproducible
   container.
2. **Bake a GNS3-ready appliance disk** (legacy-BIOS bootable qcow2).
3. **Import the appliance** into GNS3 as a template and build a topology with a
   provisioning server.
4. **Provision a NOS** — the ONIE demo OS for a smoke test, or **SONiC** for a
   real switch — via ONIE's DHCP/HTTP installer discovery.
5. **Validate switching** — configure VLANs across the SONiC data ports and
   verify connectivity and isolation between two test hosts.

The appliance exposes **1 management port + 8 data ports**.

```
                 ┌───────┐
   internet ─────┤  NAT  │
                 └───┬───┘
                     │ eth0
                 ┌───┴────────┐  eth1 (172.31.0.1/24, DHCP + HTTP)
                 │   server   ├────────────────┐
                 │ (Ubuntu VM)│                │ management (adapter 0)
                 └────────────┘          ┌─────┴──────┐
                                         │ onie-switch │  ── data ports 1..8
                                         │  (SONiC)    │      (Ethernet0..28)
                                         └──┬───────┬──┘
                                     adapter1│       │adapter2
                                        ┌────┴─┐  ┌──┴───┐
                                        │ PC1  │  │ PC2  │
                                        └──────┘  └──────┘
```

See [`docs/architecture.md`](docs/architecture.md) for the port map and design
decisions.

## Repository layout

| Path | Runs on | Purpose |
|------|---------|---------|
| `config.env.example` | – | Template for all tunables; copy to `config.env`. |
| `lib.sh`, `gns3/gns3lib.py` | GNS3 host | Shared config loader + GNS3 API helpers. |
| `build/` | GNS3 host + container | Build ONIE and the embed recovery ISO. |
| `appliance/make-appliance-disk.sh` | GNS3 host | Bake the appliance qcow2 from the embed ISO. |
| `gns3/deploy-appliance.sh`, `setup-gns3.py` | GNS3 host | Publish the image, register the template, build the base topology. |
| `provision/` | GNS3 host + server VM | Turn the server VM into a DHCP + HTTP provisioning server. |
| `sonic/build-sonic-installer.sh`, `push-sonic-installer.sh` | GNS3 host | Reconstruct and publish a SONiC ONIE installer. |
| `gns3/setup-switch-test.py`, `sonic/test-vlan.py` | GNS3 host | Wire two test hosts and run the VLAN validation. |
| `gns3/test-provisioning.sh`, `watch-console.py` | GNS3 host | (Re)boot the ONIE node and capture its console. |
| `sonic-ref/` | – | Vendored upstream ONIE/SONiC packaging scripts (see its README). |
| `docs/` | – | Architecture, SONiC provisioning, and switch validation references. |

## Prerequisites

* A **Linux host running GNS3 server 2.2.x** with KVM enabled, plus `docker`,
  `qemu-utils`, `qemu-system-x86`, `sshpass` and `git`. All build and deploy
  scripts run on this host.
* The GNS3 project must contain a **Linux server VM** (an Ubuntu 22.04/24.04
  cloud image works well) used as the provisioning server:
  * name it to match `GNS3_SERVER_NAME` (default `server`);
  * reachable over the GNS3 NAT network by SSH with `SERVER_SSH_USER` /
    `SERVER_SSH_PASS`;
  * root filesystem large enough to hold the NOS installer — the SONiC installer
    is ~2.5 GB, so grow the VM disk to ≥ 34 GB (`qemu-img resize` + cloud-init
    `growpart`).
* For SONiC provisioning: a **direct-boot `sonic-vs` disk image**
  (from the SONiC build artifacts), placed on the GNS3 host at the path set in
  `SONIC_IMG`.

## Configuration

All scripts read a single `config.env`. Copy the example and adjust it:

```bash
cp config.env.example config.env
$EDITOR config.env
```

Deploy the repository to the GNS3 host under the working directory the scripts
expect (`ONIE_WORKDIR`, default `~/onie-build`):

```bash
rsync -a ./ <gns3-host>:~/onie-build/
```

Run the remaining commands **on the GNS3 host** from `~/onie-build`.

## Step-by-step

### 1. Build ONIE

```bash
# Fetch the ONIE source (matches ONIE_SRC in config.env)
git clone https://github.com/opencomputeproject/onie ~/onie-build/onie

# Build the demo NOS + recovery ISO in a Debian 10 container (~30-40 min first run)
cd ~/onie-build/build && bash run-build.sh

# Rebuild the recovery ISO so it defaults to "Embed ONIE" (unattended disk baking)
bash run-embed-iso.sh
```

Details and troubleshooting: [`docs/build-onie.md`](docs/build-onie.md).

### 2. Bake the appliance disk

```bash
cd ~/onie-build
bash appliance/make-appliance-disk.sh      # -> ~/onie-build/onie-kvm_x86_64.qcow2
bash build/boot-check.sh                    # optional: confirm it boots from disk
```

The disk is sized from `APPLIANCE_DISK_SIZE` (default 40 GB, required to fit
SONiC's 32 GB partition).

### 3. Import into GNS3

```bash
bash gns3/deploy-appliance.sh
```

This publishes the qcow2 into the GNS3 image store, renders the `.gns3a`
descriptor, registers the **ONIE-kvm_x86_64** template (1 management + 8 data
ports, 8 GB RAM), and builds the `NAT — server — onie-switch` base topology.

Alternatively, import the appliance through the GNS3 GUI: copy
`onie-kvm_x86_64.qcow2` into the GNS3 image store and use
*File → Import appliance* on `gns3/ONIE-kvm_x86_64.gns3a` (also shipped in
the release bundle as `artifacts/onie-kvm_x86_64.gns3a`). The descriptor is
validated against the official gns3-registry `appliance_v6` schema.

### 4. Configure the provisioning server

```bash
bash provision/provision-server.sh
```

The server VM gets a static IP on its LAN NIC (`LAN_IP`), a `dnsmasq` DHCP range,
and an HTTP server offering the installer through ONIE's discovery "waterfall"
(plus DHCP option 114). By default this publishes the **ONIE demo OS** installer.

### 5. Provision the NOS

**Option A — demo OS smoke test.** With the demo installer published in step 4:

```bash
WATCH_SECS=300 bash gns3/test-provisioning.sh
```

Watch ONIE lease an address, download `onie-installer`, install, and reboot into
the demo OS.

**Option B — SONiC.** Reconstruct and publish the SONiC installer, then reboot
the ONIE node to install it:

```bash
# Mount the sonic-vs image (see docs/provision-sonic.md for the exact commands)
sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd0 --read-only "$SONIC_IMG"
sudo mkdir -p /mnt/sonic && sudo mount -o ro /dev/nbd0p3 /mnt/sonic

bash sonic/build-sonic-installer.sh        # -> ~/onie-build/sonic-pkg/target/sonic-vs.bin
bash sonic/push-sonic-installer.sh         # publish it on the server VM
WATCH_SECS=600 bash gns3/test-provisioning.sh
```

Details: [`docs/provision-sonic.md`](docs/provision-sonic.md).

### 6. Validate switching

Wire two test hosts to the first two data ports and run the VLAN test:

```bash
python3 gns3/setup-switch-test.py          # adds PC1/PC2, wires them, starts everything
# wait a few minutes for SONiC containers to come up, then:
python3 sonic/test-vlan.py
```

The test puts `Ethernet0` and `Ethernet4` into an access VLAN, confirms the two
hosts can reach each other, moves one port to a second VLAN and confirms they
are isolated, then restores the shared VLAN. Expected results and manual
equivalents: [`docs/switch-validation.md`](docs/switch-validation.md).

## Credentials

| System | Username | Password |
|--------|----------|----------|
| ONIE console / demo OS | `root` | `onie` |
| SONiC | `admin` | `YourPaSsWoRd` |
| Server VM (SSH) | `SERVER_SSH_USER` (`ubuntu`) | `SERVER_SSH_PASS` (`ubuntu`) |

> These are lab defaults. Change them (`config.env`, and SONiC's `admin`
> password) before using this outside an isolated environment.

## Troubleshooting

* **No appliance in the GNS3 GUI** — `deploy-appliance.sh` registers the
  template via the API, so it appears under *Edit → Preferences → QEMU VMs*
  (refresh the client) rather than the appliance list. To get a GUI appliance
  entry instead, import `gns3/ONIE-kvm_x86_64.gns3a` via *File → Import appliance*.
* **ONIE never installs** — confirm the server VM has DHCP/HTTP up
  (`systemctl status dnsmasq onie-http`) and that
  `curl http://<LAN_IP>/onie-installer` works from the server.
* **SONiC install stops or OOMs** — the appliance disk must be ≥ 34 GB and RAM
  ≥ 8 GB (`APPLIANCE_DISK_SIZE`, `APPLIANCE_RAM`); first boot takes several
  minutes to start ~40 containers.
* **`EthernetX is a router interface!`** — SONiC's default config is L3; remove
  the port's IP before adding it to a VLAN (the test script does this).

See [`docs/`](docs/) for the full design notes.

## License

Original work is MIT-licensed (see [`LICENSE`](LICENSE)). Vendored upstream
packaging under `sonic-ref/` keeps its own licenses; see [`NOTICE`](NOTICE).
