#!/bin/bash
# 生成带 Applications 快捷方式的 DMG
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Tidepool.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

rm -rf build/dmg
mkdir -p build/dmg
ditto "$APP" "build/dmg/Tidepool.app"
ln -s /Applications "build/dmg/Applications"

hdiutil create \
    -volname "Tidepool" \
    -srcfolder "build/dmg" \
    -ov -format UDZO \
    "build/Tidepool-$VERSION.dmg" >/dev/null

echo "✅ build/Tidepool-$VERSION.dmg"
