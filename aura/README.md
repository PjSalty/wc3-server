# aura

[Slayer95/aura-bot](https://github.com/Slayer95/aura-bot) autohost for a private
Warcraft III: The Frozen Throne PvPGN realm. Logs into the PvPGN server as a
client and hosts games, so players join hosted lobbies and never port-forward
their own game port.

Pinned to v10.0.0-dev, commit `0da186e` (2025-06-23). The image builds StormLib,
bncsutil, miniupnpc and cpr from the project's vendored deps (Discord/DPP
disabled), then aura itself, on debian:13.

## Game data (you supply it)

aura compiles maps against Warcraft III's `common.j` + `blizzard.j`, which are
Blizzard game data and are **never** shipped in this image. Extract them from
your OWN legitimate WC3 install (`War3x.mpq` -> `Scripts/`) and drop them into
the jass volume (`AURA_JASS_DIR`). Until then the container idles instead of
crash-looping; the pvpgn realm runs fine without it. You must own a legitimate
copy of Warcraft III: Reign of Chaos / The Frozen Throne.

## Config

`config/config.ini.tmpl` is rendered to `config.ini` at container start by
`entrypoint.sh` (envsubst). Only keys that differ from the upstream
`config-example.ini` are set. Everything is driven by env from the deploy compose:

| Env | Config key | Purpose | Default |
|-----|-----------|---------|---------|
| `AURA_REALM_HOST` | `realm_1.host_name` | the pvpgn service name/host | (required) |
| `AURA_REALM_NAME` | `realm_1.unique_name` | display name for the realm | `MyRealm` |
| `AURA_REALM_USERNAME` | `realm_1.username` | bot account (auto-registers) | (required) |
| `AURA_REALM_PASSWORD` | `realm_1.password` | bot password (env/secret store, never committed) | (required) |
| `AURA_REALM_GAME_VERSION` | `global_realm.game_version` | must match the version players run | `1.27` |
| `AURA_MAP_TRANSFER_MAX_SIZE` | `hosting.map_transfers.max_size` | in-lobby map transfer cap (KB) | `131072` |
| `AURA_HOST_PORT` | `net.host_port.only` | fixed host port for hosted games (forward it) | `6113` |
| `AURA_PUBLIC_IP` | `net.ipv4.public_address.value` | advertised so external players can join | (required) |
| `AURA_JASS_DIR` | `bot.jass_path` | where you drop `common.j` + `blizzard.j` | `/var/lib/aura/jass` |

Maps live in the `/var/lib/aura/maps` volume; drop `.w3x`/`.w3m` there, or let
EpicWar/WC3Maps auto-download populate it.

## Admin commands

Aura is administered by chat commands (trigger `.`) from an account listed in
`realm_1.admins`. See the upstream `COMMANDS.md` for the full set (host, load,
map, ban, kick, and autohost controls).

## Verification

The C++ build (StormLib + bncsutil + cpr + aura) is heavy and is verified by the
image build. Confirm the aura config filename and `net.host_port` behavior on
the first real run against your live PvPGN server. `AURA_REALM_GAME_VERSION`
must be set to whatever version your client bundle actually runs.
