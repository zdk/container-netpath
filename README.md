# netpath

Shows how traffic leaves each [apple/container](https://github.com/apple/container) network, and where it stops.

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

## Use

```bash
container netpath              # every network
container netpath <name|ip>    # one network or container
container netpath --json       # for scripts and agents
```

A broken step is marked `✗`, with a `fix:` line below it.

Exit codes: `0` healthy, `1` broken, `2` could not inspect the host.

## Notes

- If `container` came from Homebrew, run `netpath enable` again after `brew upgrade container` ([#1617](https://github.com/apple/container/issues/1617)).
- The NAT step is inferred. Checking it needs root.
- A lost bridge with several networks is usually [#2051](https://github.com/apple/container/issues/2051).
- Build from source: `make build && sudo make install`. Needs a current Xcode.
