# aura/Dockerfile
# Slayer95/aura-bot autohost for a private WC3:TFT realm. Multi-stage: compile
# the pinned commit against its vendored deps, then ship a slim runtime. Base
# pinned to Debian 13 (Trixie).
#
# NOTE: this C++ build (StormLib + bncsutil + miniupnpc + cpr + aura) is heavy
# and is verified by the CI build, not locally. DPP (Discord) is disabled to
# avoid its long build; the bot does not need Discord here.

# ---- build stage ----------------------------------------------------------
FROM debian:13-slim AS build

# Pinned to v10.0.0-dev, master commit as of 2025-06-23. No tagged releases
# upstream, so pin the SHA for reproducibility.
ARG AURA_REF=0da186eace1bf11aa1e819f831d98d69f4e85170

# Build deps per the project's BUILDING.md (Debian/Ubuntu line).
RUN apt-get update \
 && apt-get install --no-install-recommends -y \
      ca-certificates git build-essential m4 cmake curl \
      libgmp3-dev libssl-dev libbz2-dev zlib1g-dev libcurl4-openssl-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
# deps/ (StormLib, bncsutil, miniupnpc, pjass) are vendored in-tree at this ref,
# not git submodules (no .gitmodules exists), so a plain clone+checkout is
# complete. The test asserts the tree is intact instead of silently swallowing
# an incomplete clone.
RUN git clone https://github.com/Slayer95/aura-bot.git . \
 && git checkout "${AURA_REF}" \
 && test -f deps/StormLib/CMakeLists.txt

# Vendored deps, built and installed in the order BUILDING.md specifies.
RUN cd deps/StormLib && mkdir -p build && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=1 .. \
 && make -j"$(nproc)" && make install
RUN cd deps/bncsutil/src/bncsutil && make -j"$(nproc)" && make install
RUN cd deps/miniupnpc && make -j"$(nproc)" && make install
RUN git clone https://github.com/libcpr/cpr.git /tmp/cpr && cd /tmp/cpr \
 && mkdir -p build && cd build \
 && cmake .. -DCPR_USE_SYSTEM_CURL=ON -DBUILD_SHARED_LIBS=1 \
 && cmake --build . --parallel && cmake --install .
RUN ldconfig

# Fork patch: the JoinStrings instantiation macro takes a single param T, but is
# invoked with comma-containing template types like array<string, 2>, which the
# preprocessor splits into two args -> "macro passed 2 arguments, but takes just
# 1" under Debian 13's GCC. Make the macro variadic so the whole type (commas
# included) is forwarded intact. The grep asserts the patch landed.
RUN sed -i \
      -e 's/#define INSTANTIATE_JOIN_STRINGS_IMPL(T)/#define INSTANTIATE_JOIN_STRINGS_IMPL(...)/' \
      -e 's/JoinStrings(const T& list/JoinStrings(const __VA_ARGS__\& list/g' \
      src/util.cpp \
 && grep -q 'INSTANTIATE_JOIN_STRINGS_IMPL(\.\.\.)' src/util.cpp

# Build Aura itself with Discord (DPP) disabled. WFLAGS=-fpermissive downgrades
# the legacy-code strictness errors (out-of-line static member linkage, etc.)
# that Debian 13's GCC rejects but the upstream's older toolchain accepted;
# WFLAGS is an unused Makefile hook injected into CXXFLAGS, so -std=c++17 and the
# other flags are preserved.
RUN export AURABUILD_DPP=0 \
 && make -j"$(nproc)" WFLAGS=-fpermissive \
 && test -x ./aura

# ---- runtime stage --------------------------------------------------------
FROM debian:13-slim AS runtime

LABEL org.opencontainers.image.title="aura-bot" \
      org.opencontainers.image.description="Slayer95/aura-bot autohost for a private WC3:TFT PvPGN realm" \
      org.opencontainers.image.version="10.0.0-dev-20250623" \
      org.opencontainers.image.source="https://github.com/Slayer95/aura-bot"

RUN apt-get update \
 && apt-get install --no-install-recommends -y \
      libgmp10 libssl3 libbz2-1.0 zlib1g libcurl4 libstdc++6 gettext-base ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 1000 aura \
 && useradd  --system --uid 1000 --gid 1000 --home-dir /opt/aura \
      --shell /usr/sbin/nologin aura

# Installed shared libs from the build stage. StormLib + cpr use cmake and land
# in /usr/local/lib; bncsutil + miniupnpc use raw `make install` and land in
# /usr/lib, so both paths must be copied or aura fails at runtime with
# "libbncsutil.so: cannot open shared object file".
COPY --from=build /usr/local/lib/ /usr/local/lib/
COPY --from=build /usr/lib/libbncsutil.so /usr/lib/libminiupnpc.so.18 /usr/lib/
COPY --from=build /src/aura /opt/aura/aura
# Ship the upstream defaults so the overlay only sets what differs.
COPY --from=build /src/config-example.ini /opt/aura/config-example.ini
COPY --from=build /src/aliases.ini /opt/aura/aliases.ini

COPY config/config.ini.tmpl /opt/aura/config.ini.tmpl
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /opt/aura/aura \
 && mkdir -p /var/lib/aura/maps /var/lib/aura/config /var/lib/aura/jass \
 && chown -R aura:aura /opt/aura /var/lib/aura \
 && ldconfig

USER aura
WORKDIR /opt/aura

VOLUME ["/var/lib/aura/maps", "/var/lib/aura/config", "/var/lib/aura/jass"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
