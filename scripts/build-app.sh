#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
BUILD_ROOT="${PROJECT_ROOT}/.build-universal"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_DIR="${DIST_DIR}/AgentAwake.app"
CONTENTS_DIR="${APP_DIR}/Contents"

rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

build_architecture() {
    local architecture="$1"
    local scratch_path="${BUILD_ROOT}/${architecture}"

    swift build \
        --package-path "$PROJECT_ROOT" \
        --configuration release \
        --arch "$architecture" \
        --scratch-path "$scratch_path"

    swift build \
        --package-path "$PROJECT_ROOT" \
        --configuration release \
        --arch "$architecture" \
        --scratch-path "$scratch_path" \
        --show-bin-path
}

ARM64_BIN_PATH="$(build_architecture arm64 | tail -1)"
X86_64_BIN_PATH="$(build_architecture x86_64 | tail -1)"

lipo -create \
    "$ARM64_BIN_PATH/AgentAwake" \
    "$X86_64_BIN_PATH/AgentAwake" \
    -output "$CONTENTS_DIR/MacOS/AgentAwake"

for script_name in agentawake-helper agentawake-install-helper agentawake-uninstall-helper; do
    install -m 755 \
        "$PROJECT_ROOT/Sources/AgentAwake/Resources/${script_name}.sh" \
        "$CONTENTS_DIR/Resources/${script_name}.sh"
    test -x "$CONTENTS_DIR/Resources/${script_name}.sh"
done

install -m 644 \
    "$PROJECT_ROOT/Sources/AgentAwake/Resources/io.github.jaewookang.agentawake.helper.plist" \
    "$CONTENTS_DIR/Resources/io.github.jaewookang.agentawake.helper.plist"
test -r "$CONTENTS_DIR/Resources/io.github.jaewookang.agentawake.helper.plist"

cp "$PROJECT_ROOT/packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"

if [ -n "${AGENTAWAKE_CODESIGN_IDENTITY:-}" ]; then
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$AGENTAWAKE_CODESIGN_IDENTITY" \
        "$APP_DIR"
else
    codesign --force --deep --sign - "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent \
    "$APP_DIR" \
    "$DIST_DIR/AgentAwake-${VERSION}.zip"

shasum -a 256 "$DIST_DIR/AgentAwake-${VERSION}.zip"
