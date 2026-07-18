#!/usr/bin/env bash
#
# Render the aura-bot config from env and launch the bot in the foreground so
# the container runtime supervises it and captures its console.
set -euo pipefail

: "${AURA_REALM_HOST:?set AURA_REALM_HOST to the pvpgn service name}"
: "${AURA_REALM_USERNAME:?set AURA_REALM_USERNAME}"
: "${AURA_REALM_PASSWORD:?set AURA_REALM_PASSWORD via env or your secret store}"
: "${AURA_PUBLIC_IP:?set AURA_PUBLIC_IP to the public WAN IP}"
: "${AURA_REALM_NAME:=MyRealm}"
: "${AURA_REALM_GAME_VERSION:=1.27}"
: "${AURA_MAP_TRANSFER_MAX_SIZE:=131072}"
: "${AURA_HOST_PORT:=6113}"
: "${AURA_JASS_DIR:=/var/lib/aura/jass}"

export AURA_REALM_HOST AURA_REALM_NAME AURA_REALM_USERNAME AURA_REALM_PASSWORD \
       AURA_PUBLIC_IP AURA_REALM_GAME_VERSION AURA_MAP_TRANSFER_MAX_SIZE \
       AURA_HOST_PORT AURA_JASS_DIR

# Render config.ini into the bot working dir. Re-rendered each start, so the
# realm password is never persisted to a volume.
envsubst < /opt/aura/config.ini.tmpl > /opt/aura/config.ini

# aura needs Warcraft III's common.j + blizzard.j (game data, user-supplied from
# a legitimate WC3 install: War3x.mpq -> Scripts/) to compile .w3x/.w3m maps, and
# hard-fails at init without them. These Blizzard files are NOT redistributable
# and are never shipped in this image. pvpgn serves the realm on its own, so
# instead of crash-looping, idle here until the files are dropped into
# AURA_JASS_DIR, then start the autohost bot. Self-activates with no restart.
if [ ! -f "${AURA_JASS_DIR}/common.j" ] || [ ! -f "${AURA_JASS_DIR}/blizzard.j" ]; then
  echo "[entrypoint] aura autohost idle: waiting for common.j + blizzard.j in ${AURA_JASS_DIR}"
  echo "[entrypoint] extract them from your OWN WC3 install (War3x.mpq -> Scripts/) to enable map hosting."
  echo "[entrypoint] the pvpgn realm is unaffected; players can host games peer-to-peer now."
  until [ -f "${AURA_JASS_DIR}/common.j" ] && [ -f "${AURA_JASS_DIR}/blizzard.j" ]; do
    sleep 30
  done
  echo "[entrypoint] jass files found, starting aura autohost."
fi

# aura reads config.ini from its working directory.
cd /opt/aura
exec ./aura
