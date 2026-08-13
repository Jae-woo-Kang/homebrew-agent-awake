#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="${PROJECT_ROOT}/dist/AgentAwake.app/Contents/Resources"
INSTALLER="${RESOURCES_DIR}/agentawake-install-helper.sh"
UNINSTALLER="${RESOURCES_DIR}/agentawake-uninstall-helper.sh"
OWNER_UID="$(id -u)"
OWNER_PID="$$"
LEASE_ONE=""
LEASE_TWO=""

cleanup() {
    if [ -n "$LEASE_ONE" ]; then
        touch "${LEASE_ONE}/stop" 2>/dev/null || true
    fi
    if [ -n "$LEASE_TWO" ]; then
        touch "${LEASE_TWO}/stop" 2>/dev/null || true
    fi
    sudo /bin/bash "$UNINSTALLER" >/dev/null 2>&1 || true
    if [ -n "$LEASE_ONE" ] && [ -d "$LEASE_ONE" ]; then
        rm -rf "$LEASE_ONE"
    fi
    if [ -n "$LEASE_TWO" ] && [ -d "$LEASE_TWO" ]; then
        rm -rf "$LEASE_TWO"
    fi
}
trap cleanup EXIT

create_request() {
    local lease
    lease="$(mktemp -d "/private/var/tmp/agentawake.${OWNER_UID}.XXXXXX")"
    chmod 700 "$lease"
    printf 'owner_pid=%s\nowner_uid=%s\nbattery_floor=20\nmax_seconds=120\n' \
        "$OWNER_PID" "$OWNER_UID" > "${lease}/request"
    printf 'starting\n' > "${lease}/heartbeat"
    printf 'state=requested\nreason=waiting\nactivated=0\n' > "${lease}/state"
    printf '%s\n' "$lease"
}

wait_for_state() {
    local lease="$1"
    local expected="$2"
    local attempt=0
    while [ "$attempt" -lt 20 ]; do
        if grep -qx "state=${expected}" "${lease}/state" 2>/dev/null; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    printf 'Timed out waiting for helper state %s. Current state:\n' "$expected" >&2
    cat "${lease}/state" >&2 || true
    return 1
}

sudo /bin/bash "$INSTALLER" "$OWNER_UID"
grep -qx 'version=1' /private/var/run/agentawake-helper/status
grep -qx "allowed_uid=${OWNER_UID}" /private/var/run/agentawake-helper/status

LEASE_ONE="$(create_request)"
wait_for_state "$LEASE_ONE" active
touch "${LEASE_ONE}/stop"
wait_for_state "$LEASE_ONE" stopped

# A second request must use the already-installed helper with no installer run.
LEASE_TWO="$(create_request)"
wait_for_state "$LEASE_TWO" active
touch "${LEASE_TWO}/stop"
wait_for_state "$LEASE_TWO" stopped
