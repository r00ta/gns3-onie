# ONIE + SONiC switch appliance for GNS3

Build an [ONIE](https://opencomputeproject.github.io/onie/) (Open Network Install
Environment) virtual appliance from source, import it into
[GNS3](https://www.gns3.com/), provision it over the network with a network
operating system, and run it as a Layer-2 switch.

The repository is organised around **three independent build generators** plus a
deploy/validate workflow:

1. **ONIE appliance** — [`build/make-onie-appliance.sh`](build/make-onie-appliance.sh)
   compiles ONIE for the `kvm_x86_64` target and produces a GNS3-ready appliance
   disk (`onie-kvm_x86_64.qcow2`) and its importable descriptor
   (`onie-kvm_x86_64.gns3a`).
2. **SONiC installer** — [`sonic/build-sonic-installer.sh`](sonic/build-sonic-installer.sh)
   turns a direct-boot `sonic-vs` disk image into a genuine ONIE installer
   (`sonic-vs.bin`) that ONIE can download and install.
3. **Container embed** (optional) — [`sonic/embed-container.sh`](sonic/embed-container.sh)
   takes a finished installer plus a Docker build context and emits a new
   installer that runs your container automatically on every switch.

You then **deploy** the appliance into GNS3, **provision** it with the demo OS or
SONiC over ONIE's DHCP/HTTP discovery, and **validate** it as an 8-port VLAN
switch.

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
| **`build/make-onie-appliance.sh`** | GNS3 host | **Generator 1:** build the ONIE qcow2 + `.gns3a`. |
| `build/`, `appliance/make-appliance-disk.sh` | GNS3 host + container | Sub-steps: compile ONIE, embed ISO, bake the disk. |
| `appliance/render-gns3a.sh` | GNS3 host | Render the `.gns3a` descriptor from the baked disk. |
| **`sonic/build-sonic-installer.sh`** | GNS3 host | **Generator 2:** `sonic-vs` image → `sonic-vs.bin`. |
| **`sonic/embed-container.sh`**, `sonic/embed-container/` | GNS3 host | **Generator 3:** bake a Docker container into an installer. |
| `gns3/deploy-appliance.sh`, `setup-gns3.py` | GNS3 host | Deploy: publish the image, register the template, build the topology. |
| `provision/` | GNS3 host + server VM | Turn the server VM into a DHCP + HTTP provisioning server. |
| `sonic/push-sonic-installer.sh` | GNS3 host | Publish an installer on the server VM. |
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

## Build the artifacts

The three generators are independent. Run only what you need.

### Generator 1 — ONIE appliance (qcow2 + `.gns3a`)

```bash
bash build/make-onie-appliance.sh
```

This compiles ONIE in a Debian 10 container (~30-40 min first run), rebuilds the
recovery ISO so it defaults to *Embed ONIE*, boots it once under legacy BIOS to
bake the disk, and renders the descriptor. Outputs land under `ONIE_WORKDIR`
(default `~/onie-build`):

* `onie-kvm_x86_64.qcow2` — the GNS3-ready appliance disk (40 GB virtual,
  ~26 MB actual);
* `onie-kvm_x86_64.gns3a` — the importable appliance descriptor (real md5/size,
  validated against the official gns3-registry `appliance_v6` schema).

Re-run without recompiling ONIE with `SKIP_ONIE_BUILD=1`. The individual steps
(`build/run-build.sh`, `build/run-embed-iso.sh`,
`appliance/make-appliance-disk.sh`, `appliance/render-gns3a.sh`) can also be run
on their own. Details and troubleshooting:
[`docs/build-onie.md`](docs/build-onie.md).

### Generator 2 — SONiC installer (`sonic-vs.bin`)

Given a direct-boot `sonic-vs` disk image (from the SONiC build artifacts),
reconstruct a genuine ONIE installer:

```bash
SONIC_IMG=~/onie-build/sonic-vs.img.gz \
    bash sonic/build-sonic-installer.sh   # -> ~/onie-build/sonic-pkg/target/sonic-vs.bin
```

The script mounts the image's SONiC-OS partition (via `qemu-nbd`, read-only),
repackages its payload with SONiC's own `onie-mk-demo.sh`, and unmounts on exit.
`SONIC_IMG` accepts a raw `.img` or a gzipped `.img.gz`. To mount the image
yourself instead, leave `SONIC_IMG` unset and mount it at `$IMG_MNT`. Details:
[`docs/provision-sonic.md`](docs/provision-sonic.md).

### Generator 3 — embed a container into an installer (optional)

Bake a Docker container into a finished installer so every provisioned switch
runs it automatically — installer in, installer out:

```bash
INSTALLER=~/onie-build/sonic-pkg/target/sonic-vs.bin \
    bash sonic/embed-container.sh
#   -> ~/onie-build/sonic-pkg/target/sonic-vs-hello-sonic.bin
```

The example container lives in `sonic/embed-container/hello-world/`; point the
script at your own build context with `CONTEXT`/`IMAGE`/`NAME`. The input
installer is left untouched. Details:
[`docs/embed-container.md`](docs/embed-container.md).

## Deploy and validate in GNS3

### 1. Deploy the appliance

```bash
bash gns3/deploy-appliance.sh
```

This publishes the qcow2 into the GNS3 image store, (re)renders the `.gns3a`
descriptor, registers the **ONIE-kvm_x86_64** template (1 management + 8 data
ports, 8 GB RAM), and builds the `NAT — server — onie-switch` base topology.

Alternatively, import through the GNS3 GUI: copy `onie-kvm_x86_64.qcow2` into the
GNS3 image store and use *File → Import appliance* on the generated
`onie-kvm_x86_64.gns3a`.

### 2. Configure the provisioning server

```bash
bash provision/provision-server.sh
```

The server VM gets a static IP on its LAN NIC (`LAN_IP`), a `dnsmasq` DHCP range,
and an HTTP server offering the installer through ONIE's discovery "waterfall"
(plus DHCP option 114). By default this publishes the **ONIE demo OS** installer.

### 3. Provision the NOS

**Option A — demo OS smoke test.** With the demo installer published in step 2:

```bash
WATCH_SECS=300 bash gns3/test-provisioning.sh
```

Watch ONIE lease an address, download `onie-installer`, install, and reboot into
the demo OS.

**Option B — SONiC.** Publish the installer built by Generator 2 (or 3), then
reboot the ONIE node to install it:

```bash
bash sonic/push-sonic-installer.sh         # publish it on the server VM
WATCH_SECS=600 bash gns3/test-provisioning.sh
```

### 4. Validate switching

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
