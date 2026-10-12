# Native-host relay daemon for a private Warcraft III: The Frozen Throne server.
#
# Lets a player host a native Create Game with zero router config: the player's
# launcher opens one outbound tunnel here, the relay allocates a public port and
# proxies the player's realm connection to pvpgn (binding its source port so
# pvpgn advertises this server's IP:port as the game host), then fans joiner TCP
# down the tunnel to the player's Warcraft III.
#
# The Go source here (cmd/wc3-relay + internal/relay + internal/tunnel) is shared
# with the launcher client; keep the two copies in sync.

FROM golang:1.27-trixie@sha256:2f84bc93ecfb2689f782b153fdcd368b5a7ab96c1386c65cdaccf35e726d6a44 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /wc3-relay ./cmd/wc3-relay

FROM debian:13-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
COPY --from=build /wc3-relay /usr/local/bin/wc3-relay
# Non-root; the daemon only needs to bind high ports (>1024) on the host network.
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/wc3-relay"]
