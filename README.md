# netpath

Display [apple/container](https://github.com/apple/container) the packet traverses host network.

```
$ container netpath
default  192.168.64.0/24                                ✓ healthy

  buildkit 192.168.64.2 ─┐
═════════════════════════╪═══ host ══════
  vmenet0                ▼
  bridge100              ▼  gw 192.168.64.1
  route                  ▼  192.168.64.0/24 → bridge100
  NAT                    ▼  → 192.168.1.140
  en0                    ▼  192.168.1.140
═════════════════════════╪═══════════════
  router 192.168.1.1     ▼  → internet ✓
```

## Install

```bash
brew install zdk/tools/container-netpath
netpath enable
```

`netpath enable` adds the plugin to `container`. It asks for `sudo` only if needed. `netpath disable` removes it.

## Usage

```bash
container netpath              # show for every network
container netpath <name|ip>    # show for specified network name or container ip
container netpath --json       # use for scripting and agents
```

A broken route is marked `✗`

## Caveats

- If you installed `container` with Homebrew, please run `netpath enable` again after `brew upgrade container`.
