#!/bin/bash
# Shared helpers for the ONIE/GNS3 shell scripts.
# Source this near the top of a script:  . "$(dirname "$0")/../lib.sh"
# It loads config.env (if present) and provides small utilities.

# Load configuration. Search next to the repo root and the deploy workdir.
_load_config() {
    local self here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for c in "$here/config.env" "$HOME/onie-build/config.env"; do
        if [ -f "$c" ]; then
            # shellcheck disable=SC1090
            . "$c"
            return 0
        fi
    done
    return 0
}
_load_config

# Resolve the server VM IP on the GNS3 NAT network (libvirt default network).
gns3_server_ip() {
    local ip
    ip=$(sudo virsh net-dhcp-leases default 2>/dev/null | awk '/ipv4/{print $5}' | cut -d/ -f1 | head -1)
    [ -z "$ip" ] && ip=$(ip neigh show dev virbr0 2>/dev/null | awk '/REACHABLE|STALE|DELAY/{print $1; exit}')
    echo "$ip"
}

# Wait for the server VM to answer SSH; prints its IP on success.
wait_server_ip() {
    local ip="" i
    for i in $(seq 1 30); do
        ip=$(gns3_server_ip)
        [ -n "$ip" ] && break
        sleep 5
    done
    [ -n "$ip" ] || { echo "ERROR: could not resolve server VM IP on the NAT network" >&2; return 1; }
    echo "$ip"
}

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
