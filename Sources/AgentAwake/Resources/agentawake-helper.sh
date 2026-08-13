#!/bin/bash

set -u

HELPER_VERSION=1
STATE_DIR="/private/var/run/agentawake-helper"
STATUS_FILE="${STATE_DIR}/status"
CONFIG_DIR="/Library/Application Support/AgentAwake"
ALLOWED_UID_FILE="${CONFIG_DIR}/allowed-uid"
RECOVERY_FILE="${CONFIG_DIR}/recovery-state"

ACTIVE_LEASE=""
ACTIVE_PID=""
BATTERY_FLOOR=20
MAX_SECONDS=43200
STARTED_AT=0
ORIGINAL_SLEEP_DISABLED=0
RUNNING=1

is_unsigned_integer() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

read_field() {
    local file="$1"
    local key="$2"
    awk -F= -v requested_key="$key" \
        '$1 == requested_key {print substr($0, index($0, "=") + 1); exit}' \
        "$file" 2>/dev/null
}

read_sleep_disabled() {
    local value
    value="$(pmset -g 2>/dev/null | awk '/SleepDisabled/{print $2; found=1; exit} END{if(!found)print 0}')"
    case "$value" in
        1) printf '1\n' ;;
        *) printf '0\n' ;;
    esac
}

restore_sleep_setting() {
    local original="$1"
    if [ "$original" = "1" ]; then
        pmset -a disablesleep 1 >/dev/null 2>&1 || true
    else
        pmset -a disablesleep 0 >/dev/null 2>&1 || true
    fi
}

write_state() {
    local state="$1"
    local reason="$2"
    local activated="$3"
    local state_file="${ACTIVE_LEASE}/state"

    if [ -n "$ACTIVE_LEASE" ] && [ -f "$state_file" ] && [ ! -L "$state_file" ]; then
        printf 'state=%s\nreason=%s\nactivated=%s\n' \
            "$state" "$reason" "$activated" > "$state_file" 2>/dev/null || true
    fi
}

write_helper_status() {
    local allowed_uid="$1"
    mkdir -p "$STATE_DIR"
    chmod 755 "$STATE_DIR"
    printf 'version=%s\nallowed_uid=%s\n' "$HELPER_VERSION" "$allowed_uid" > "$STATUS_FILE"
    chmod 644 "$STATUS_FILE"
}

recover_interrupted_session() {
    [ -f "$RECOVERY_FILE" ] || return 0

    local original
    original="$(read_field "$RECOVERY_FILE" "original_sleep_disabled")"
    case "$original" in
        0|1) restore_sleep_setting "$original" ;;
        *) restore_sleep_setting 0 ;;
    esac
    rm -f "$RECOVERY_FILE"
}

request_is_valid() {
    local lease="$1"
    local allowed_uid="$2"
    local request_file="${lease}/request"
    local heartbeat_file="${lease}/heartbeat"
    local state_file="${lease}/state"
    local owner_pid owner_uid battery_floor max_seconds process_uid

    case "$lease" in
        "/private/var/tmp/agentawake.${allowed_uid}."*) ;;
        *) return 1 ;;
    esac

    [ -d "$lease" ] && [ ! -L "$lease" ] || return 1
    [ "$(stat -f '%u' "$lease" 2>/dev/null)" = "$allowed_uid" ] || return 1
    [ ! -e "${lease}/stop" ] || return 1

    for file in "$request_file" "$heartbeat_file" "$state_file"; do
        [ -f "$file" ] && [ ! -L "$file" ] || return 1
        [ "$(stat -f '%u' "$file" 2>/dev/null)" = "$allowed_uid" ] || return 1
    done

    grep -qx 'state=requested' "$state_file" 2>/dev/null || return 1

    owner_pid="$(read_field "$request_file" "owner_pid")"
    owner_uid="$(read_field "$request_file" "owner_uid")"
    battery_floor="$(read_field "$request_file" "battery_floor")"
    max_seconds="$(read_field "$request_file" "max_seconds")"

    is_unsigned_integer "$owner_pid" || return 1
    is_unsigned_integer "$owner_uid" || return 1
    is_unsigned_integer "$battery_floor" || return 1
    is_unsigned_integer "$max_seconds" || return 1
    [ "$owner_uid" = "$allowed_uid" ] || return 1
    [ "$battery_floor" -ge 5 ] && [ "$battery_floor" -le 80 ] || return 1
    [ "$max_seconds" -ge 60 ] && [ "$max_seconds" -le 86400 ] || return 1

    process_uid="$(ps -o uid= -p "$owner_pid" 2>/dev/null | tr -d ' ')"
    [ "$process_uid" = "$allowed_uid" ] || return 1

    ACTIVE_LEASE="$lease"
    ACTIVE_PID="$owner_pid"
    BATTERY_FLOOR="$battery_floor"
    MAX_SECONDS="$max_seconds"
    return 0
}

activate_request() {
    ORIGINAL_SLEEP_DISABLED="$(read_sleep_disabled)"
    umask 077
    printf 'original_sleep_disabled=%s\n' "$ORIGINAL_SLEEP_DISABLED" > "$RECOVERY_FILE"
    chmod 600 "$RECOVERY_FILE"

    if ! pmset -a disablesleep 1 >/dev/null 2>&1; then
        write_state "error" "macOS 전원 설정을 변경하지 못했습니다." 0
        rm -f "$RECOVERY_FILE"
        ACTIVE_LEASE=""
        ACTIVE_PID=""
        return 1
    fi

    STARTED_AT="$(date +%s)"
    write_state "active" "keep-awake active" 1
    return 0
}

heartbeat_expired() {
    local heartbeat_file="${ACTIVE_LEASE}/heartbeat"
    local modified now
    modified="$(stat -f '%m' "$heartbeat_file" 2>/dev/null || printf '0')"
    now="$(date +%s)"
    [ $((now - modified)) -gt 25 ]
}

owner_is_running() {
    local process_uid
    process_uid="$(ps -o uid= -p "$ACTIVE_PID" 2>/dev/null | tr -d ' ')"
    [ -n "$process_uid" ] && [ "$process_uid" = "$(cat "$ALLOWED_UID_FILE" 2>/dev/null)" ]
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

finish_active_request() {
    local reason="$1"
    local force_sleep="$2"

    restore_sleep_setting "$ORIGINAL_SLEEP_DISABLED"
    rm -f "$RECOVERY_FILE"
    write_state "stopped" "$reason" 1

    if [ "$force_sleep" = "1" ]; then
        pmset sleepnow >/dev/null 2>&1 || true
    fi

    ACTIVE_LEASE=""
    ACTIVE_PID=""
    STARTED_AT=0
}

monitor_active_request() {
    if [ -f "${ACTIVE_LEASE}/stop" ]; then
        finish_active_request "사용자가 잠자기 방지를 껐습니다." 0
    elif ! owner_is_running; then
        finish_active_request "AgentAwake가 종료되어 자동 해제했습니다." 0
    elif heartbeat_expired; then
        finish_active_request "앱 응답이 없어 자동 해제했습니다." 0
    elif [ "$(date +%s)" -ge $((STARTED_AT + MAX_SECONDS)) ]; then
        finish_active_request "최대 유지 시간에 도달해 자동 해제했습니다." 0
    elif is_battery_floor_reached; then
        finish_active_request "배터리 ${BATTERY_FLOOR}% 안전 기준에 도달해 자동 해제했습니다." 0
    elif is_thermal_pressure_critical; then
        finish_active_request "심각한 발열이 감지되어 Mac을 잠자기 상태로 전환했습니다." 1
    fi
}

scan_for_request() {
    local allowed_uid="$1"
    local candidate
    for candidate in /private/var/tmp/agentawake."${allowed_uid}".*; do
        [ -d "$candidate" ] || continue
        if request_is_valid "$candidate" "$allowed_uid"; then
            activate_request || true
            return
        fi
    done
}

shutdown_helper() {
    RUNNING=0
}

trap 'shutdown_helper' INT TERM HUP

mkdir -p "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"
recover_interrupted_session

ALLOWED_UID="$(cat "$ALLOWED_UID_FILE" 2>/dev/null || true)"
if ! is_unsigned_integer "$ALLOWED_UID" || [ "$ALLOWED_UID" -eq 0 ]; then
    exit 78
fi
write_helper_status "$ALLOWED_UID"

while [ "$RUNNING" -eq 1 ]; do
    if [ -n "$ACTIVE_LEASE" ]; then
        monitor_active_request
    else
        scan_for_request "$ALLOWED_UID"
    fi
    touch "$STATUS_FILE" 2>/dev/null || true
    sleep 1
done

if [ -n "$ACTIVE_LEASE" ]; then
    finish_active_request "전원 도우미가 종료되어 자동 해제했습니다." 0
elif [ -f "$RECOVERY_FILE" ]; then
    recover_interrupted_session
fi

rm -f "$STATUS_FILE"
exit 0
