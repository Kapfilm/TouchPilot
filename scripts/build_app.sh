#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift scripts/make_original_coral_icon.swift Resources build/AppIcon.iconset

ASSET_CATALOG="$ROOT/build/TouchPilotAssets.xcassets"
ASSET_SET="$ASSET_CATALOG/AppIcon.appiconset"
ASSET_OUT="$ROOT/build/CompiledAssets"
rm -rf "$ASSET_CATALOG" "$ASSET_OUT"
mkdir -p "$ASSET_SET" "$ASSET_OUT"
cp "$ROOT/Resources/AppIconContents.json" "$ASSET_SET/Contents.json"
for file in "$ROOT"/build/AppIcon.iconset/*.png; do
  cp "$file" "$ASSET_SET/$(basename "$file")"
done
if command -v xcrun >/dev/null 2>&1; then
  xcrun actool "$ASSET_CATALOG" \
    --compile "$ASSET_OUT" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/build/asset-info.plist"
fi

swift build -c release

APP="$ROOT/build/TouchPilot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/TouchPilot" "$APP/Contents/MacOS/TouchPilot"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [ -f "$ASSET_OUT/Assets.car" ]; then
  cp "$ASSET_OUT/Assets.car" "$APP/Contents/Resources/Assets.car"
  cp "$ASSET_OUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

if command -v codesign >/dev/null 2>&1; then
  xattr -cr "$APP"
  codesign --force --deep --sign - --identifier local.touchpilot.app "$APP"
fi

echo "$APP"
