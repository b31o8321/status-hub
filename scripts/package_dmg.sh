#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/release}"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/StatusHub.app"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/StatusHub/Info.plist")
DMG_NAME="StatusHub-${VERSION}.dmg"
STAGING_DIR="$OUTPUT_DIR/staging"

rm -rf "$OUTPUT_DIR"
mkdir -p "$STAGING_DIR"

xcodebuild \
  -project "$ROOT_DIR/StatusHub.xcodeproj" \
  -scheme StatusHub \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CODE_SIGNING_ALLOWED=NO

cp -R "$APP_PATH" "$STAGING_DIR/StatusHub.app"
cp "$ROOT_DIR/docs/install.md" "$STAGING_DIR/安装说明.md"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "StatusHub" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DIR/$DMG_NAME"

echo "$OUTPUT_DIR/$DMG_NAME"

