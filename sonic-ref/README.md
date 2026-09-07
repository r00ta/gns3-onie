# Third-party ONIE/SONiC packaging scripts

These files are **pinned copies of upstream scripts**, vendored here so the
SONiC installer can be reconstructed offline. They are used by
`sonic/build-sonic-installer.sh`.

| File | Upstream source | License |
|------|-----------------|---------|
| `install.sh` | `sonic-net/sonic-buildimage` (`installer/x86_64/install.sh`) | GPL-2.0 |
| `sharch_body.sh` | `opencomputeproject/onie` (`installer/sharch_body.sh`) | GPL-2.0 |
| `onie-mk-demo.sh` | `opencomputeproject/onie` (`demo/mk/onie-mk-demo.sh`) | GPL-2.0 |
| `default_platform.conf` | `sonic-net/sonic-buildimage` | GPL-2.0 |
| `onie-image.conf` | `sonic-net/sonic-buildimage` | GPL-2.0 |

These retain their original copyright headers and licenses. See `NOTICE` in the
repository root. To refresh them, re-fetch from the upstream `master` branches.
