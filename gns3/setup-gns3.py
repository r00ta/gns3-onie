#!/usr/bin/env python3
"""Register the ONIE appliance template and build the base provisioning topology.

    NAT ── eth0(server)                internet (apt + downloads)
           eth1(server) ── eth0(onie)  provisioning LAN (DHCP + HTTP)

The ONIE node is created with one management port plus eight data ports; only
the management port (adapter 0) is wired here, which is all ONIE needs to
discover and install a NOS. The data ports are wired later by
setup-switch-test.py once a NOS is installed.

Run on the GNS3 host after deploy-appliance.sh has published the disk image:
    python3 setup-gns3.py
Idempotent: existing template, nodes and links are reused by name.
"""
import os
import sys
import time

import gns3lib as g

TEMPLATE_NAME = "ONIE-kvm_x86_64"
ONIE_IMAGE = "onie-kvm_x86_64.qcow2"
SERVER_NAME = os.environ.get("GNS3_SERVER_NAME", "server")
ONIE_NAME = os.environ.get("GNS3_ONIE_NAME", "onie-switch")
RAM = int(os.environ.get("APPLIANCE_RAM", "8192"))
ADAPTERS = int(os.environ.get("APPLIANCE_ADAPTERS", "9"))
NIC = os.environ.get("APPLIANCE_NIC", "e1000")


def ensure_template():
    tmpl = g.find(g.api("GET", "/templates"), name=TEMPLATE_NAME)
    spec = {
        "name": TEMPLATE_NAME,
        "template_type": "qemu",
        "compute_id": "local",
        "platform": os.environ.get("ONIE_ARCH", "x86_64"),
        "qemu_path": "/usr/bin/qemu-system-x86_64",
        "hda_disk_image": ONIE_IMAGE,
        "hda_disk_interface": "virtio",
        "ram": RAM,
        "cpus": 1,
        "adapters": ADAPTERS,
        "adapter_type": NIC,
        "console_type": "telnet",
        "boot_priority": "c",
        "on_close": "power_off",
        "options": "-nographic",
        "category": "guest",
        "symbol": ":/symbols/qemu_guest.svg",
    }
    if tmpl:
        print("Template exists, updating:", TEMPLATE_NAME)
        g.api("PUT", f"/templates/{tmpl['template_id']}",
              {"ram": RAM, "adapters": ADAPTERS, "adapter_type": NIC})
        return tmpl["template_id"]
    print("Creating template:", TEMPLATE_NAME)
    return g.api("POST", "/templates", spec)["template_id"]


def add_from_template(pid, tid, x, y):
    return g.api("POST", f"/projects/{pid}/templates/{tid}",
                 {"x": x, "y": y, "compute_id": "local"})


def make_link(pid, links, a, b):
    ends = {(a["node_id"], a["adapter_number"], a["port_number"]),
            (b["node_id"], b["adapter_number"], b["port_number"])}
    for link in links:
        got = {(n["node_id"], n["adapter_number"], n["port_number"]) for n in link["nodes"]}
        if got == ends:
            print("  link already exists")
            return
    g.api("POST", f"/projects/{pid}/links", {"nodes": [a, b]})
    print("  link created")


def main():
    pid = g.project_id()
    tid = ensure_template()

    ns = g.nodes(pid)
    server = g.find(ns, name=SERVER_NAME)
    if not server:
        sys.exit(f"ERROR: node {SERVER_NAME!r} not found. Add your provisioning "
                 f"server VM to the project and name it {SERVER_NAME!r} first.")

    onie = g.find(ns, name=ONIE_NAME)
    if not onie:
        print("Creating ONIE node:", ONIE_NAME)
        onie = add_from_template(pid, tid, 200, 0)
        g.api("PUT", f"/projects/{pid}/nodes/{onie['node_id']}", {"name": ONIE_NAME})

    nat = g.find(ns, node_type="nat")
    if not nat:
        nat_tmpl = g.find(g.api("GET", "/templates"), template_type="nat")
        if not nat_tmpl:
            sys.exit("ERROR: no NAT template available on this GNS3 server.")
        print("Creating NAT node")
        nat = add_from_template(pid, nat_tmpl["template_id"], -250, -120)

    # The server needs a second NIC for the provisioning LAN (requires it stopped).
    server = g.api("GET", f"/projects/{pid}/nodes/{server['node_id']}")
    if server["properties"].get("adapters", 1) < 2:
        print("Giving server a second NIC (stop -> patch -> start)")
        if server.get("status") == "started":
            g.api("POST", f"/projects/{pid}/nodes/{server['node_id']}/stop")
            time.sleep(3)
        g.api("PUT", f"/projects/{pid}/nodes/{server['node_id']}",
              {"properties": {"adapters": 2}})

    links = g.api("GET", f"/projects/{pid}/links")
    sid, oid, nid = server["node_id"], onie["node_id"], nat["node_id"]
    print("Linking server eth0 <-> NAT")
    make_link(pid, links, {"node_id": sid, "adapter_number": 0, "port_number": 0},
              {"node_id": nid, "adapter_number": 0, "port_number": 0})
    print("Linking server eth1 <-> ONIE management port (adapter 0)")
    make_link(pid, links, {"node_id": sid, "adapter_number": 1, "port_number": 0},
              {"node_id": oid, "adapter_number": 0, "port_number": 0})

    srv = g.api("GET", f"/projects/{pid}/nodes/{sid}")
    if srv.get("status") != "started":
        print("Starting server node")
        g.api("POST", f"/projects/{pid}/nodes/{sid}/start")

    print("\nProject nodes:")
    for n in g.nodes(pid):
        print(f"  {n['name']:16} {n['node_type']:8} console={n.get('console')} status={n.get('status')}")


if __name__ == "__main__":
    main()
