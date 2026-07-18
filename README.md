# wc3-server

A self-hostable, private Warcraft III: The Frozen Throne (classic, not Reforged)
server. It composes three open-source pieces so a group of friends can play
together over the internet:

- **pvpgn** - a Battle.net realm (login, chat, custom-game list) via PvPGN-PRO.
- **wc3-relay** - a native-host tunnel relay so a player can host a Create Game
  with no router config. Built from the separate
  [wc3-launcher](https://github.com/PjSalty/wc3-launcher) repo (`cmd/wc3-relay`).
- **aura** - an autohost bot that hosts lobbies for players who do not host their
  own.

Everything is configured from a single `.env` file. Nothing in this repo contains
a real server address, IP, secret, or registry: you supply those.

## Quick start

```bash
cd deploy
cp .env.example .env
# edit .env: at minimum set PUBLIC_IP, REALM_NAME, BOT_USERNAME, BOT_PASSWORD
docker compose up -d --build
```

Then forward the ports, point a DNS name at your public IP, and hand your friends
the [wc3-launcher](https://github.com/PjSalty/wc3-launcher) release pointed at
your server. Full instructions in **[deploy/README.md](deploy/README.md)**.

## What you provide

- A host with a public IP (a small VPS is plenty) and the ability to forward
  ports on your router or firewall.
- Your own Warcraft III game data (`common.j` + `blizzard.j` from your own
  install) if you want aura to host maps. This repo ships **no Blizzard files**;
  see [NOTICE](NOTICE).

## Legal

Open-source glue that builds PvPGN-PRO and aura-bot from their own upstream
sources and distributes no Blizzard binaries or game data. You must own Warcraft
III and supply your own game data. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
