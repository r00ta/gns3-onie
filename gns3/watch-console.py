#!/usr/bin/env python3
"""Capture a GNS3 telnet console for a fixed time and echo it to stdout.
Usage: watch-onie-console.py <host> <port> <seconds>
"""
import socket, sys, time

host, port, secs = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
end = time.time() + secs
s = socket.create_connection((host, port), timeout=10)
s.settimeout(2)
buf = b""
try:
    while time.time() < end:
        try:
            data = s.recv(4096)
            if not data:
                time.sleep(0.5)
                continue
            buf += data
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        except socket.timeout:
            continue
finally:
    s.close()
