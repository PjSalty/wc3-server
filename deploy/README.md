# Deploying wc3-server

End to end: stand up the realm + relay + bot, make it reachable, and point the
launcher at it.

## 1. Configure

```bash
cp .env.example .env
```

Edit `.env`. The values you must set:

| Variable | What |
|----------|------|
| `PUBLIC_IP` | Your host's public (WAN) IP, advertised to players. |
| `REALM_NAME` | The realm's display name, shown in the launcher's gateway list. |
| `BOT_USERNAME` / `BOT_PASSWORD` | The account aura logs in as. Create it in-client first, or let pvpgn create it. Keep the password in your secret manager, never in git. |
| `RELAY_TOKEN` | Optional shared token launchers present. Empty = token gate off. Set `RELAY_REQUIRE_AUTH=1` to enforce it. |

Registry: images build locally by default (`IMAGE_REGISTRY=localhost/wc3`). To
pull prebuilt images instead, set `IMAGE_REGISTRY=ghcr.io/your-org` and the
`*_TAG` variables.

## 2. Run

```bash
docker compose up -d --build
```

## 3. Make it reachable

Forward these from your router/firewall to the host (all TCP):

| Port(s) | Service |
|---------|---------|
| `6112` | pvpgn realm (login / chat / game list) |
| `6200` | pvpgn w3route session relay |
| `7000` | wc3-relay tunnel port |
| `6300-6399` | wc3-relay public game-port pool (must match `RELAY_POOL_*`) |
| `7443` | wc3-mapd map library (HTTPS; launchers sync maps) |
| `6113` | aura host port |

Point a DNS **A record** at your `PUBLIC_IP` (DNS-only; do not proxy it, the
protocol is raw TCP, not HTTP).

## 4. TLS on the relay (recommended)

Put a cert + key in `deploy/tls/` and set `RELAY_TLS_CERT` / `RELAY_TLS_KEY` to
their in-container paths. Set `RELAY_REQUIRE_TLS=1` once it works. The launcher
can pin the relay cert's SPKI hash, so a self-signed cert is fine.

## 5. Map library (map sync)

Players host their own games, and their launchers sync your curated maps so
everyone has the same set and nobody waits on an in-game transfer.

Drop vetted `.w3x` / `.w3m` files into `WC3_MAPS_DIR` (`deploy/maps/` by
default). The `wc3-mapd` service serves them **read-only** over HTTPS on
`MAPD_PORT` (7443), and each launcher downloads only the maps it does not already
have, verifying every file's SHA-256 before it lands. It never overwrites a
player's own maps.

This is deliberately one-way: there is **no upload path**. A `.w3x` carries
executable map script, so auto-accepting player uploads would let anyone poison
every player's map folder. You are the only curator - add maps you trust, from
moderated sources. To update a map, add it under a new (versioned) filename;
launchers pick it up on next start.

HTTPS is required (launchers only sync over TLS): reuse the relay's cert by
setting `MAPD_TLS_CERT` / `MAPD_TLS_KEY` to the mounted `/tls` paths. The
launcher pins the same cert as the relay, so a self-signed cert is fine.

## 6. Aura game data

Aura idles until you drop your own `common.j` + `blizzard.j` (from your Warcraft
III install) into the aura data volume. This repo ships no Blizzard files.

## 7. Point the launcher at it

Give your friends the [wc3-launcher](https://github.com/PjSalty/wc3-launcher)
release. On first run it asks for the server address (your DNS name) and, if you
set one, the relay token. That's it.
