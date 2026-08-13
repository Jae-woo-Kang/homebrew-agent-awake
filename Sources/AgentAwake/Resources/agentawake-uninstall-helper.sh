#!/bin/bash

set -u

LABEL="io.github.jaewookang.agentawake.helper"
CONFIG_DIR="/Library/Application Support/AgentAwake"
RECOVERY_FILE="${CONFIG_DIR}/recovery-state"
HELPER_PATH="/Library/PrivilegedHelperTools/${LABEL}.sh"
PLIST_PATH="/Library/LaunchDaemons/${LABEL}.plist"
STATE_DIR="/private/var/run/agentawake-helper"

if [ "$(id -u)" -ne 0 ]; then
    printf 'AgentAwake helper removal requires administrator access.\n' >&2
    exit 77
fi

launchctl bootout "system/${LABEL}" >/dev/null 2>&1 || true
sleep 1

if [ -f "$RECOVERY_FILE" ]; then
    original="$(awk -F= '$1 == "original_sleep_disabled" {print $2; exit}' "$RECOVERY_FILE")"
    if [ "$original" = "1" ]; then
        pmset -a disablesleep 1 >/dev/null 2>&1 || true
    else
        pmset -a disablesleep 0 >/dev/null 2>&1 || true
    fi
fi

rm -f "$HELPER_PATH"
rm -f "$PLIST_PATH"
rm -f "${CONFIG_DIR}/allowed-uid"
rm -f "$RECOVERY_FILE"
rm -f "${STATE_DIR}/status"
rmdir "$STATE_DIR" >/dev/null 2>&1 || true
rmdir "$CONFIG_DIR" >/dev/null 2>&1 || true
exit 0
