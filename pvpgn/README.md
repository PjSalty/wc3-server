# pvpgn

PvPGN-PRO Battle.net emulator for a private Warcraft III: The Frozen Throne
realm. Players log in through the classic WC3 client, see each other in
channels, and host custom games. This realm is private: it never announces to
any public tracker.

- Source: [github.com/PjSalty/pvpgn-pro-hardened](https://github.com/PjSalty/pvpgn-pro-hardened) `v0.1.1`, a
  security-hardened fork of PvPGN-PRO, GPL-2.0
- Upstream: [github.com/pvpgn/pvpgn-server](https://github.com/pvpgn/pvpgn-server), GPL-2.0
- Base image: `debian:13-slim` (Trixie)
- Storage: plain-file backend (no database)

`bnetd` parses untrusted packets straight off the internet, so the build uses the
hardened fork: modern compiler mitigations (FORTIFY_SOURCE=3, stack protector,
full RELRO, CET, PIE) plus fixes for memory-safety bugs found by fuzzing the
bnet/w3route parsers. A memory-safety bug becomes a crash the container restarts
rather than remote code execution. It is a drop-in for stock PvPGN-PRO: same
`bnetd`, same config, same 6112/6200 ports, same behaviour.

## What's here

| File | Purpose |
|------|---------|
| `Dockerfile` | multi-stage build: compiles the hardened pvpgn source, verifies the mitigations, ships a slim runtime |
| `conf/bnetd.conf.overrides` | the handful of `key = value` settings a private WC3 realm pins |
| `conf/address_translation.conf.example` | documents the split-horizon NAT format (the entrypoint generates the real file) |
| `entrypoint.sh` | applies the overlay, wires NAT for the w3route port, runs `bnetd -f` |

## Build

Build the image locally:

```bash
docker build -t pvpgn-wc3:v0.1.1 pvpgn/
```

The build clones the pinned tag, runs the documented
`cmake -D CMAKE_INSTALL_PREFIX=/usr/local/pvpgn -D PVPGN_HARDENING=ON -D WITH_LUA=true`,
then `make` / `make install`, and finally runs `test/checksec.sh` against the
built binary: if any mitigation is missing the image build fails, so an
unhardened `bnetd` can never ship. The result lands at:

- `sbin/bnetd` the server binary
- `etc/pvpgn/*.conf` config (bnetd expands `${SYSCONFDIR}` / `${LOCALSTATEDIR}` at runtime)
- `var/pvpgn/{users,clans,teams}` plain-file account store

A CI workflow can also build this and push to any registry you configure; the
repo does not require one, and building locally needs no registry at all.

## Run

```bash
docker run -d --name pvpgn \
  -p 6112:6112/tcp \
  -p 6200:6200/tcp \
  -e PVPGN_PUBLIC_IP=203.0.113.10 \
  -v pvpgn-data:/usr/local/pvpgn/var/pvpgn \
  pvpgn-wc3:v0.1.1
```

Replace `203.0.113.10` (an RFC-5737 documentation address) with your own
public/WAN IP. `bnetd` runs in the foreground (`-f`) as pid 1, so
`docker logs -f pvpgn` shows realm activity live.

### Environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `PVPGN_PUBLIC_IP` | *(empty)* | public IP for NAT. Empty means no translation (LAN or direct only). Set this when the realm sits behind NAT. |
| `PVPGN_LOCAL_CIDR` | `192.168.0.0/16,10.0.0.0/8,172.16.0.0/12` | client networks that keep the internal w3route address. Only clients outside these get the public IP. |
| `PVPGN_W3ROUTE_PORT` | `6200` | w3route TCP port (keep in sync with `w3routeaddr`). |
| `PVPGN_LOG_STDOUT` | `true` | send the log to stdout. Set `false` to log to `var/pvpgn/bnetd.log`. |

## Ports and NAT

Two TCP ports face the players:

- `6112/tcp` bnetd, the Battle.net client connection
- `6200/tcp` w3route, WC3 matchmaking

Forward both from the router to the host, then set `PVPGN_PUBLIC_IP`. The
entrypoint writes `address_translation.conf` so external clients receive the
public IP for the w3route port while LAN clients keep the internal address.
See `conf/address_translation.conf.example` for the file format. Game hosting
itself is peer-to-peer through the bot, so players never forward their own
ports.

## Accounts

New accounts are created from the game client (`new_accounts = true`). First
person to log in with a name registers it. Accounts live in the mounted volume,
so keep `var/pvpgn/` on a persistent volume or the account list resets on
rebuild. The volume must be writable by uid 1000.

## Client

Players use the classic WC3: TFT client, version `1.28.5` (or `1.26a`), plus
the [W3L loader](https://github.com/pvpgn/w3l) (`w3l.exe` + `w3lh.dll`) to
bypass Battle.net signature checks. Reforged (1.29+) can NOT connect. The
loader and client wiring are the launcher component's job, not this server's.

Each player must own a legitimate copy of Warcraft III: Reign of Chaos and The
Frozen Throne. No Blizzard game data is shipped here.

## Config overlay

`bnetd.conf.overrides` holds only the keys a private realm pins:

- `track = 0` don't announce to any public tracker
- `new_accounts = true` in-client signup
- `servaddrs = ":"` listen on all interfaces, port 6112
- `w3routeaddr = "0.0.0.0:6200"` w3route listener
- `motdw3file = w3motd.txt` message shown in the custom-games menu

Everything else keeps its upstream default, including the plain-file
`storage_path`. The entrypoint applies each override idempotently into the
installed `bnetd.conf`, so it's safe to restart. `logfile` and `transfile` are
set from the environment at startup, so they're not pinned in the overlay.

## Run without Docker

The built `/usr/local/pvpgn` tree also runs natively. Install the tree on the
host and start it the same way the entrypoint does:

```bash
/usr/local/pvpgn/sbin/bnetd -f -c /usr/local/pvpgn/etc/pvpgn/bnetd.conf
```

To hand off a tarball instead of a registry image:

```bash
docker create --name pvpgn-export pvpgn-wc3:v0.1.1
docker export pvpgn-export -o pvpgn-wc3-v0.1.1.tar
```
