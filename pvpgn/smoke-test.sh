#!/usr/bin/env bash
#
# Script: pvpgn/smoke-test.sh
# Description: Start the pvpgn service from deploy/docker-compose.yml, with the
#              sandbox it really runs under, and prove the realm comes up, takes
#              a handshake and a flood of malformed input, and logs nothing
#              fatal while doing it.
# Usage: pvpgn/smoke-test.sh <image>
#

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly COMPOSE_FILE="${SCRIPT_DIR}/../deploy/docker-compose.yml"
readonly PROJECT="wc3-smoke"
readonly CONTAINER="wc3-pvpgn" # the compose file's container_name
readonly BNET_PORT=16112
readonly W3ROUTE_PORT=16200

# =============================================================================
# FUNCTIONS
# =============================================================================

log() { printf '[smoke] %s\n' "$*"; }

die() {
    printf '[smoke] FAIL: %s\n' "$*" >&2
    docker logs "${CONTAINER}" 2>&1 | tail -n 25 >&2 || true
    exit 1
}

usage() {
    cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") <image>

Runs <image> as the pvpgn service of deploy/docker-compose.yml, so what is
tested is the compose file's own sandbox (read-only root, tmpfs, seccomp
profile, no capabilities), not a copy of its flags.

Example:
    $(basename "${BASH_SOURCE[0]}") ghcr.io/your-org/pvpgn:latest
EOF
}

compose() {
    IMAGE_REGISTRY="localhost/wc3-smoke" PVPGN_TAG="test" PUBLIC_IP="203.0.113.10" \
        PVPGN_BNET_PORT="${BNET_PORT}" PVPGN_W3ROUTE_PORT="${W3ROUTE_PORT}" \
        PVPGN_NEW_ACCOUNTS="false" \
        docker compose -p "${PROJECT}" -f "${COMPOSE_FILE}" "$@"
}

cleanup() {
    compose down --volumes >/dev/null 2>&1 || true
    docker image rm localhost/wc3-smoke/pvpgn:test >/dev/null 2>&1 || true
}

port_open() {
    (exec 3<> "/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# Send a bnet init byte with a SID_AUTH_INFO-shaped packet, then malformed bytes
# at both listeners. The body is random, so the server may answer, stay quiet or
# drop the connection; only the daemon dying is a failure, and that is checked
# after this returns.
talk() {
    python3 - "${BNET_PORT}" "${W3ROUTE_PORT}" << 'PY'
import os
import socket
import sys


def send(port, payload):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=4) as s:
            s.sendall(payload)
            s.settimeout(2)
            try:
                s.recv(256)
            except (socket.timeout, ConnectionError):
                pass
    except ConnectionError:
        pass


bnet, w3route = int(sys.argv[1]), int(sys.argv[2])
body = b"\x50\x00\x00\x00" + os.urandom(60)
send(bnet, b"\x01" + body[:2] + len(body).to_bytes(2, "little") + body[4:])
for port in (bnet, w3route):
    for payload in (b"\x01" + os.urandom(3072), b"\xff" * 4000, os.urandom(1500), b"\x01\xff\xff\xff\xff"):
        send(port, payload)
PY
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        [[ $# -eq 1 ]] && exit 0
        exit 2
    fi
    local image="$1"

    trap cleanup EXIT
    docker tag "${image}" localhost/wc3-smoke/pvpgn:test
    log "starting the pvpgn service from ${COMPOSE_FILE}"
    compose up -d --no-build --no-deps pvpgn >/dev/null

    local i
    for i in $(seq 1 30); do
        port_open "${BNET_PORT}" && break
        [[ "${i}" -lt 30 ]] || die "the bnet port never came up"
        sleep 0.5
    done
    log "bnet port is up"

    talk
    sleep 1

    [[ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}")" == "true" ]] \
        || die "the daemon exited after a handshake and malformed input"
    port_open "${BNET_PORT}" || die "the bnet port stopped serving"
    log "the daemon survived a handshake and malformed input on both ports"

    # A daemon can stay up while part of it is dead: a syscall the profile denies,
    # or a write the read-only root refuses, shows up in the log, not as an exit.
    local problems
    problems="$(docker logs "${CONTAINER}" 2>&1 | grep -E '\[fatal\]|Operation not permitted|Read-only file system' || true)"
    [[ -z "${problems}" ]] || die "the sandbox broke something: ${problems}"
    log "nothing fatal, denied or refused in the log"

    docker exec "${CONTAINER}" grep -qx 'new_accounts = false' /run/pvpgn/bnetd.conf \
        || die "PVPGN_NEW_ACCOUNTS=false did not reach the running config"
    [[ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "${CONTAINER}")" == "true" ]] \
        || die "the container is not on a read-only root"
    docker exec "${CONTAINER}" grep -q '^Seccomp:[[:space:]]*2$' /proc/1/status \
        || die "no seccomp filter is applied to the daemon"
    log "read-only root, seccomp filter and the signup switch are all in effect"

    log "PASS"
}

main "$@"
