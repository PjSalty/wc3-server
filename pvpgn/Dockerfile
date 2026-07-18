# pvpgn/Dockerfile
# PvPGN-PRO Battle.net emulator for a private Warcraft III: The Frozen Throne
# realm. Multi-stage: compile the pinned 1.99.7.2.1 source, then ship a slim
# runtime. Base pinned to Debian 13 (Trixie).

# ---- build stage ----------------------------------------------------------
FROM debian:13-slim AS build

# Pinned upstream release tag (github.com/pvpgn/pvpgn-server). No 'v' prefix.
ARG PVPGN_VERSION=1.99.7.2.1

# Build toolchain + PvPGN deps: zlib and Lua 5.1 (WITH_LUA). No MySQL/SQLite --
# a private realm uses the plain-file storage backend (the bnetd default).
RUN apt-get update \
 && apt-get install --no-install-recommends -y \
      build-essential \
      cmake \
      git \
      ca-certificates \
      zlib1g-dev \
      liblua5.1-0-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${PVPGN_VERSION}" \
      https://github.com/pvpgn/pvpgn-server.git .

# Upstream-documented invocation: install prefix + WITH_LUA (README).
# CMAKE_POLICY_VERSION_MINIMUM lets this 2018-era CMake project configure under
# the much newer CMake in Trixie without the legacy-minimum deprecation erroring.
RUN cmake -S . -B build \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/usr/local/pvpgn \
      -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -D WITH_LUA=true \
 && cmake --build build -j "$(nproc)" \
 && cmake --install build

# ---- runtime stage --------------------------------------------------------
FROM debian:13-slim AS runtime

LABEL org.opencontainers.image.title="pvpgn-wc3" \
      org.opencontainers.image.description="PvPGN-PRO private Battle.net server for Warcraft III: TFT" \
      org.opencontainers.image.version="1.99.7.2.1" \
      org.opencontainers.image.source="https://github.com/pvpgn/pvpgn-server"

# Runtime shared libs only: zlib, Lua 5.1, C++ runtime.
RUN apt-get update \
 && apt-get install --no-install-recommends -y \
      zlib1g \
      liblua5.1-0 \
      libstdc++6 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 1000 pvpgn \
 && useradd  --system --uid 1000 --gid 1000 --home-dir /usr/local/pvpgn \
      --shell /usr/sbin/nologin pvpgn

# Built server tree: sbin/bnetd, etc/pvpgn/*.conf, var/pvpgn/{users,clans,...}.
COPY --from=build /usr/local/pvpgn /usr/local/pvpgn

# Private-realm config overlay + entrypoint.
COPY conf/bnetd.conf.overrides /usr/local/pvpgn/etc/pvpgn/bnetd.conf.overrides
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# The runtime user owns writable state (account DB, logs) and the config the
# entrypoint patches in place. Binaries stay root-owned, read+exec only.
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && chown -R pvpgn:pvpgn /usr/local/pvpgn/etc /usr/local/pvpgn/var

USER pvpgn
WORKDIR /usr/local/pvpgn

# 6112/tcp = bnetd client port; 6200/tcp = w3route (WC3 matchmaking).
EXPOSE 6112/tcp 6200/tcp

# Account DB, clans, teams, logs. Mount a volume here to persist accounts
# across container restarts (must be writable by uid 1000).
VOLUME ["/usr/local/pvpgn/var/pvpgn"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
