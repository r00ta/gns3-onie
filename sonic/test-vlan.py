#!/usr/bin/env python3
"""Configure and validate L2/VLAN switching on the SONiC appliance.

Drives the SONiC console and the two VPCS consoles over telnet to:
  1. put data ports Ethernet0 and Ethernet4 into an access VLAN,
  2. verify two hosts in that VLAN can reach each other,
  3. move one port to a second VLAN and verify the hosts are isolated,
  4. restore the shared VLAN and re-verify connectivity.

Console ports are discovered from the GNS3 API by node name, so nothing is
hard-coded. Run on the GNS3 host:  python3 test-vlan.py
"""
import os
import socket
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "gns3"))
import gns3lib as g

ONIE_NAME = os.environ.get("GNS3_ONIE_NAME", "onie-switch")
PC1_NAME = os.environ.get("GNS3_PC1_NAME", "PC1")
PC2_NAME = os.environ.get("GNS3_PC2_NAME", "PC2")
USER = os.environ.get("SONIC_USER", "admin")
PASS = os.environ.get("SONIC_PASS", "YourPaSsWoRd")
VLAN = os.environ.get("TEST_VLAN", "10")
VLAN2 = str(int(VLAN) + 10)
PC1_IP = os.environ.get("PC1_IP", "192.168.50.10")
PC2_IP = os.environ.get("PC2_IP", "192.168.50.20")
MASK = os.environ.get("TEST_NETMASK", "255.255.255.0")

# The two wired data ports (adapter 1 -> Ethernet0, adapter 2 -> Ethernet4).
PORT1, PORT2 = "Ethernet0", "Ethernet4"


def drain(sock):
    out = b""
    try:
        while True:
            out += sock.recv(4096)
    except Exception:
        pass
    return out.decode(errors="replace")


def send(sock, cmd, wait=3):
    sock.sendall(cmd.encode() + b"\r\n")
    time.sleep(wait)
    return drain(sock)


def console(port):
    sock = socket.create_connection(("127.0.0.1", port), timeout=10)
    sock.settimeout(6)
    return sock


def sonic(port, cmds):
    sock = console(port)
    send(sock, "", 1)
    send(sock, USER, 2)
    send(sock, PASS, 3)
    out = "".join(send(sock, c, 3) for c in cmds)
    sock.close()
    return out


def pc(port, cmds):
    sock = console(port)
    send(sock, "", 1)
    out = "".join(send(sock, c, 2) for c in cmds)
    sock.close()
    return out


def main():
    pid = g.project_id(create=False)
    sw = g.console_port(pid, ONIE_NAME)
    c1 = g.console_port(pid, PC1_NAME)
    c2 = g.console_port(pid, PC2_NAME)
    print(f"consoles: switch={sw} {PC1_NAME}={c1} {PC2_NAME}={c2}")

    print(f"\n== Create VLAN {VLAN} and add {PORT1}/{PORT2} as untagged members ==")
    print(sonic(sw, [
        f"sudo config vlan add {VLAN}",
        f"sudo config interface ip remove {PORT1} 10.0.0.0/31",
        f"sudo config interface ip remove {PORT2} 10.0.0.2/31",
        f"sudo config vlan member add -u {VLAN} {PORT1}",
        f"sudo config vlan member add -u {VLAN} {PORT2}",
        f"sudo config interface startup {PORT1}",
        f"sudo config interface startup {PORT2}",
        "sudo config save -y",
        "show vlan brief",
    ]))

    print("== Address the two hosts in the same subnet ==")
    print(pc(c1, [f"ip {PC1_IP} {MASK}"]))
    print(pc(c2, [f"ip {PC2_IP} {MASK}"]))

    print(f"== SAME VLAN: {PC1_NAME} -> {PC2_NAME} (expect success) ==")
    print(pc(c1, ["clear arp", f"ping {PC2_IP} -c 4"]))

    print(f"== Isolate: move {PORT2} to VLAN {VLAN2} ==")
    print(sonic(sw, [
        f"sudo config vlan add {VLAN2}",
        f"sudo config vlan member del {VLAN} {PORT2}",
        f"sudo config vlan member add -u {VLAN2} {PORT2}",
        f"sudo config interface startup {PORT2}",
        "show vlan brief",
    ]))

    print(f"== DIFFERENT VLAN: {PC1_NAME} -> {PC2_NAME} (expect failure) ==")
    print(pc(c1, ["clear arp", f"ping {PC2_IP} -c 4"]))

    print(f"== Restore {PORT2} to VLAN {VLAN} and save ==")
    print(sonic(sw, [
        f"sudo config vlan member del {VLAN2} {PORT2}",
        f"sudo config vlan del {VLAN2}",
        f"sudo config vlan member add -u {VLAN} {PORT2}",
        f"sudo config interface startup {PORT2}",
        "sudo config save -y",
        "show vlan brief",
    ]))

    print(f"== SAME VLAN again: {PC1_NAME} -> {PC2_NAME} (expect success) ==")
    print(pc(c1, ["clear arp", f"ping {PC2_IP} -c 3"]))


if __name__ == "__main__":
    main()
