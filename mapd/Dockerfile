# Map library daemon (wc3-mapd) for a private Warcraft III: The Frozen Throne server.
#
# Serves the curated map library read-only over HTTPS so players' launchers sync
# the same maps on startup, with no in-game download wait. There is NO upload
# path: the operator curates by dropping vetted .w3x/.w3m into the mounted /maps
# dir. A .w3x carries executable map script, so auto-accepting client uploads
# would let anyone poison every player's map folder; that path does not exist.
#
# The source is the launcher's: cmd/wc3-mapd and internal/maplib live in
# github.com/PjSalty/wc3-launcher, next to the client that reads the same
# manifest, and are built from a pinned release of it.

FROM golang:1.27-trixie@sha256:f18c3d73a184fb0582828510722e723b63a93f7188d11dd223d9be6f6880e65d AS build

# Pinned launcher release: the tag for readability, the commit as the actual pin.
# Keep it the same in ../relay/Dockerfile.
ARG LAUNCHER_REF=v1.3.11
ARG LAUNCHER_SHA=0c01d6bcbe1da1e09fd7f86caaec61c6d374ecf7

ENV GOTOOLCHAIN=local GOFLAGS=-mod=readonly
WORKDIR /src
RUN git clone --depth 1 --branch "${LAUNCHER_REF}" \
      https://github.com/PjSalty/wc3-launcher.git . \
 && test "$(git rev-parse HEAD)" = "${LAUNCHER_SHA}"
RUN go mod download && go mod verify
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /wc3-mapd ./cmd/wc3-mapd

FROM debian:13-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
COPY --from=build /wc3-mapd /usr/local/bin/wc3-mapd
# Non-root, same uid as the relay so it can read the shared /tls. Reads the
# read-only /maps mount and binds high port 7443.
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/wc3-mapd"]
