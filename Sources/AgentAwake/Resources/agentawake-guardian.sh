#!/bin/bash

set -euo pipefail

LEASE_DIR="${1:-}"
OWNER_PID="${2:-}"
OWNER_UID="${3:-}"
BATTERY_FLOOR="${4:-20}"
MAX_SECONDS="${5:-43200}"

HEARTBEAT_FILE="${LEASE_DIR}/heartbeat"
STOP_FILE="${LEASE_DIR}/stop"
STATE_FILE="${LEASE_DIR}/state"
STARTED_AT="$(date +%s)"
ORIGINAL_SLEEP_DISABLED=0
FINISHED=0
FORCE_SLEEP=0
EXIT_REASON="guardian stopped"
INPUTS_VALIDATED=0
ACTIVATED=0

write_state() {
    local state="$1"
    local reason="$2"

    if [ "$INPUTS_VALIDATED" -eq 1 ] && [ ! -L "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
        printf 'state=%s\nreason=%s\nactivated=%s\n' \
            "$state" "$reason" "$ACTIVATED" > "$STATE_FILE"
    fi
}

fail() {
    write_state "error" "$1"
    printf 'AgentAwake guardian: %s\n' "$1" >&2
    exit 1
}

is_unsigned_integer() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

validate_inputs() {
    is_unsigned_integer "$OWNER_PID" || fail "invalid owner PID"
    is_unsigned_integer "$OWNER_UID" || fail "invalid owner UID"
    is_unsigned_integer "$BATTERY_FLOOR" || fail "invalid battery floor"
    is_unsigned_integer "$MAX_SECONDS" || fail "invalid maximum duration"

    [ "$BATTERY_FLOOR" -ge 5 ] && [ "$BATTERY_FLOOR" -le 80 ] \
        || fail "battery floor must be between 5 and 80"
    [ "$MAX_SECONDS" -ge 60 ] && [ "$MAX_SECONDS" -le 86400 ] \
        || fail "maximum duration must be between 60 and 86400 seconds"

    case "$LEASE_DIR" in
        "/private/var/tmp/agentawake.${OWNER_UID}."*) ;;
        *) fail "invalid lease directory" ;;
    esac

    [ -d "$LEASE_DIR" ] && [ ! -L "$LEASE_DIR" ] || fail "lease directory is unavailable"
    [ -f "$HEARTBEAT_FILE" ] && [ ! -L "$HEARTBEAT_FILE" ] || fail "heartbeat file is unavailable"
    [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] || fail "state file is unavailable"

    local directory_uid heartbeat_uid state_uid
    directory_uid="$(stat -f '%u' "$LEASE_DIR")"
    heartbeat_uid="$(stat -f '%u' "$HEARTBEAT_FILE")"
    state_uid="$(stat -f '%u' "$STATE_FILE")"
    [ "$directory_uid" = "$OWNER_UID" ] || fail "lease directory owner mismatch"
    [ "$heartbeat_uid" = "$OWNER_UID" ] || fail "heartbeat owner mismatch"
    [ "$state_uid" = "$OWNER_UID" ] || fail "state file owner mismatch"
    INPUTS_VALIDATED=1
}

read_sleep_disabled() {
    local value
    value="$(pmset -g 2>/dev/null | awk '/SleepDisabled/{print $2; found=1; exit} END{if(!found)print 0}')"
    case "$value" in
        1) printf '1\n' ;;
        *) printf '0\n' ;;
    esac
}

is_battery_floor_reached() {
    local line percent
    line="$(pmset -g batt 2>/dev/null | awk '/InternalBattery/{print; exit}')"
    [ -n "$line" ] || return 1
    printf '%s' "$line" | grep -q 'discharging' || return 1
    percent="$(printf '%s' "$line" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
    [ -n "$percent" ] && [ "$percent" -le "$BATTERY_FLOOR" ]
}

is_thermal_pressure_critical() {
    local limit
    limit="$(pmset -g therm 2>/dev/null \
        | awk -F'=' '/CPU_Speed_Limit/{gsub(/[^0-9]/,"",$2); print $2; exit}')"
    [ -n "$limit" ] && [ "$limit" -le 30 ]
}

heartbeat_expired() {
    local modified now
    modified="$(stat -f '%m' "$HEARTBEAT_FILE" 2>/dev/null || printf '0')"
    now="$(date +%s)"
    [ $((now - modified)) -gt 25 ]
}

finish() {
    [ "$FINISHED" -eq 0 ] || return 0
    FINISHED=1

    if [ "$ORIGINAL_SLEEP_DISABLED" -eq 1 ]; then
        pmset -a disablesleep 1 >/dev/null 2>&1 || true
    else
        pmset -a disablesleep 0 >/dev/null 2>&1 || true
    fi

    write_state "stopped" "$EXIT_REASON"

    if [ "$FORCE_SLEEP" -eq 1 ]; then
        pmset sleepnow >/dev/null 2>&1 || true
    fi
}

trap 'EXIT_REASON="guardian interrupted"; finish; exit 0' INT TERM HUP
trap 'finish' EXIT

validate_inputs
ORIGINAL_SLEEP_DISABLED="$(read_sleep_disabled)"
pmset -a disablesleep 1
ACTIVATED=1
write_state "active" "keep-awake active"

while :; do
    sleep 1

    if [ -e "$STOP_FILE" ]; then
        EXIT_REASON="사용자가 잠자기 방지를 껐습니다."
        break
    fi

    if ! kill -0 "$OWNER_PID" 2>/dev/null; then
        EXIT_REASON="AgentAwake가 종료되어 자동 해제했습니다."
        break
    fi

    if heartbeat_expired; then
        EXIT_REASON="앱 응답이 없어 자동 해제했습니다."
        break
    fi

    if [ "$(date +%s)" -ge $((STARTED_AT + MAX_SECONDS)) ]; then
        EXIT_REASON="최대 유지 시간에 도달해 자동 해제했습니다."
        break
    fi

    if is_battery_floor_reached; then
        EXIT_REASON="배터리 ${BATTERY_FLOOR}% 안전 기준에 도달해 자동 해제했습니다."
        break
    fi

    if is_thermal_pressure_critical; then
        EXIT_REASON="심각한 발열이 감지되어 Mac을 잠자기 상태로 전환했습니다."
        FORCE_SLEEP=1
        break
    fi
done

finish
trap - EXIT
exit 0
