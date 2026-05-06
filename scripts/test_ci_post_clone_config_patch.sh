#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/volumearc-ci-post-clone.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/App" "$TMP_DIR/ci_scripts"
cp "$ROOT_DIR/App/Info.plist" "$TMP_DIR/App/Info.plist"
cp "$ROOT_DIR/ci_scripts/ci_post_clone.sh" "$TMP_DIR/ci_scripts/ci_post_clone.sh"
LOG_PATH="$TMP_DIR/ci_post_clone.log"

run_patch() {
  local relay_url="$1"
  SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0" \
    VOLUMEARC_AI_RELAY_URL="$relay_url" \
    CI_XCODEBUILD_ACTION="test" \
    bash "$TMP_DIR/ci_scripts/ci_post_clone.sh" >"$LOG_PATH"
}

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plutil -extract "$key" raw "$TMP_DIR/App/Info.plist")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected $key=$expected, got $actual" >&2
    exit 1
  fi
}

run_patch "relay.volumearc.app"
assert_plist_value "VolumeArcAIRelayURL" "https://relay.volumearc.app"
assert_plist_value "VolumeArcSentryDSN" "https://examplePublicKey@o0.ingest.sentry.io/0"

run_patch "https://relay.volumearc.app"
assert_plist_value "VolumeArcAIRelayURL" "https://relay.volumearc.app"

if SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0" \
  VOLUMEARC_AI_RELAY_URL="http://relay.volumearc.app" \
  CI_XCODEBUILD_ACTION="test" \
  bash "$TMP_DIR/ci_scripts/ci_post_clone.sh" >"$LOG_PATH" 2>&1; then
  echo "FAIL: ci_post_clone.sh accepted a non-HTTPS relay URL" >&2
  exit 1
fi

if SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0" \
  VOLUMEARC_AI_RELAY_URL="https://example.com" \
  CI_XCODEBUILD_ACTION="test" \
  bash "$TMP_DIR/ci_scripts/ci_post_clone.sh" >"$LOG_PATH" 2>&1; then
  echo "FAIL: ci_post_clone.sh accepted a non-allowlisted relay host" >&2
  exit 1
fi

echo "ci_post_clone config patch test passed"
