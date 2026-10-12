# Deploying wc3-server

End to end: stand up the realm + relay + map library, make it reachable, and
point the launcher at it.

## 1. Configure

```bash
cp .env.example .env
```

Edit `.env`. The values you must set:

| Variable | What |
|----------|------|
| `PUBLIC_IP` | Your host's public (WAN) IP, advertised to players. |
| `REALM_NAME` | The realm's display name, shown in the launcher's gateway list. |
| `RELAY_TOKEN` | Shared token every launcher presents. Generate one with `openssl rand -hex 32`. The relay will not start without it. |

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

Point a DNS **A record** at your `PUBLIC_IP` (DNS-only; do not proxy it, the
protocol is raw TCP, not HTTP).

## 4. TLS certificate (required)

The relay and the map server both serve TLS and will not start without a
certificate. The launcher pins the certificate's public key, so a self-signed
one is enough and no public CA is involved. Do this before step 2:

```bash
mkdir -p tls
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
  -subj "/CN=your.server.example" -addext "subjectAltName=DNS:your.server.example" \
  -keyout tls/privkey.pem -out tls/fullchain.pem
# the containers run as uid 1000 and read these through a read-only mount
sudo chown 1000 tls/privkey.pem && chmod 0400 tls/privkey.pem
```

The pin your players' launchers need (`certPin` in `wc3-launcher.json`, or
`--cert-pin`) is the SHA-256 of that public key:

```bash
openssl x509 -in tls/fullchain.pem -pubkey -noout \
  | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
```

Both gates are on by default. `RELAY_REQUIRE_TLS=0` and `RELAY_REQUIRE_AUTH=0`
turn them off, and exist for a local test, not for a server on the internet.

Accounts: in-client signup is open by default so friends can register. Once
they have, set `PVPGN_NEW_ACCOUNTS=false` and restart pvpgn.

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

HTTPS is required (launchers only sync over TLS). The map server reuses the
relay's certificate through `MAPD_TLS_CERT` / `MAPD_TLS_KEY`, which already
point at the mounted `/tls` paths, and the launcher pins the same key.

## 6. Point the launcher at it

Give your friends the [wc3-launcher](https://github.com/PjSalty/wc3-launcher)
release. On first run it asks for the server address (your DNS name) and, if you
set one, the relay token. That's it.
