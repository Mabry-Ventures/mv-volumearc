#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TEAM="${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM env var to your Apple team ID (e.g., A886EMZZW6)}"
VERSION="$(cat VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
ARCHIVE_DIR="$ROOT/build/archives"
OUTPUT_DIR="$ROOT/build/export"
ARCHIVE_PATH="$ARCHIVE_DIR/VolumeArc-${VERSION}-${BUILD_NUMBER}.xcarchive"
EXPORT_PLIST="$ROOT/scripts/ExportOptions.plist"

echo "=== VolumeArc Archive ==="
echo "  Version:      $VERSION ($BUILD_NUMBER)"
echo "  Team:         $TEAM"
echo "  Archive path: $ARCHIVE_PATH"
echo ""

DEVELOPMENT_TEAM="$TEAM" BUILD_NUMBER="$BUILD_NUMBER" ruby "scripts/generate_xcode_project.rb"

mkdir -p "$ARCHIVE_DIR" "$OUTPUT_DIR"

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcApp" \
  -sdk iphoneos \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Automatic \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

echo ""
echo "=== Exporting IPA ==="

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$OUTPUT_DIR"

DSYM_PATH="$ARCHIVE_PATH/dSYMs"
echo ""
echo "=== Archive Complete ==="
echo "  IPA:   $OUTPUT_DIR/"
echo "  dSYMs: $DSYM_PATH"
echo ""
echo "Upload to TestFlight:"
echo "  xcrun altool --upload-app -f \"$OUTPUT_DIR/VolumeArc.ipa\" -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
