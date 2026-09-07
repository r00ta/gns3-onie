#!/usr/bin/env python3
"""Attach two test hosts to the ONIE/SONiC switch's first two data ports.

Adds two VPCS nodes and wires them to the switch:
    PC1 -> ONIE adapter 1  (front-panel Ethernet0)
    PC2 -> ONIE adapter 2  (front-panel Ethernet4)

The switch node already exposes 1 management + 8 data ports (see setup-gns3.py),
so no reconfiguration of the switch is required. Run after a NOS is installed:
    python3 setup-switch-test.py
Idempotent: existing PCs and links are reused by name.
"""
import os

import gns3lib as g

ONIE_NAME = os.environ.get("GNS3_ONIE_NAME", "onie-switch")
PC1_NAME = os.environ.get("GNS3_PC1_NAME", "PC1")
PC2_NAME = os.environ.get("GNS3_PC2_NAME", "PC2")


def ensure_pc(pid, vpcs_tid, name, x, y):
    node = g.find_node(pid, name)
    if node:
        return node
    node = g.api("POST", f"/projects/{pid}/templates/{vpcs_tid}",
                 {"x": x, "y": y, "compute_id": "local"})
    g.api("PUT", f"/projects/{pid}/nodes/{node['node_id']}", {"name": name})
    return g.find_node(pid, name)


def ensure_link(pid, links, pc_id, sw_id, sw_adapter):
    ends = {(pc_id, 0, 0), (sw_id, sw_adapter, 0)}
    for link in links:
        got = {(n["node_id"], n["adapter_number"], n["port_number"]) for n in link["nodes"]}
        if got == ends:
            print(f"  link to adapter {sw_adapter} already exists")
            return
    g.api("POST", f"/projects/{pid}/links", {"nodes": [
        {"node_id": pc_id, "adapter_number": 0, "port_number": 0},
        {"node_id": sw_id, "adapter_number": sw_adapter, "port_number": 0},
    ]})
    print(f"  linked to switch adapter {sw_adapter}")


def main():
    pid = g.project_id(create=False)
    switch = g.find_node(pid, ONIE_NAME)
    if not switch:
        raise SystemExit(f"switch node {ONIE_NAME!r} not found")
    vpcs = g.find(g.api("GET", "/templates"), template_type="vpcs")
    if not vpcs:
        raise SystemExit("no VPCS template available on this GNS3 server")
    vpcs_tid = vpcs["template_id"]

    pc1 = ensure_pc(pid, vpcs_tid, PC1_NAME, 400, 150)
    pc2 = ensure_pc(pid, vpcs_tid, PC2_NAME, 400, 300)
    print(f"{PC1_NAME}={pc1['node_id']}  {PC2_NAME}={pc2['node_id']}")

    links = g.api("GET", f"/projects/{pid}/links")
    ensure_link(pid, links, pc1["node_id"], switch["node_id"], 1)
    ensure_link(pid, links, pc2["node_id"], switch["node_id"], 2)

    for nid in (switch["node_id"], pc1["node_id"], pc2["node_id"]):
        g.api("POST", f"/projects/{pid}/nodes/{nid}/start")
    print("Started switch + PCs. Allow a few minutes for SONiC containers to come up.")


if __name__ == "__main__":
    main()
