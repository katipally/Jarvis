#!/bin/bash
# Build, sign, notarize, and staple Jarvis for distribution.
# Requires: a "Developer ID Application" certificate, and notarytool credentials
# stored once via:
#   xcrun notarytool store-credentials jarvis-notary \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Usage: DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
set -euo pipefail

cd "$(dirname "$0")/.."
: "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application: …' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-jarvis-notary}"

echo "› Generating project"
xcodegen generate

echo "› Building Release"
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    clean build

APP="build/Build/Products/Release/Jarvis.app"
[ -d "$APP" ] || { echo "Build failed: $APP not found"; exit 1; }

echo "› Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "› Creating DMG"
DMG="build/Jarvis.dmg"
rm -f "$DMG"
hdiutil create -volname "Jarvis" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "› Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "› Stapling"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

echo "✓ Done: $DMG"
echo "  Verify on a clean machine: spctl -a -t open --context context:primary-signature -v \"$DMG\""
