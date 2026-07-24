# wc3-server

A self-hostable, private Warcraft III: The Frozen Throne (classic, not Reforged)
server. It composes three open-source pieces so a group of friends can play
together over the internet:

- **pvpgn** - a Battle.net realm (login, chat, custom-game list) via PvPGN-PRO.
- **wc3-relay** - a native-host tunnel relay so a player can host a Create Game
  with no router config: their launcher opens one outbound tunnel and the relay
  proxies joiners to them. Built here from `cmd/wc3-relay`.
- **wc3-mapd** - a read-only map library server so every player's launcher syncs
  the same curated maps on startup. Built here from `cmd/wc3-mapd`.

Everything is configured from a single `.env` file. Nothing in this repo contains
a real server address, IP, secret, or registry: you supply those.

## Quick start

```bash
cd deploy
cp .env.example .env
# edit .env: at minimum set PUBLIC_IP, REALM_NAME, RELAY_TOKEN
docker compose up -d --build
```

Then forward the ports, point a DNS name at your public IP, and hand your friends
the [wc3-launcher](https://github.com/PjSalty/wc3-launcher) release pointed at
your server. Full instructions in **[deploy/README.md](deploy/README.md)**.

## What you provide

- A host with a public IP (a small VPS is plenty) and the ability to forward
  ports on your router or firewall.
- Curated maps: drop your own vetted `.w3x`/`.w3m` files into the map library
  and every player's launcher syncs them.

Players need their own copy of Warcraft III; this repo ships **no Blizzard
files** and distributes no game data. See [NOTICE](NOTICE).

## Legal

Open-source glue that builds PvPGN-PRO from a hardened fork (GPL-2.0, source at
[PjSalty/pvpgn-pro-hardened](https://github.com/PjSalty/pvpgn-pro-hardened)) and
the relay and map daemons from `cmd/`, and distributes no Blizzard binaries or
game data. You must own Warcraft III. See [LICENSE](LICENSE) and
[NOTICE](NOTICE).
