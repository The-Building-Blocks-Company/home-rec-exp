#!/usr/bin/env bash
#
# build-dmg.sh — Archive, Developer ID sign, notarize, staple, and package
# Home Rec as a distributable .dmg. (BL-030–033)
#
# ⚠️ UNTESTED SCAFFOLD: this orchestrates the standard direct-distribution flow
# but has not been run. It requires an Apple Developer account, a Developer ID
# Application identity in your Keychain, and a stored notarytool profile. No
# secrets are embedded; everything sensitive comes from your environment/Keychain.
#
# Prerequisites:
#   - Xcode + command line tools
#   - create-dmg:  brew install create-dmg
#   - A Developer ID Application identity in Keychain
#   - A stored notarytool profile, created once with:
#       xcrun notarytool store-credentials "HomeRecNotary" \
#         --apple-id "you@example.com" --team-id "TEAMID" --password "<app-specific-pw>"
#
# Required environment variables:
#   TEAM_ID      Apple Developer Team ID (e.g. ABCDE12345)
#   AC_PROFILE   notarytool keychain profile name (e.g. HomeRecNotary)
#
# Usage:
#   TEAM_ID=ABCDE12345 AC_PROFILE=HomeRecNotary ./scripts/build-dmg.sh

set -euo pipefail

PROJECT="HomeRec/HomeRec.xcodeproj"
SCHEME="HomeRec"
APP_NAME="HomeRec"
CONFIG="Release"
DIST_DIR="$(pwd)/dist"
ARCHIVE="$DIST_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$DIST_DIR/export"
APP="$EXPORT_DIR/$APP_NAME.app"
DMG="$DIST_DIR/$APP_NAME.dmg"

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
: "${AC_PROFILE:?Set AC_PROFILE to your stored notarytool profile name}"

command -v create-dmg >/dev/null 2>&1 || {
  echo "error: create-dmg not found. Install with: brew install create-dmg" >&2
  exit 1
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Archiving ($CONFIG)…"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

echo "==> Exporting (Developer ID)…"
cat > "$DIST_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$DIST_DIR/ExportOptions.plist"

echo "==> Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing the app…"
ditto -c -k --keepParent "$APP" "$DIST_DIR/$APP_NAME.zip"
xcrun notarytool submit "$DIST_DIR/$APP_NAME.zip" --keychain-profile "$AC_PROFILE" --wait
xcrun stapler staple "$APP"

echo "==> Building DMG…"
create-dmg \
  --volname "Home Rec" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 175 190 \
  --app-drop-link 425 190 \
  "$DMG" \
  "$APP"

echo "==> Notarizing + stapling the DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$AC_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> Validating Gatekeeper acceptance…"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true

echo "==> Done: $DMG"
