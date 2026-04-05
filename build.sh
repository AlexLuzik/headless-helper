#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="HeadlessHelper"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
DMG_NAME="$APP_NAME-$VERSION"

echo "Building $APP_NAME v$VERSION..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
cp "Sources/$APP_NAME/Info.plist" "$CONTENTS/Info.plist"
cp "Sources/$APP_NAME/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "Sources/$APP_NAME/Resources/MenuBarIcon.png" "$RESOURCES/MenuBarIcon.png"
cp "Sources/$APP_NAME/Resources/MenuBarIcon@2x.png" "$RESOURCES/MenuBarIcon@2x.png"

for lang in en uk; do
    mkdir -p "$RESOURCES/${lang}.lproj"
    cp "Sources/$APP_NAME/Resources/${lang}.lproj/Localizable.strings" "$RESOURCES/${lang}.lproj/"
done

echo "Building click_helper..."
swiftc -O "Sources/$APP_NAME/Utilities/click_helper.swift" -o "$MACOS/click_helper"

chmod +x "$MACOS/$APP_NAME"
chmod +x "$MACOS/click_helper"

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Creating DMG..."
DMG_DIR="/tmp/$DMG_NAME"
rm -rf "$DMG_DIR" "$DMG_NAME.dmg"
mkdir -p "$DMG_DIR"
cp -r "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "Headless Helper" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_NAME.dmg" >/dev/null 2>&1
rm -rf "$DMG_DIR"

echo ""
echo "Built: $(pwd)/$APP_BUNDLE"
echo "  DMG: $(pwd)/$DMG_NAME.dmg"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "NOTE: Grant Accessibility permission in System Settings."
