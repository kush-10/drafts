#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Support/Info.plist")"
MINIMUM_OS="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$ROOT/Support/Info.plist")"
SIGNER="${SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"
OUTPUT="$ROOT/dist/releases/v$VERSION"
NAME="Drafts-$VERSION-universal"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a numeric x.y.z version in Support/Info.plist." >&2
    exit 1
fi
if [[ -n "$NOTARY_PROFILE" && "$SIGNER" == "-" ]]; then
    echo "Notarization requires SIGNING_IDENTITY to be a Developer ID Application identity." >&2
    exit 1
fi
mkdir -p "$ROOT/dist" "$OUTPUT"
for artifact in "$NAME.dmg" "$NAME.zip" SHA256SUMS.txt release-info.json; do
    if [[ -e "$OUTPUT/$artifact" ]]; then
        echo "Release artifact already exists: $OUTPUT/$artifact. Bump the version before packaging again." >&2
        exit 1
    fi
done

# This unique build directory keeps packaging separate from any running dist/Drafts.app.
STAGING="$(mktemp -d "$ROOT/dist/.package-$VERSION.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT
APP_OUTPUT_DIR="$STAGING/build" UNIVERSAL=1 "$ROOT/scripts/build-app.sh" release
APP="$STAGING/build/Drafts.app"
SIGNING="ad-hoc"
NOTARIZED=false

if [[ "$SIGNER" != "-" ]]; then SIGNING="certificate"; fi
if [[ -n "$NOTARY_PROFILE" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/notarize.zip"
    xcrun notarytool submit "$STAGING/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    NOTARIZED=true
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/$NAME.zip"
mkdir -p "$STAGING/volume"
ditto "$APP" "$STAGING/volume/Drafts.app"
ln -s /Applications "$STAGING/volume/Applications"
cp "$ROOT/Support/Install.txt" "$STAGING/volume/Install.txt"
cp "$ROOT/LICENSE" "$STAGING/volume/LICENSE.txt"
hdiutil create -volname "Drafts $VERSION" -fs HFS+ -srcfolder "$STAGING/volume" -format UDZO "$STAGING/$NAME.dmg"

if [[ "$SIGNER" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGNER" "$STAGING/$NAME.dmg"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$STAGING/$NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$STAGING/$NAME.dmg"
    xcrun stapler validate "$STAGING/$NAME.dmg"
fi

codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/Drafts" -verify_arch arm64
lipo "$APP/Contents/MacOS/Drafts" -verify_arch x86_64
hdiutil verify "$STAGING/$NAME.dmg"
cat > "$STAGING/release-info.json" <<EOF
{
  "version": "$VERSION",
  "minimumMacOS": "$MINIMUM_OS",
  "architectures": ["arm64", "x86_64"],
  "signing": "$SIGNING",
  "notarized": $NOTARIZED
}
EOF

pushd "$STAGING" > /dev/null
shasum -a 256 "$NAME.dmg" "$NAME.zip" release-info.json > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
popd > /dev/null
for artifact in "$NAME.dmg" "$NAME.zip" SHA256SUMS.txt release-info.json; do
    mv "$STAGING/$artifact" "$OUTPUT/$artifact"
done
echo "Release files: $OUTPUT"
if [[ "$NOTARIZED" == "false" ]]; then
    echo "PREVIEW: not notarized. Document macOS Gatekeeper's Open Anyway flow before distributing."
fi
