# Embedding a Docker container in the SONiC image

This lab can bake an arbitrary Docker container into the SONiC installer so that
every switch you provision runs it automatically — no registry access required
at runtime.

## How it works

`sonic/embed-container.sh` takes a **finished** SONiC installer (a `.bin`
produced by `sonic/build-sonic-installer.sh`) and emits a new `.bin` — installer
in, installer out. The input is left untouched. It:

1. Builds your container (legacy builder, so `docker save` yields a tarball that
   SONiC's Docker Engine can `docker load`) and saves it to a tarball.
2. Extracts the installer payload, unpacks its root filesystem (`fs.squashfs`)
   and injects:
   - `/usr/local/<name>/<name>.tar` — the saved image;
   - `/usr/local/<name>/start.sh` — `docker load` + `docker run`;
   - `/etc/systemd/system/<name>.service` — a oneshot unit ordered
     `After=docker.service`, enabled via `multi-user.target.wants`.
3. Repacks `fs.squashfs` (same compressor), swaps it back into the payload, and
   re-wraps the self-extracting installer. The 2 GB `dockerfs.tar.gz` shipped
   inside the installer is reused untouched.

The container image lives in the read-only base layer, so it survives
`config reload` and reboots; the systemd unit re-creates the container on every
boot.

## Usage

```bash
# Embed a container into an existing installer (defaults to the hello-world example).
INSTALLER=~/onie-build/sonic-pkg/target/sonic-vs.bin \
    bash sonic/embed-container.sh
#   -> ~/onie-build/sonic-pkg/target/sonic-vs-hello-sonic.bin

# Publish it and provision a switch as usual.
SERVER_IP=<vm-ip> BIN=~/onie-build/sonic-pkg/target/sonic-vs-hello-sonic.bin \
    bash sonic/push-sonic-installer.sh
```

## Providing your own container

The example lives in `sonic/embed-container/hello-world/` (an `app/` folder plus
a `Dockerfile`); edit `app/hello.sh` to change what it does, or point the script
at a different build context:

```bash
CONTEXT=/path/to/your/container \
IMAGE=my-agent:1.0 NAME=my-agent \
    bash sonic/embed-container.sh
```

If your container needs specific `docker run` flags (host networking, bind
mounts, capabilities, …), pass them via `RUN_OPTS`; they are baked into the
generated `start.sh`:

```bash
CONTEXT=/path/to/your/agent IMAGE=my-agent:1.0 NAME=my-agent \
RUN_OPTS="--network host -v /var/run/redis:/var/run/redis -v /etc/sonic:/etc/sonic:ro" \
    bash sonic/embed-container.sh
```

Guidelines for an embeddable image:

- Base it on a small image (e.g. `busybox`, `alpine`, `distroless`); the
  appliance has no internet access, so every layer must be inside the saved
  tarball.
- The entrypoint should be a long-running foreground process. If it depends on
  SONiC services (e.g. the redis CONFIG_DB/STATE_DB socket) that come up after
  Docker, keep `--restart unless-stopped` (the default) so it retries until they
  are ready.

## Verifying on the switch

After the switch boots SONiC (`admin` / the configured password):

```bash
systemctl is-active <name>        # -> active
sudo docker ps    | grep <name>   # -> Up ...
sudo docker logs <name>
```

For a supported, lifecycle-managed alternative (FEATURE table, CLI plugins,
warm-reboot integration), see SONiC's own
[application extension framework](https://github.com/sonic-net/SONiC/blob/master/doc/sonic-application-extension/sonic-application-extension.md);
this script is the lightweight "bake a container into the image" path.
