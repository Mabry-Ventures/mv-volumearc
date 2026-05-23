#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <VolumeArc.ipa> [expected-build-number]" >&2
  exit 2
fi

IPA_PATH="$1"
EXPECTED_BUILD="${2:-${EXPECTED_BUILD_NUMBER:-}}"
EXPECTED_RELAY_URL="${EXPECTED_RELAY_URL:-https://relay.volumearc.app}"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "FAIL: IPA not found at $IPA_PATH" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/volumearc-ipa-contract.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

/usr/bin/unzip -q "$IPA_PATH" -d "$TMP_DIR"

APP_BUNDLE="$TMP_DIR/Payload/VolumeArc.app"
WATCH_BUNDLE="$APP_BUNDLE/Watch/VolumeArcWatch.app"
WATCH_WIDGET_BUNDLE="$WATCH_BUNDLE/PlugIns/VolumeArcWatchWidgets.appex"
WATCH_ASSETS_CAR="$WATCH_BUNDLE/Assets.car"

require_dir() {
  local path="$1"
  local label="$2"
  if [[ ! -d "$path" ]]; then
    echo "FAIL: missing $label at $path" >&2
    exit 1
  fi
}

plist_value() {
  local key="$1"
  local plist="$2"
  /usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

require_plist_value() {
  local key="$1"
  local expected="$2"
  local plist="$3"
  local actual
  actual="$(plist_value "$key" "$plist")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected $key=$expected in $plist, got ${actual:-<empty>}" >&2
    exit 1
  fi
}

require_codesign() {
  local bundle="$1"
  local label="$2"
  local expected_team="${3:-}"
  if ! /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
    echo "FAIL: $label codesign verification failed at $bundle" >&2
    /usr/bin/codesign --verify --deep --strict "$bundle" >&2 || true
    exit 1
  fi

  local team_identifier
  team_identifier="$(/usr/bin/codesign -d --verbose=4 "$bundle" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
  if [[ -z "$team_identifier" ]]; then
    echo "FAIL: $label codesign TeamIdentifier missing at $bundle" >&2
    exit 1
  fi

  if [[ -n "$expected_team" && "$team_identifier" != "$expected_team" ]]; then
    echo "FAIL: $label codesign TeamIdentifier mismatch at $bundle: expected $expected_team, got $team_identifier" >&2
    exit 1
  fi

  LAST_TEAM_IDENTIFIER="$team_identifier"
}

require_watch_assets_car() {
  local assets_car="$1"
  if [[ ! -f "$assets_car" ]]; then
    echo "FAIL: missing compiled watch Assets.car at $assets_car" >&2
    exit 1
  fi

  local asset_info
  if ! asset_info="$(/usr/bin/xcrun assetutil --info "$assets_car" 2>&1)"; then
    echo "FAIL: unable to inspect compiled watch Assets.car at $assets_car" >&2
    printf "%s\n" "$asset_info" >&2
    exit 1
  fi

  printf "%s" "$asset_info" |
    /usr/bin/ruby -rjson -e '
      begin
        records = JSON.parse(STDIN.read)
      rescue JSON::ParserError => error
        warn "FAIL: unable to parse assetutil output for #{ARGV.fetch(0)}: #{error.message}"
        exit 1
      end
      icons = records.select { |record| record["AssetType"] == "Icon Image" && record["Name"] == "AppIcon" }
      required = {
        "marketing 1024x1024" => ->(record) { record["Idiom"] == "marketing" && record["PixelWidth"] == 1024 && record["PixelHeight"] == 1024 },
        "watch 48x48" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 48 && record["PixelHeight"] == 48 },
        "watch 55x55" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 55 && record["PixelHeight"] == 55 },
        "watch 58x58" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 58 && record["PixelHeight"] == 58 },
        "watch 80x80" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 80 && record["PixelHeight"] == 80 },
        "watch 87x87" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 87 && record["PixelHeight"] == 87 },
        "watch 88x88" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 88 && record["PixelHeight"] == 88 },
        "watch 100x100" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 100 && record["PixelHeight"] == 100 },
        "watch 172x172" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 172 && record["PixelHeight"] == 172 },
        "watch 196x196" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 196 && record["PixelHeight"] == 196 },
        "watch 216x216" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 216 && record["PixelHeight"] == 216 }
      }
      missing = required.keys.reject { |name| icons.any? { |record| required.fetch(name).call(record) } }
      if missing.any?
        warn "FAIL: compiled watch Assets.car missing AppIcon renditions: #{missing.join(", ")}"
        exit 1
      end
    ' "$assets_car"
}

require_extension_entry_point() {
  local bundle="$1"
  local label="$2"
  local executable_name
  executable_name="$(plist_value "CFBundleExecutable" "$bundle/Info.plist")"
  if [[ -z "$executable_name" ]]; then
    echo "FAIL: $label missing CFBundleExecutable in $bundle/Info.plist" >&2
    exit 1
  fi

  local executable_path="$bundle/$executable_name"
  if [[ ! -f "$executable_path" ]]; then
    echo "FAIL: $label missing executable at $executable_path" >&2
    exit 1
  fi

  local symbols
  local nm_bin="${NM_BIN:-/usr/bin/nm}"
  if ! symbols="$("$nm_bin" -m "$executable_path" 2>&1)"; then
    echo "FAIL: unable to inspect $label symbols at $executable_path" >&2
    printf "%s\n" "$symbols" >&2
    exit 1
  fi

  if ! /usr/bin/grep -Eq '(^|[[:space:]])_NSExtensionMain($|[[:space:]])' <<<"$symbols"; then
    echo "FAIL: $label executable must link with -e _NSExtensionMain; App Store Connect rejects extension binaries that enter through _main" >&2
    exit 1
  fi
}

require_dir "$APP_BUNDLE" "VolumeArc app bundle"
require_dir "$WATCH_BUNDLE" "embedded watch app"
require_dir "$WATCH_WIDGET_BUNDLE" "embedded watch widget extension"

require_plist_value "VolumeArcAIRelayURL" "$EXPECTED_RELAY_URL" "$APP_BUNDLE/Info.plist"

# VOL-196: if the relay URL is configured (release builds always have
# it set), the signing key must also be configured. Without the key,
# `AIRelayCoachProvider` installs but every coach request throws
# `relayUnavailable`, silently degrading cloud AI and live voice in
# TestFlight/App Store. Fail the IPA contract loudly so the
# misconfiguration cannot ship. The key value itself is never logged;
# we only confirm the Info.plist entry exists and is non-empty.
if [[ -n "$EXPECTED_RELAY_URL" ]]; then
  signing_key_value=$(plutil -extract VolumeArcRelaySigningKey raw -o - "$APP_BUNDLE/Info.plist" 2>/dev/null || true)
  if [[ -z "$signing_key_value" || "$signing_key_value" == "\$(VOLUMEARC_RELAY_SIGNING_KEY)" ]]; then
    echo "FAIL: VolumeArcRelaySigningKey is missing or unresolved in $APP_BUNDLE/Info.plist. Release builds must inject VOLUMEARC_RELAY_SIGNING_KEY before archive; without it, cloud AI and live voice silently degrade for every user. See ci_scripts/ci_post_clone.sh and docs/RELEASE.md (VOL-182)." >&2
    exit 1
  fi
fi
require_plist_value "CFBundleDisplayName" "VolumeArc" "$WATCH_BUNDLE/Info.plist"
require_plist_value "CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName" "AppIcon" "$WATCH_BUNDLE/Info.plist"
require_plist_value "CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles.0" "AppIcon" "$WATCH_BUNDLE/Info.plist"
require_plist_value "CFBundleDisplayName" "VolumeArc" "$WATCH_WIDGET_BUNDLE/Info.plist"
require_plist_value "NSExtension.NSExtensionPointIdentifier" "com.apple.widgetkit-extension" "$WATCH_WIDGET_BUNDLE/Info.plist"

if [[ -n "$EXPECTED_BUILD" ]]; then
  require_plist_value "CFBundleVersion" "$EXPECTED_BUILD" "$APP_BUNDLE/Info.plist"
  require_plist_value "CFBundleVersion" "$EXPECTED_BUILD" "$WATCH_BUNDLE/Info.plist"
  require_plist_value "CFBundleVersion" "$EXPECTED_BUILD" "$WATCH_WIDGET_BUNDLE/Info.plist"
fi

LAST_TEAM_IDENTIFIER=""
require_codesign "$APP_BUNDLE" "VolumeArc app" "${EXPECTED_TEAM_IDENTIFIER:-}"
APP_TEAM_IDENTIFIER="$LAST_TEAM_IDENTIFIER"
require_codesign "$WATCH_BUNDLE" "VolumeArc watch app" "$APP_TEAM_IDENTIFIER"
require_codesign "$WATCH_WIDGET_BUNDLE" "VolumeArc watch widget" "$APP_TEAM_IDENTIFIER"
require_extension_entry_point "$WATCH_WIDGET_BUNDLE" "VolumeArc watch widget"
require_watch_assets_car "$WATCH_ASSETS_CAR"

echo "Exported IPA contract OK: watch app/widget embedded, relay config patched, signing valid, watch widget entry point and AppIcon renditions compiled."
