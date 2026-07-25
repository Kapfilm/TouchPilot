#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
APP="$ROOT/build/TouchPilot.app"
DMG="$ROOT/build/TouchPilot-${VERSION}.dmg"
RW_DMG="$ROOT/build/TouchPilot-${VERSION}-rw.dmg"
STAGING="$ROOT/build/dmg-staging"
MOUNT_POINT="$ROOT/build/dmg-mount"
ATTACHED_DEVICE=""

cleanup() {
  if [ -n "$ATTACHED_DEVICE" ]; then
    hdiutil detach "$ATTACHED_DEVICE" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING" "$MOUNT_POINT"
  rm -f "$RW_DMG"
}
trap cleanup EXIT

"$ROOT/scripts/build_app.sh"

rm -rf "$STAGING" "$MOUNT_POINT"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/TouchPilot.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG" "$RW_DMG"
hdiutil create \
  -volname "TouchPilot ${VERSION}" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -ov \
  -format UDRW \
  "$RW_DMG"

mkdir -p "$MOUNT_POINT"
ATTACHED_DEVICE="$(
  hdiutil attach "$RW_DMG" \
    -mountpoint "$MOUNT_POINT" \
    -nobrowse \
    -readwrite |
    awk '/^\/dev\// { print $1; exit }'
)"

cp "$ROOT/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNT_POINT"
else
  xcrun SetFile -a C "$MOUNT_POINT"
fi
touch "$MOUNT_POINT/TouchPilot.app"
sync

hdiutil detach "$ATTACHED_DEVICE"
ATTACHED_DEVICE=""

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -o "$DMG"

echo "$DMG"
