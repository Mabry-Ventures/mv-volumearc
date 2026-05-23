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
INFO_PLIST="$ROOT/App/Info.plist"
INFO_PLIST_BACKUP=""

restore_info_plist() {
  if [[ -n "$INFO_PLIST_BACKUP" && -f "$INFO_PLIST_BACKUP" ]]; then
    cp "$INFO_PLIST_BACKUP" "$INFO_PLIST"
    rm -f "$INFO_PLIST_BACKUP"
  fi
}
trap restore_info_plist EXIT

patch_relay_signing_key() {
  if [[ -z "${VOLUMEARC_RELAY_SIGNING_KEY:-}" ]]; then
    echo "ERROR: Set VOLUMEARC_RELAY_SIGNING_KEY env var before creating a distribution archive." >&2
    echo "       It must match the Cloudflare Worker RELAY_SIGNING_KEY secret; otherwise TestFlight coach relay auth returns 401." >&2
    exit 1
  fi
  PLIST_ENV_NAME="VOLUMEARC_RELAY_SIGNING_KEY" /usr/bin/ruby <<'RUBY'
require "base64"

env_name = ENV.fetch("PLIST_ENV_NAME")
value = ENV.fetch(env_name, "")

if value.match?(/\s/)
  warn "ERROR: #{env_name} must be a single base64 value with no whitespace."
  exit 1
end

begin
  decoded = Base64.strict_decode64(value)
rescue ArgumentError
  warn "ERROR: #{env_name} must be valid standard base64."
  exit 1
end

if decoded.bytesize < 32
  warn "ERROR: #{env_name} must decode to at least 32 bytes."
  exit 1
end
RUBY

  INFO_PLIST_BACKUP="$(mktemp "${TMPDIR:-/tmp}/volumearc-info-plist.XXXXXX")"
  cp "$INFO_PLIST" "$INFO_PLIST_BACKUP"
  PLIST_KEY="VolumeArcRelaySigningKey" PLIST_ENV_NAME="VOLUMEARC_RELAY_SIGNING_KEY" /usr/bin/ruby - "$INFO_PLIST" <<'RUBY'
require "cgi"

path = ARGV.fetch(0)
key = ENV.fetch("PLIST_KEY")
env_name = ENV.fetch("PLIST_ENV_NAME")
value = CGI.escapeHTML(ENV.fetch(env_name))
xml = File.read(path)
pattern = %r{(<key>#{Regexp.escape(key)}</key>\s*<string>)(.*?)(</string>)}m

if xml.match?(pattern)
  xml = xml.sub(pattern) { "#{Regexp.last_match(1)}#{value}#{Regexp.last_match(3)}" }
else
  insert = "\n\t<key>#{CGI.escapeHTML(key)}</key>\n\t<string>#{value}</string>\n"
  xml = xml.sub(%r{\n</dict>}, "#{insert}</dict>")
end

File.write(path, xml)
RUBY
  echo "Patched VolumeArcRelaySigningKey into Info.plist for archive (len=${#VOLUMEARC_RELAY_SIGNING_KEY})"
}

echo "=== VolumeArc Archive ==="
echo "  Version:      $VERSION ($BUILD_NUMBER)"
echo "  Team:         $TEAM"
echo "  Archive path: $ARCHIVE_PATH"
echo ""

DEVELOPMENT_TEAM="$TEAM" BUILD_NUMBER="$BUILD_NUMBER" ruby "scripts/generate_xcode_project.rb"
patch_relay_signing_key

mkdir -p "$ARCHIVE_DIR" "$OUTPUT_DIR"

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcApp" \
  -destination "generic/platform=iOS" \
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
