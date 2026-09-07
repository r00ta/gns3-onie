# Switch and VLAN validation

Once SONiC is installed, the appliance is validated as a real Layer-2 switch
between two hosts wired to its first two data ports.

## Wiring

`gns3/setup-switch-test.py` adds two VPCS hosts and connects them:

| Host | GNS3 adapter | SONiC port |
|------|--------------|------------|
| PC1 | ONIE adapter 1 | `Ethernet0` |
| PC2 | ONIE adapter 2 | `Ethernet4` |

## Default config caveat

SONiC-vs ships a T1 config in which every port is an **L3 routed** interface with
a `/31` and a BGP neighbor. Adding such a port to a VLAN fails with
`Error: EthernetX is a router interface!`. The L3 address must be removed first:

```bash
sudo config interface ip remove Ethernet0 10.0.0.0/31
sudo config interface ip remove Ethernet4 10.0.0.2/31
```

## Automated test

```bash
python3 sonic/test-vlan.py
```

Console ports are discovered from the GNS3 API by node name. The driver logs into
the SONiC and VPCS consoles and runs the sequence below.

### Procedure and expected results

1. **Access VLAN.** Create VLAN 10, remove the L3 addresses from `Ethernet0` /
   `Ethernet4`, add both as untagged members, bring them up, save. Address the
   hosts in one subnet (`192.168.50.10/24`, `192.168.50.20/24`).
   * `show vlan brief` lists both ports untagged in VLAN 10; `show mac` learns
     both host MACs dynamically on VLAN 10.
   * **PC1 → PC2 ping succeeds.** ✅
2. **Isolation.** Move `Ethernet4` into VLAN 20.
   * **PC1 → PC2 ping fails** (`host not reachable`). ✅
3. **Restore.** Move `Ethernet4` back to VLAN 10 and save.
   * **PC1 → PC2 ping succeeds again.** ✅

### Manual equivalent

```bash
sudo config vlan add 10
sudo config interface ip remove Ethernet0 10.0.0.0/31
sudo config interface ip remove Ethernet4 10.0.0.2/31
sudo config vlan member add -u 10 Ethernet0
sudo config vlan member add -u 10 Ethernet4
sudo config interface startup Ethernet0
sudo config interface startup Ethernet4
sudo config save -y
show vlan brief
show mac
```

`config save -y` persists the configuration across reboots. Login: `admin` /
`YourPaSsWoRd`.
