# Native-host relay daemon for a private Warcraft III: The Frozen Throne server.
#
# Lets a player host a native Create Game with zero router config: the player's
# launcher opens one outbound tunnel here, the relay allocates a public port and
# proxies the player's realm connection to pvpgn (so pvpgn advertises this
# server's address as the game host), then fans joiner TCP down the tunnel to the
# player's Warcraft III.
#
# The source is the launcher's: cmd/wc3-relay and the packages under it live in
# github.com/PjSalty/wc3-launcher, next to the client that speaks the same
# protocol, and are built from a pinned release of it. This repo used to carry
# its own copy, and the copy fell behind.

FROM golang:1.27-trixie@sha256:2f84bc93ecfb2689f782b153fdcd368b5a7ab96c1386c65cdaccf35e726d6a44 AS build

# Pinned launcher release. The tag is for readability; the commit is the actual
# pin, asserted after the clone so a moved or re-pointed tag fails the build
# instead of silently changing the source. Keep it the same in ../mapd/Dockerfile.
ARG LAUNCHER_REF=v1.3.11
ARG LAUNCHER_SHA=0c01d6bcbe1da1e09fd7f86caaec61c6d374ecf7

ENV GOTOOLCHAIN=local GOFLAGS=-mod=readonly
WORKDIR /src
RUN git clone --depth 1 --branch "${LAUNCHER_REF}" \
      https://github.com/PjSalty/wc3-launcher.git . \
 && test "$(git rev-parse HEAD)" = "${LAUNCHER_SHA}"
RUN go mod download && go mod verify
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /wc3-relay ./cmd/wc3-relay

FROM debian:13-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
COPY --from=build /wc3-relay /usr/local/bin/wc3-relay
# Non-root; the daemon only needs to bind high ports (>1024) on the host network.
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/wc3-relay"]
