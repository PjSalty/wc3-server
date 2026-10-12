#!/usr/bin/env bash
#
# Script: entrypoint.sh
# Description: Apply the private-server config overlay, wire NAT address
#              translation for the w3route port, then run bnetd in the
#              foreground for a private Warcraft III: The Frozen Throne realm.
# Usage: entrypoint.sh [extra bnetd args...]
#

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly PVPGN_PREFIX="/usr/local/pvpgn"
readonly BNETD_BIN="${PVPGN_PREFIX}/sbin/bnetd"
readonly OVERRIDES_FILE="${PVPGN_PREFIX}/etc/pvpgn/bnetd.conf.overrides"
readonly STATE_DIR="${PVPGN_PREFIX}/var/pvpgn"

# Where the config bnetd runs with is written. The installed tree is never
# edited, so the container runs on a read-only root filesystem: the compose file
# mounts a small tmpfs here. Without one the image's own directory is used.
readonly RUNTIME_DIR="${PVPGN_RUNTIME_DIR:-/run/pvpgn}"

# w3route port the WC3 clients reach for matchmaking (must match w3routeaddr).
readonly W3ROUTE_PORT="${PVPGN_W3ROUTE_PORT:-6200}"

# Public IP for NAT address translation. Empty = no translation (LAN/direct).
PVPGN_PUBLIC_IP="${PVPGN_PUBLIC_IP:-}"

# Comma-separated client networks that keep the internal (untranslated) w3route
# address. Defaults to the RFC1918 ranges so only genuinely external clients
# receive the public IP.
PVPGN_LOCAL_CIDR="${PVPGN_LOCAL_CIDR:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"

# Send the bnetd log to stdout (container console). false logs to
# ${LOCALSTATEDIR}/bnetd.log instead.
PVPGN_LOG_STDOUT="${PVPGN_LOG_STDOUT:-true}"

# The two overlay settings an operator changes without rebuilding. Empty keeps
# the overlay's value (new_accounts = true, track = 0).
#   PVPGN_NEW_ACCOUNTS  true|false  in-client account signup
#   PVPGN_TRACK         seconds     tracker announce interval, 0 = never announce
PVPGN_NEW_ACCOUNTS="${PVPGN_NEW_ACCOUNTS:-}"
PVPGN_TRACK="${PVPGN_TRACK:-}"

# =============================================================================
# FUNCTIONS
# =============================================================================

log() { printf '[entrypoint] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Locate the installed bnetd.conf: the pristine file the running config is
# copied from. It is read, never written.
find_conf() {
    local conf="${PVPGN_PREFIX}/etc/pvpgn/bnetd.conf"
    [[ -f "${conf}" ]] || conf="$(find "${PVPGN_PREFIX}" -type f -name bnetd.conf | head -n1)"
    [[ -n "${conf}" && -f "${conf}" ]] || die "bnetd.conf not found under ${PVPGN_PREFIX}"
    printf '%s' "${conf}"
}

# Idempotently set "key = value" in a pvpgn config file: replace the first
# matching (possibly commented) line, else append.
set_conf_key() {
    local file="$1" key="$2" value="$3"
    local line="${key} = ${value}"
    # shortcut: SOH delimiter keeps ':' '/' '"' in values sed-safe; swap to a
    # temp-file rewrite only if a value ever needs a literal SOH byte.
    local d=$'\001'
    if grep -Eq "^[#[:space:]]*${key}[[:space:]]*=" "${file}"; then
        # Rewritten through a variable, not sed -i: editing in place makes a temp
        # file and copies the original's attributes onto it, which takes syscalls
        # the seccomp profile has no other reason to allow.
        local out
        out="$(sed "s${d}^[#[:space:]]*${key}[[:space:]]*=.*${d}${line}${d}" "${file}")"
        printf '%s\n' "${out}" > "${file}"
    else
        printf '%s\n' "${line}" >> "${file}"
    fi
}

# Apply every "key = value" line from the overrides overlay into bnetd.conf.
apply_overrides() {
    local conf="$1"
    [[ -f "${OVERRIDES_FILE}" ]] || { log "no overrides file, keeping upstream defaults"; return; }
    local raw key value
    while IFS= read -r raw || [[ -n "${raw}" ]]; do
        raw="${raw%%#*}"                                # strip comments
        [[ "${raw}" =~ [^[:space:]] ]] || continue      # skip blank lines
        [[ "${raw}" == *"="* ]] || continue             # skip non key=value
        key="${raw%%=*}"
        key="$(printf '%s' "${key}" | tr -d '[:space:]')"
        value="${raw#*=}"
        value="${value#"${value%%[![:space:]]*}"}"      # ltrim
        value="${value%"${value##*[![:space:]]}"}"      # rtrim
        [[ -n "${key}" ]] || continue
        set_conf_key "${conf}" "${key}" "${value}"
        log "set ${key} = ${value}"
    done < "${OVERRIDES_FILE}"
}

# Apply PVPGN_NEW_ACCOUNTS / PVPGN_TRACK over the overlay. Both are validated:
# a typo must stop the container, not reach bnetd as a value it reads as "on".
apply_env_settings() {
    local conf="$1"
    case "${PVPGN_NEW_ACCOUNTS}" in
        "") ;;
        true|false)
            set_conf_key "${conf}" "new_accounts" "${PVPGN_NEW_ACCOUNTS}"
            log "set new_accounts = ${PVPGN_NEW_ACCOUNTS} (PVPGN_NEW_ACCOUNTS)"
            ;;
        *) die "PVPGN_NEW_ACCOUNTS must be true or false, got '${PVPGN_NEW_ACCOUNTS}'" ;;
    esac
    case "${PVPGN_TRACK}" in
        "") ;;
        *[!0-9]*) die "PVPGN_TRACK must be a whole number of seconds (0 = never announce), got '${PVPGN_TRACK}'" ;;
        *)
            set_conf_key "${conf}" "track" "${PVPGN_TRACK}"
            log "set track = ${PVPGN_TRACK} (PVPGN_TRACK)"
            ;;
    esac
}

# Point bnetd's transfile at a generated NAT mapping so remote clients receive
# the public IP for the w3route port while LAN clients keep the internal one.
configure_nat() {
    local conf="$1"
    local transfile="${RUNTIME_DIR}/address_translation.conf"

    if [[ -z "${PVPGN_PUBLIC_IP}" ]]; then
        log "PVPGN_PUBLIC_IP unset, no NAT translation (LAN/direct only)"
        return
    fi

    log "NAT: w3route 0.0.0.0:${W3ROUTE_PORT} -> ${PVPGN_PUBLIC_IP}:${W3ROUTE_PORT}"
    {
        printf '# generated by entrypoint.sh, do not edit by hand\n'
        printf '# input(ip:port)     output(ip:port)     exclude(net)     include(net)\n'
        local cidr
        local -a cidrs
        IFS=',' read -ra cidrs <<< "${PVPGN_LOCAL_CIDR}"
        for cidr in "${cidrs[@]}"; do
            cidr="$(printf '%s' "${cidr}" | tr -d '[:space:]')"
            [[ -n "${cidr}" ]] || continue
            printf '0.0.0.0:%s     %s:%s     %s     ANY\n' \
                "${W3ROUTE_PORT}" "${PVPGN_PUBLIC_IP}" "${W3ROUTE_PORT}" "${cidr}"
        done
    } > "${transfile}"

    set_conf_key "${conf}" "transfile" "\"${transfile}\""
}

# The ban list is the one file under etc/ that bnetd writes back (on /ipban and
# when it exits). Keep it with the rest of the state, so bans survive a restart
# and the config tree can stay read-only.
configure_banlist() {
    local conf="$1"
    local banfile="${STATE_DIR}/bnban.conf"
    if [[ ! -e "${banfile}" ]]; then
        cp "${PVPGN_PREFIX}/etc/pvpgn/bnban.conf" "${banfile}" 2>/dev/null \
            || log "warn: could not seed ${banfile}; bans will not persist until it is writable"
    fi
    set_conf_key "${conf}" "ipbanfile" "\"${banfile}\""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    [[ -x "${BNETD_BIN}" ]] || die "bnetd binary not found/executable at ${BNETD_BIN}"

    local installed conf
    installed="$(find_conf)"
    mkdir -p "${RUNTIME_DIR}" 2>/dev/null || true
    [[ -d "${RUNTIME_DIR}" && -w "${RUNTIME_DIR}" ]] \
        || die "${RUNTIME_DIR} is not writable by uid $(id -u); mount a tmpfs there (see deploy/docker-compose.yml)"
    conf="${RUNTIME_DIR}/bnetd.conf"
    cp "${installed}" "${conf}"
    log "using config ${conf} (from ${installed})"

    apply_overrides "${conf}"
    apply_env_settings "${conf}"

    if [[ "${PVPGN_LOG_STDOUT}" == "true" ]]; then
        set_conf_key "${conf}" "logfile" "\"/dev/stdout\""
        log "logging to stdout"
    fi

    configure_nat "${conf}"

    # Plain-file account store lives under var/pvpgn; make sure the dirs exist
    # (a mounted volume may start empty). var must be writable by this user.
    mkdir -p "${STATE_DIR}/users" \
             "${STATE_DIR}/clans" \
             "${STATE_DIR}/teams" 2>/dev/null \
        || log "warn: could not create var dirs (check mounted volume perms for uid 1000)"

    configure_banlist "${conf}"

    log "starting bnetd in foreground (-f)"
    # -f = do not daemonize, -c = explicit config path. exec so bnetd becomes
    # PID 1 and receives container signals directly.
    exec "${BNETD_BIN}" -f -c "${conf}" "$@"
}

main "$@"
