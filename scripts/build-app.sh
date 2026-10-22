#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT/dist}"
SIGNER="${SIGNING_IDENTITY:--}"
cd "$ROOT"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 1
fi

BUILD_ARGS=(--configuration "$CONFIGURATION")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP="$OUTPUT_DIR/Drafts.app"
ICONSET="$OUTPUT_DIR/Drafts.iconset"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$BIN_DIR/Drafts" "$APP/Contents/MacOS/Drafts"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/Drafts.icns"
if [[ "$CONFIGURATION" == "release" ]]; then
    strip -S "$APP/Contents/MacOS/Drafts"
fi
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    lipo "$APP/Contents/MacOS/Drafts" -verify_arch arm64
    lipo "$APP/Contents/MacOS/Drafts" -verify_arch x86_64
fi
if [[ "$SIGNER" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGNER" "$APP"
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

echo "Built $APP"
echo "Launch with: open \"$APP\""
