#!/bin/bash
# 组装 TimingBomb.app（release 产物 + Info.plist + 资源 + ad-hoc 签名）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${TB_VERSION:-0.1.0}"
APP_NAME="TimingBomb.app"
ROOT="$(pwd)"
BUILD="$ROOT/.build/release"
STAGING="$ROOT/dist/app-staging"

echo "==> release build"
swift build -c release

echo "==> assemble $APP_NAME"
rm -rf "$STAGING"
mkdir -p "$STAGING/$APP_NAME/Contents/MacOS" "$STAGING/$APP_NAME/Contents/Resources"

cp "$BUILD/tb" "$BUILD/timingbombd" "$BUILD/TimingBombApp" "$BUILD/jsrunner" "$STAGING/$APP_NAME/Contents/MacOS/"
cp -R "$ROOT/Skills" "$STAGING/$APP_NAME/Contents/Resources/Skills"
cp -R "$ROOT/examples" "$STAGING/$APP_NAME/Contents/Resources/examples"
cp "$ROOT/README.md" "$STAGING/$APP_NAME/Contents/Resources/"
cp "$ROOT/Resources/Icons/AppIcon.icns" "$STAGING/$APP_NAME/Contents/Resources/"
cp "$ROOT/Resources/Icons/"*Template*.png "$STAGING/$APP_NAME/Contents/Resources/"

cat > "$STAGING/$APP_NAME/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>TimingBomb</string>
    <key>CFBundleExecutable</key>
    <string>TimingBombApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.timingbomb.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TimingBomb</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
for binary in tb timingbombd TimingBombApp; do
    codesign --force --sign - --timestamp=none "$STAGING/$APP_NAME/Contents/MacOS/$binary"
done
codesign --force --sign - --timestamp=none "$STAGING/$APP_NAME"

echo "==> done: $STAGING/$APP_NAME (v$VERSION)"
