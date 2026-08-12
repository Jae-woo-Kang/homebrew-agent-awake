#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="${PROJECT_ROOT}/dist/AgentAwake.app"
APP_TARGET="/Applications/AgentAwake.app"

if [ ! -d "$APP_SOURCE" ]; then
    "$PROJECT_ROOT/scripts/build-app.sh"
fi

rm -rf "$APP_TARGET"
cp -R "$APP_SOURCE" "$APP_TARGET"
open "$APP_TARGET"

echo "Installed AgentAwake at $APP_TARGET"
