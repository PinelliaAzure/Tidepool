#!/bin/bash
# 构建 Tidepool.app（ad-hoc 本地签名，双击即可运行）
set -euo pipefail

# 纯 Command Line Tools 环境：macOS 27 SDK 的 SwiftUI 需要缺失的宏插件，
# 回退到 MacOSX26.5 SDK。安装了完整 Xcode 时不做处理。
CLT_SDKS="/Library/Developer/CommandLineTools/SDKs"
if [ -z "${SDKROOT:-}" ] && ! ls -d /Applications/Xcode*.app >/dev/null 2>&1; then
    for candidate in "$CLT_SDKS"/MacOSX26.5.sdk "$CLT_SDKS"/MacOSX26.sdk; do
        if [ -d "$candidate" ]; then
            export SDKROOT="$candidate"
            break
        fi
    done
fi

CONFIG="${1:-release}"
swift build -c "$CONFIG"

# 版本号单一来源：VERSION 文件；构建号取 git 提交数，可用环境变量覆盖。
VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || true)"
VERSION="${TIDEPOOL_VERSION:-${VERSION:-0.0.0}}"
BUILD_NUMBER="${TIDEPOOL_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

APP_DIR="build/Tidepool.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/$CONFIG/Tidepool" "$APP_DIR/Contents/MacOS/Tidepool"
if [ -f "Resources/Tidepool.icns" ]; then
    cp "Resources/Tidepool.icns" "$APP_DIR/Contents/Resources/Tidepool.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
    <key>CFBundleExecutable</key><string>Tidepool</string>
    <key>CFBundleIdentifier</key><string>dev.pinellia.tidepool</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Tidepool</string>
    <key>CFBundleDisplayName</key><string>Tidepool</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>Tidepool</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 pinellia</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "✅ 构建完成: $APP_DIR"
