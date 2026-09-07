#!/usr/bin/env python3
"""Small GNS3 v2 REST helper used by the topology and test scripts.

Configuration is read from config.env (literal KEY=VALUE lines) and the process
environment, so nothing about the target project is hard-coded.
"""
import json
import os
import re
import urllib.error
import urllib.request


def load_config():
    """Merge literal KEY=VALUE pairs from config.env into the environment.

    Real environment variables win; shell-expanded values (containing '$') are
    left for the shell scripts and skipped here.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    for path in (os.path.join(here, os.pardir, "config.env"),
                 os.path.expanduser("~/onie-build/config.env")):
        if not os.path.isfile(path):
            continue
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, val = line.split("=", 1)
                key, val = key.strip(), val.strip().strip('"').strip("'")
                val = re.sub(r"\s+#.*$", "", val).strip().strip('"').strip("'")
                if "$" in val:
                    continue
                os.environ.setdefault(key, val)
        break


load_config()

API = os.environ.get("GNS3_API", "http://localhost:3080/v2")


def api(method, path, data=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(API + path, data=body, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            txt = resp.read().decode()
            return json.loads(txt) if txt else {}
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"{method} {path} -> {exc.code}: {exc.read().decode()}")


def find(items, **kw):
    for item in items:
        if all(item.get(k) == v for k, v in kw.items()):
            return item
    return None


def project_id(name=None, create=True):
    """Return the id of the project called *name*, optionally creating it."""
    name = name or os.environ.get("GNS3_PROJECT_NAME", "onie-lab")
    proj = find(api("GET", "/projects"), name=name)
    if proj:
        return proj["project_id"]
    if not create:
        raise RuntimeError(f"project {name!r} not found")
    return api("POST", "/projects", {"name": name})["project_id"]


def nodes(pid):
    return api("GET", f"/projects/{pid}/nodes")


def find_node(pid, name):
    return find(nodes(pid), name=name)


def console_port(pid, name):
    node = find_node(pid, name)
    if not node:
        raise RuntimeError(f"node {name!r} not found in project")
    return node["console"]
