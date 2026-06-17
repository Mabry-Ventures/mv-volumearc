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

require_plist_sentry_dsn() {
  local key="$1"
  local plist="$2"
  local actual
  actual="$(plist_value "$key" "$plist")"
  if [[ -z "$actual" || "$actual" == *'$('* ]]; then
    echo "FAIL: expected configured Sentry DSN in $plist, got ${actual:-<empty>}" >&2
    exit 1
  fi
  if [[ ! "$actual" =~ ^https://[^/@]+@[^/]+/.+ ]]; then
    echo "FAIL: expected HTTPS Sentry DSN URL with public key and project path in $plist, got $actual" >&2
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

extract_entitlements() {
  local bundle="$1"
  local label="$2"
  local output="$3"
  if ! /usr/bin/codesign -d --entitlements - --xml "$bundle" >"$output" 2>/dev/null || [[ ! -s "$output" ]]; then
    echo "FAIL: $label signed entitlements missing at $bundle" >&2
    exit 1
  fi
}

require_entitlement_string() {
  local entitlements="$1"
  local key="$2"
  local expected="$3"
  local label="$4"
  /usr/bin/python3 - "$entitlements" "$key" "$expected" "$label" <<'PY'
import plistlib
import sys

path, key, expected, label = sys.argv[1:5]
with open(path, "rb") as handle:
    entitlements = plistlib.load(handle)
actual = entitlements.get(key)
if actual != expected:
    print(f"FAIL: {label} signed entitlement {key} must be {expected!r}, got {actual!r}", file=sys.stderr)
    sys.exit(1)
PY
}

require_entitlement_bool_true() {
  local entitlements="$1"
  local key="$2"
  local label="$3"
  /usr/bin/python3 - "$entitlements" "$key" "$label" <<'PY'
import plistlib
import sys

path, key, label = sys.argv[1:4]
with open(path, "rb") as handle:
    entitlements = plistlib.load(handle)
actual = entitlements.get(key)
if actual is not True:
    print(f"FAIL: {label} signed entitlement {key} must be true, got {actual!r}", file=sys.stderr)
    sys.exit(1)
PY
}

require_entitlement_contains() {
  local entitlements="$1"
  local key="$2"
  local expected="$3"
  local label="$4"
  /usr/bin/python3 - "$entitlements" "$key" "$expected" "$label" <<'PY'
import plistlib
import sys

path, key, expected, label = sys.argv[1:5]
with open(path, "rb") as handle:
    entitlements = plistlib.load(handle)
actual = entitlements.get(key)

if isinstance(actual, str):
    matches = actual == expected
elif actual is None:
    matches = False
else:
    try:
        matches = expected in actual
    except TypeError:
        matches = False

if not matches:
    print(f"FAIL: {label} signed entitlement {key} missing {expected!r}; got {actual!r}", file=sys.stderr)
    sys.exit(1)
PY
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

  local asset_info_path="$TMP_DIR/watch-assets.json"
  printf "%s" "$asset_info" >"$asset_info_path"
  /usr/bin/python3 - "$assets_car" "$asset_info_path" <<'PY'
import json
import sys

assets_car = sys.argv[1]
asset_info_path = sys.argv[2]
try:
    with open(asset_info_path, "r", encoding="utf-8") as handle:
        records = json.load(handle)
except json.JSONDecodeError as error:
    print(f"FAIL: unable to parse assetutil output for {assets_car}: {error}", file=sys.stderr)
    sys.exit(1)

icons = [
    record for record in records
    if record.get("AssetType") == "Icon Image" and record.get("Name") == "AppIcon"
]
required = {
    "marketing 1024x1024": lambda record: record.get("Idiom") == "marketing" and record.get("PixelWidth") == 1024 and record.get("PixelHeight") == 1024,
    "watch 48x48": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 48 and record.get("PixelHeight") == 48,
    "watch 55x55": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 55 and record.get("PixelHeight") == 55,
    "watch 58x58": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 58 and record.get("PixelHeight") == 58,
    "watch 80x80": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 80 and record.get("PixelHeight") == 80,
    "watch 87x87": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 87 and record.get("PixelHeight") == 87,
    "watch 88x88": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 88 and record.get("PixelHeight") == 88,
    "watch 100x100": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 100 and record.get("PixelHeight") == 100,
    "watch 172x172": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 172 and record.get("PixelHeight") == 172,
    "watch 196x196": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 196 and record.get("PixelHeight") == 196,
    "watch 216x216": lambda record: record.get("Idiom") == "watch" and record.get("PixelWidth") == 216 and record.get("PixelHeight") == 216,
}
missing = [name for name, predicate in required.items() if not any(predicate(record) for record in icons)]
if missing:
    print(f"FAIL: compiled watch Assets.car missing AppIcon renditions: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)
PY
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

require_plist_sentry_dsn "VolumeArcSentryDSN" "$APP_BUNDLE/Info.plist"
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

LAST_TEAM_IDENTIFIER=""
require_codesign "$APP_BUNDLE" "VolumeArc app" "${EXPECTED_TEAM_IDENTIFIER:-}"
APP_TEAM_IDENTIFIER="$LAST_TEAM_IDENTIFIER"
require_codesign "$WATCH_BUNDLE" "VolumeArc watch app" "$APP_TEAM_IDENTIFIER"
require_codesign "$WATCH_WIDGET_BUNDLE" "VolumeArc watch widget" "$APP_TEAM_IDENTIFIER"

APP_ENTITLEMENTS="$TMP_DIR/VolumeArc.entitlements.plist"
WATCH_ENTITLEMENTS="$TMP_DIR/VolumeArcWatch.entitlements.plist"
extract_entitlements "$APP_BUNDLE" "VolumeArc app" "$APP_ENTITLEMENTS"
extract_entitlements "$WATCH_BUNDLE" "VolumeArc watch app" "$WATCH_ENTITLEMENTS"
require_entitlement_string "$APP_ENTITLEMENTS" "aps-environment" "production" "VolumeArc app"
require_entitlement_contains "$APP_ENTITLEMENTS" "com.apple.developer.icloud-container-identifiers" "iCloud.com.mabryventures.VolumeArc" "VolumeArc app"
require_entitlement_bool_true "$APP_ENTITLEMENTS" "com.apple.developer.healthkit" "VolumeArc app"
require_entitlement_contains "$APP_ENTITLEMENTS" "com.apple.security.application-groups" "group.com.mabryventures.volumearc" "VolumeArc app"
require_entitlement_bool_true "$WATCH_ENTITLEMENTS" "com.apple.developer.healthkit" "VolumeArc watch app"
require_entitlement_contains "$WATCH_ENTITLEMENTS" "com.apple.security.application-groups" "group.com.mabryventures.volumearc" "VolumeArc watch app"

require_extension_entry_point "$WATCH_WIDGET_BUNDLE" "VolumeArc watch widget"
require_watch_assets_car "$WATCH_ASSETS_CAR"

echo "Exported IPA contract OK: watch app/widget embedded, relay config patched, production entitlements signed, signing valid, watch widget entry point and AppIcon renditions compiled."
