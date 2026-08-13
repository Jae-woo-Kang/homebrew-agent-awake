#!/bin/bash

set -euo pipefail

HELPER_VERSION=1
LABEL="io.github.jaewookang.agentawake.helper"
ALLOWED_UID="${1:-}"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_SOURCE="${SOURCE_DIR}/agentawake-helper.sh"
PLIST_SOURCE="${SOURCE_DIR}/${LABEL}.plist"
CONFIG_DIR="/Library/Application Support/AgentAwake"
HELPER_PATH="/Library/PrivilegedHelperTools/${LABEL}.sh"
PLIST_PATH="/Library/LaunchDaemons/${LABEL}.plist"
STATUS_FILE="/private/var/run/agentawake-helper/status"

case "$ALLOWED_UID" in
    ''|*[!0-9]*) exit 64 ;;
esac
[ "$ALLOWED_UID" -gt 0 ] || exit 64
[ -f "$HELPER_SOURCE" ] && [ ! -L "$HELPER_SOURCE" ] || exit 66
[ -f "$PLIST_SOURCE" ] && [ ! -L "$PLIST_SOURCE" ] || exit 66

install -d -o root -g wheel -m 755 "$CONFIG_DIR"
install -d -o root -g wheel -m 755 "/Library/PrivilegedHelperTools"
install -d -o root -g wheel -m 755 "/Library/LaunchDaemons"
install -o root -g wheel -m 755 "$HELPER_SOURCE" "$HELPER_PATH"
install -o root -g wheel -m 644 "$PLIST_SOURCE" "$PLIST_PATH"

UID_TEMP="$(mktemp "${CONFIG_DIR}/.allowed-uid.XXXXXX")"
printf '%s\n' "$ALLOWED_UID" > "$UID_TEMP"
chown root:wheel "$UID_TEMP"
chmod 644 "$UID_TEMP"
mv -f "$UID_TEMP" "${CONFIG_DIR}/allowed-uid"

launchctl bootout "system/${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap system "$PLIST_PATH"
launchctl enable "system/${LABEL}"
launchctl kickstart -k "system/${LABEL}"

attempt=0
while [ "$attempt" -lt 10 ]; do
    if [ -f "$STATUS_FILE" ] \
        && grep -qx "version=${HELPER_VERSION}" "$STATUS_FILE" \
        && grep -qx "allowed_uid=${ALLOWED_UID}" "$STATUS_FILE"; then
        exit 0
    fi
    attempt=$((attempt + 1))
    sleep 1
done

exit 70
