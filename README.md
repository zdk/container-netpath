# netpath

A plugin for [apple/container](https://github.com/apple/container). It shows how traffic leaves each container network, and where it stops.

```
$ container netpath
default  192.168.64.0/24                                ✓ healthy

  buildkit 192.168.64.2 ─┐
═════════════════════════╪═══ host ══════
  vmenet0, vmenet1       ▼
  bridge100              ▼  gw 192.168.64.1
  route                  ▼  192.168.64.0/24 → bridge100
  NAT                    ▼  → 192.168.1.140
  en0                    ▼  192.168.1.140
═════════════════════════╪═══════════════
  router 192.168.1.1     ▼  → internet ✓
```

## Install

```bash
make build
sudo make install
```

The plugin is installed to `/usr/local/libexec/container-plugins/netpath`.

## Use

```bash
container netpath              # every network
container netpath <name|ip>    # one network or container
container netpath --json       # for scripts and agents
```

When a network is broken, the step where traffic stops is marked `✗`. A `fix:` line underneath tells you what to do.

Exit codes: `0` healthy, `1` something is broken, `2` could not inspect the host.

## Notes

- The NAT step is inferred, not checked. Reading the NAT rules needs root.
- A network with no running containers shows as `idle`. vmnet only creates a bridge while a container is attached.
- `bridge_missing` with several networks is usually [apple/container#2051](https://github.com/apple/container/issues/2051).
