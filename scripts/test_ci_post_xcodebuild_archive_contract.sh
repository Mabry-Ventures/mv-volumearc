#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/volumearc-ci-post-xcodebuild.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_PATH="$TMP_DIR/Derived/VolumeArc.xcarchive"
APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/VolumeArc.app"
WATCH_BUNDLE="$APP_BUNDLE/Watch/VolumeArcWatch.app"
WATCH_WIDGET_BUNDLE="$WATCH_BUNDLE/PlugIns/VolumeArcWatchWidgets.appex"
DSYM_DIR="$ARCHIVE_PATH/dSYMs"
LOG_PATH="$TMP_DIR/ci_post_xcodebuild.log"
SENTRY_LOG="$TMP_DIR/sentry-cli.log"

mkdir -p "$WATCH_WIDGET_BUNDLE" "$DSYM_DIR/VolumeArc.app.dSYM" "$TMP_DIR/bin"

write_plist() {
  local path="$1"
  local build_number="$2"
  local relay_url="${3:-}"
  local extension_point="${4:-}"

  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    printf '<plist version="1.0">\n'
    printf '<dict>\n'
    printf '  <key>CFBundleVersion</key>\n'
    printf '  <string>%s</string>\n' "$build_number"
    if [[ -n "$relay_url" ]]; then
      printf '  <key>VolumeArcAIRelayURL</key>\n'
      printf '  <string>%s</string>\n' "$relay_url"
    fi
    if [[ -n "$extension_point" ]]; then
      printf '  <key>NSExtension</key>\n'
      printf '  <dict>\n'
      printf '    <key>NSExtensionPointIdentifier</key>\n'
      printf '    <string>%s</string>\n' "$extension_point"
      printf '  </dict>\n'
    fi
    printf '</dict>\n'
    printf '</plist>\n'
  } >"$path"
}

write_plist "$APP_BUNDLE/Info.plist" "16" "https://relay.volumearc.app"
write_plist "$WATCH_BUNDLE/Info.plist" "16"
write_plist "$WATCH_WIDGET_BUNDLE/Info.plist" "16" "" "com.apple.widgetkit-extension"

cat >"$TMP_DIR/bin/sentry-cli" <<'SH'
#!/usr/bin/env bash
echo "sentry-cli $*" >> "${SENTRY_CLI_TEST_LOG:?}"
SH
chmod +x "$TMP_DIR/bin/sentry-cli"

CI_XCODEBUILD_ACTION="archive" \
  CI_XCODEBUILD_EXIT_CODE="0" \
  CI_BUILD_NUMBER="16" \
  CI_DERIVED_DATA_PATH="$TMP_DIR/Derived" \
  VOLUMEARC_AI_RELAY_URL="https://relay.volumearc.app" \
  SENTRY_AUTH_TOKEN="fake-token" \
  SENTRY_CLI_TEST_LOG="$SENTRY_LOG" \
  PATH="$TMP_DIR/bin:$PATH" \
  bash "$ROOT_DIR/ci_scripts/ci_post_xcodebuild.sh" >"$LOG_PATH"

if ! grep -q "archive contract OK" "$LOG_PATH"; then
  echo "FAIL: ci_post_xcodebuild.sh did not validate the archive contract" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

if ! grep -q "debug-files upload" "$SENTRY_LOG"; then
  echo "FAIL: ci_post_xcodebuild.sh did not upload dSYMs through sentry-cli" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

rm -rf "$WATCH_BUNDLE"
if CI_XCODEBUILD_ACTION="archive" \
  CI_XCODEBUILD_EXIT_CODE="0" \
  CI_BUILD_NUMBER="16" \
  CI_ARCHIVE_PATH="$ARCHIVE_PATH" \
  SENTRY_AUTH_TOKEN="fake-token" \
  SENTRY_CLI_TEST_LOG="$SENTRY_LOG" \
  PATH="$TMP_DIR/bin:$PATH" \
  bash "$ROOT_DIR/ci_scripts/ci_post_xcodebuild.sh" >"$LOG_PATH" 2>&1; then
  echo "FAIL: ci_post_xcodebuild.sh accepted an archive without an embedded watch app" >&2
  exit 1
fi

if ! grep -q "missing embedded watch app" "$LOG_PATH"; then
  echo "FAIL: missing-watch failure did not explain the archive contract violation" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

CI_XCODEBUILD_ACTION="archive" \
  CI_XCODEBUILD_EXIT_CODE="65" \
  SENTRY_AUTH_TOKEN="fake-token" \
  PATH="$TMP_DIR/bin:$PATH" \
  bash "$ROOT_DIR/ci_scripts/ci_post_xcodebuild.sh" >"$LOG_PATH"

if ! grep -q "xcodebuild already failed" "$LOG_PATH"; then
  echo "FAIL: ci_post_xcodebuild.sh did not skip after a failed xcodebuild action" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

echo "ci_post_xcodebuild archive contract test passed"
