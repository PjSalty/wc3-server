# pvpgn/Dockerfile
# PvPGN-PRO Battle.net emulator for a private Warcraft III: The Frozen Throne
# realm. Multi-stage: compile the hardened PvPGN-PRO source, then ship a slim
# runtime. Base pinned to Debian 13 (Trixie).
#
# The source is pvpgn-pro-hardened, a security-hardened fork of PvPGN-PRO that
# tracks upstream and adds the modern compiler mitigations (FORTIFY_SOURCE=3,
# stack protector, full RELRO, CET, PIE) plus fixes for memory-safety bugs found
# by fuzzing the bnet/w3route packet parsers. It is a drop-in for stock
# PvPGN-PRO: same bnetd, same config, same 6112/6200 ports, same behaviour, so
# only the build changes. bnetd parses untrusted network input straight off the
# internet, which is exactly where those mitigations pay off: a memory-safety
# bug becomes a crash the container restarts, not remote code execution.
#
# The fork's base is upstream master (fcdf00f), which is also upstream's current
# HEAD, so this carries the upstream commits made after the last tagged release.
#
# Rollback, two ways: to isolate the hardening, rebuild this same source with
# -D PVPGN_HARDENING=OFF and drop the checksec gate; to restore the previously
# deployed bits exactly, clone github.com/pvpgn/pvpgn-server at tag 1.99.7.2.1.
# For the running realm, rolling the deployed image tag back is the fast path.

# ---- build stage ----------------------------------------------------------
FROM debian:13-slim AS build

# Pinned hardened-fork release (github.com/PjSalty/pvpgn-pro-hardened). The tag
# is for readability; the commit is the actual pin, asserted after the clone so a
# moved or re-pointed tag fails the build instead of silently changing the source.
ARG PVPGN_HARDENED_REF=v0.1.1
ARG PVPGN_HARDENED_SHA=242e8465d21cc97643442f0b864f9df482e55709

# Build toolchain + PvPGN deps: zlib and Lua 5.1 (WITH_LUA). No MySQL/SQLite --
# a private realm uses the plain-file storage backend (the bnetd default).
# binutils + checksec back the mitigation gate below.
RUN apt-get update \
 && apt-get install --no-install-recommends -y \
      build-essential \
      cmake \
      git \
      ca-certificates \
      zlib1g-dev \
      liblua5.1-0-dev \
      binutils \
      checksec \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${PVPGN_HARDENED_REF}" \
      https://github.com/PjSalty/pvpgn-pro-hardened.git . \
 && test "$(git rev-parse HEAD)" = "${PVPGN_HARDENED_SHA}"

# Upstream-documented invocation: install prefix + WITH_LUA (README).
# PVPGN_HARDENING is the fork's mitigation switch (on by default); it is passed
# explicitly so the intent is visible here. CMAKE_POLICY_VERSION_MINIMUM lets
# this legacy CMake project configure under the much newer CMake in Trixie
# without the legacy-minimum deprecation erroring.
RUN cmake -S . -B build \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/usr/local/pvpgn \
      -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -D PVPGN_HARDENING=ON \
      -D WITH_LUA=true \
 && cmake --build build -j "$(nproc)" \
 && cmake --install build

# Fail the image build if the mitigations did not actually land in the binary,
# so a silently-unhardened bnetd can never reach the realm. Checks full RELRO,
# stack canary, PIE, non-exec stack, FORTIFY, and the x86 CET property note.
RUN bash test/checksec.sh /usr/local/pvpgn/sbin/bnetd

# ---- runtime stage --------------------------------------------------------
FROM debian:13-slim AS runtime

LABEL org.opencontainers.image.title="pvpgn-wc3" \
      org.opencontainers.image.description="Hardened PvPGN-PRO private Battle.net server for Warcraft III: TFT" \
      org.opencontainers.image.version="v0.1.1" \
      org.opencontainers.image.source="https://github.com/PjSalty/pvpgn-pro-hardened"

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
