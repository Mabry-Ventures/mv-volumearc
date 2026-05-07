#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
  if ! /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
    echo "FAIL: $label codesign verification failed at $bundle" >&2
    /usr/bin/codesign --verify --deep --strict "$bundle" >&2 || true
    exit 1
  fi
}

require_watch_assets_car() {
  local assets_car="$1"
  if [[ ! -f "$assets_car" ]]; then
    echo "FAIL: missing compiled watch Assets.car at $assets_car" >&2
    exit 1
  fi

  /usr/bin/xcrun assetutil --info "$assets_car" |
    /usr/bin/ruby -rjson -e '
      records = JSON.parse(STDIN.read)
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
    '
}

require_dir "$APP_BUNDLE" "VolumeArc app bundle"
require_dir "$WATCH_BUNDLE" "embedded watch app"
require_dir "$WATCH_WIDGET_BUNDLE" "embedded watch widget extension"

require_plist_value "VolumeArcAIRelayURL" "$EXPECTED_RELAY_URL" "$APP_BUNDLE/Info.plist"
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

require_codesign "$APP_BUNDLE" "VolumeArc app"
require_codesign "$WATCH_BUNDLE" "VolumeArc watch app"
require_codesign "$WATCH_WIDGET_BUNDLE" "VolumeArc watch widget"
require_watch_assets_car "$WATCH_ASSETS_CAR"

echo "Exported IPA contract OK: watch app/widget embedded, relay config patched, signing valid, watch AppIcon renditions compiled."
