# Map library daemon (wc3-mapd) for a private Warcraft III: The Frozen Throne server.
#
# Serves the curated map library read-only over HTTPS so players' launchers sync
# the same maps on startup, with no in-game download wait. There is NO upload
# path: the operator curates by dropping vetted .w3x/.w3m into the mounted /maps
# dir. A .w3x carries executable map script, so auto-accepting client uploads
# would let anyone poison every player's map folder; that path does not exist.
#
# The Go source here (cmd/wc3-mapd + internal/maplib) is shared with the launcher
# client; keep the two copies in sync.

FROM golang:1.26-bookworm@sha256:1ecb7edf62a0408027bd5729dfd6b1b8766e578e8df93995b225dfd0944eb651 AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /wc3-mapd ./cmd/wc3-mapd

FROM debian:bookworm-slim
COPY --from=build /wc3-mapd /usr/local/bin/wc3-mapd
# Non-root, same uid as the relay so it can read the shared /certs. Reads the
# read-only /maps mount and binds high port 7443.
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/wc3-mapd"]
