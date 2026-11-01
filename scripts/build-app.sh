#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
INSTALL_APP=0
if [[ -n "${APP_OUTPUT_DIR:-}" ]]; then
    OUTPUT_DIR="$APP_OUTPUT_DIR"
else
    mkdir -p "$ROOT/.build"
    OUTPUT_DIR="$(mktemp -d "$ROOT/.build/app-stage.XXXXXX")"
    INSTALL_APP=1
    trap 'rm -rf -- "$OUTPUT_DIR"' EXIT
fi
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
# Remove only the retired, generated embedding assets from an earlier build.
python3 - "$APP" <<'PY'
import pathlib, shutil, sys
app = pathlib.Path(sys.argv[1])
targets = [app / 'Contents/Resources/Intelligence']
helpers = app / 'Contents/Helpers'
targets += [helpers / name for name in ['DraftsTopicModel', 'mlx.metallib', 'mlx-swift_Cmlx.bundle', 'swift-crypto_Crypto.bundle', 'swift-transformers_Hub.bundle']]
for target in targets:
    if target.is_symlink() or target.is_file():
        target.unlink()
    elif target.exists():
        shutil.rmtree(target)
if helpers.exists() and not any(helpers.iterdir()):
    helpers.rmdir()
PY
HELPER="$APP/Contents/MacOS/DraftsTopicModel"
cp "$BIN_DIR/DraftsTopicModel" "$HELPER"
for bundle in "$BIN_DIR"/*.bundle(N); do
    ditto "$bundle" "$APP/Contents/Resources/${bundle:t}"
done
install -m 644 "$ROOT/.build/checkouts/mlx-swift/LICENSE" "$APP/Contents/Resources/MLX-LICENSE.txt"
install -m 644 "$ROOT/.build/checkouts/mlx-swift-lm/LICENSE" "$APP/Contents/Resources/MLX-LM-LICENSE.txt"
install -m 644 "$ROOT/.build/checkouts/swift-transformers/LICENSE" "$APP/Contents/Resources/Transformers-LICENSE.txt"
cp "$ROOT/Support/ThemeCredits.txt" "$APP/Contents/Resources/ThemeCredits.txt"
cp "$BIN_DIR/Drafts" "$APP/Contents/MacOS/Drafts"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/Drafts.icns"
if [[ "$CONFIGURATION" == "release" ]]; then
    strip -S "$APP/Contents/MacOS/Drafts"
    strip -S "$HELPER"
fi
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    lipo "$APP/Contents/MacOS/Drafts" -verify_arch arm64
    lipo "$APP/Contents/MacOS/Drafts" -verify_arch x86_64
fi
if [[ "$SIGNER" == "-" ]]; then
    codesign --force --sign - "$HELPER"
    for bundle in "$APP/Contents/Resources"/*.bundle(N); do codesign --force --sign - "$bundle"; done
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGNER" "$HELPER"
    for bundle in "$APP/Contents/Resources"/*.bundle(N); do codesign --force --timestamp --sign "$SIGNER" "$bundle"; done
    codesign --force --options runtime --timestamp --sign "$SIGNER" "$APP"
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

echo "Built $APP"
if [[ "$INSTALL_APP" == "1" ]]; then
    python3 "$ROOT/scripts/install-app.py" "$APP"
    echo 'Launch with: open /Applications/Drafts.app'
else
    echo "Launch with: open \"$APP\""
fi
