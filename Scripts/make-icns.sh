#!/bin/bash
# 由 Resources/icon-1024.png 生成 Resources/Tidepool.icns
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="Resources/icon-1024.png"
ICONSET="build/Tidepool.iconset"

if [ ! -f "$MASTER" ]; then
    swift Scripts/make-icon.swift
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16 "$MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o Resources/Tidepool.icns
echo "wrote Resources/Tidepool.icns"
