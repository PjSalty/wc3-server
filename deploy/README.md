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
| `6113` | aura host port |

Point a DNS **A record** at your `PUBLIC_IP` (DNS-only; do not proxy it, the
protocol is raw TCP, not HTTP).

## 4. TLS on the relay (recommended)

Put a cert + key in `deploy/tls/` and set `RELAY_TLS_CERT` / `RELAY_TLS_KEY` to
their in-container paths. Set `RELAY_REQUIRE_TLS=1` once it works. The launcher
can pin the relay cert's SPKI hash, so a self-signed cert is fine.

## 5. Aura game data

Aura idles until you drop your own `common.j` + `blizzard.j` (from your Warcraft
III install) into the aura data volume. This repo ships no Blizzard files.

## 6. Point the launcher at it

Give your friends the [wc3-launcher](https://github.com/PjSalty/wc3-launcher)
release. On first run it asks for the server address (your DNS name) and, if you
set one, the relay token. That's it.
