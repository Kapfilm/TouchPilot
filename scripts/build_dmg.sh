#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
APP="$ROOT/build/TouchPilot.app"
DMG="$ROOT/build/TouchPilot-${VERSION}.dmg"
STAGING="$ROOT/build/dmg-staging"

"$ROOT/scripts/build_app.sh"

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/TouchPilot.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"

hdiutil create \
  -volname "TouchPilot ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGING"
echo "$DMG"
