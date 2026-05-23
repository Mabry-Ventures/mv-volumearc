#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/volumearc-ci-post-clone.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/App" "$TMP_DIR/VolumeArcApple.xcodeproj" "$TMP_DIR/bin" "$TMP_DIR/ci_scripts"
cp "$ROOT_DIR/App/Info.plist" "$TMP_DIR/App/Info.plist"
cp "$ROOT_DIR/VolumeArcApple.xcodeproj/project.pbxproj" "$TMP_DIR/VolumeArcApple.xcodeproj/project.pbxproj"
cp "$ROOT_DIR/ci_scripts/ci_post_clone.sh" "$TMP_DIR/ci_scripts/ci_post_clone.sh"
ln -s /usr/bin/true "$TMP_DIR/bin/sentry-cli"
LOG_PATH="$TMP_DIR/ci_post_clone.log"
PROJECT_FILE="$TMP_DIR/VolumeArcApple.xcodeproj/project.pbxproj"
TEST_RELAY_SIGNING_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

run_patch() {
  local relay_url="$1"
  local action="${2:-test}"
  local build_number="${3:-}"
  # SKIP_HYGIENE_GATE=1: this harness stubs only Info.plist + the project
  # file, so the VOL-246 hygiene gate (swiftlint --strict +
  # validate_release_config) has no Swift sources / .swiftlint.yml /
  # scripts/ to act on. Skip it so this test stays scoped to the config
  # patching it actually asserts. Real Xcode Cloud runs never set it.
  SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0" \
    VOLUMEARC_AI_RELAY_URL="$relay_url" \
    VOLUMEARC_RELAY_SIGNING_KEY="$TEST_RELAY_SIGNING_KEY" \
    CI_XCODEBUILD_ACTION="$action" \
    CI_BUILD_NUMBER="$build_number" \
    SKIP_HYGIENE_GATE=1 \
    PATH="$TMP_DIR/bin:$PATH" \
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

assert_project_build_number() {
  local expected="$1"
  local settings
  settings="$(grep -E "CURRENT_PROJECT_VERSION = [^;]+;" "$PROJECT_FILE" || true)"
  if [[ -z "$settings" ]]; then
    echo "FAIL: expected CURRENT_PROJECT_VERSION settings in project" >&2
    exit 1
  fi
  if printf '%s\n' "$settings" | grep -v "CURRENT_PROJECT_VERSION = ${expected};" >/dev/null; then
    echo "FAIL: expected every CURRENT_PROJECT_VERSION to equal $expected" >&2
    printf '%s\n' "$settings" >&2
    exit 1
  fi
}

run_patch "relay.volumearc.app"
assert_plist_value "VolumeArcAIRelayURL" "https://relay.volumearc.app"
assert_plist_value "VolumeArcSentryDSN" "https://examplePublicKey@o0.ingest.sentry.io/0"
assert_plist_value "VolumeArcRelaySigningKey" "$TEST_RELAY_SIGNING_KEY"
if ! grep -q "Patched VolumeArcRelaySigningKey into Info.plist (len=64)" "$LOG_PATH"; then
  echo "FAIL: ci_post_clone.sh did not log the relay signing-key patch length" >&2
  exit 1
fi
if grep -q "$TEST_RELAY_SIGNING_KEY" "$LOG_PATH"; then
  echo "FAIL: ci_post_clone.sh leaked the relay signing-key value to logs" >&2
  exit 1
fi

run_patch "https://relay.volumearc.app"
assert_plist_value "VolumeArcAIRelayURL" "https://relay.volumearc.app"

run_patch "relay.volumearc.app" "archive" "15"
assert_project_build_number "15"
if ! grep -q "Patched CURRENT_PROJECT_VERSION to 15" "$LOG_PATH"; then
  echo "FAIL: ci_post_clone.sh did not log the Xcode Cloud build-number patch" >&2
  exit 1
fi

if SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0" \
  VOLUMEARC_AI_RELAY_URL="http://relay.volumearc.app" \
  VOLUMEARC_RELAY_SIGNING_KEY="$TEST_RELAY_SIGNING_KEY" \
  CI_XCODEBUILD_ACTION="test" \
  SKIP_HYGIENE_GATE=1 \
  bash "$TMP_DIR/ci_scripts/ci_post_clone.sh" >"$LOG_PATH" 2>&1; then
  echo "FAIL: ci_post_clone.sh accepted a non-HTTPS relay URL" >&2
  exit 1
fi

if SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0" \
  VOLUMEARC_AI_RELAY_URL="https://example.com" \
  VOLUMEARC_RELAY_SIGNING_KEY="$TEST_RELAY_SIGNING_KEY" \
  CI_XCODEBUILD_ACTION="test" \
  SKIP_HYGIENE_GATE=1 \
  bash "$TMP_DIR/ci_scripts/ci_post_clone.sh" >"$LOG_PATH" 2>&1; then
  echo "FAIL: ci_post_clone.sh accepted a non-allowlisted relay host" >&2
  exit 1
fi

if SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0" \
  VOLUMEARC_AI_RELAY_URL="https://relay.volumearc.app" \
  VOLUMEARC_RELAY_SIGNING_KEY="not base64" \
  CI_XCODEBUILD_ACTION="archive" \
  SKIP_HYGIENE_GATE=1 \
  PATH="$TMP_DIR/bin:$PATH" \
  bash "$TMP_DIR/ci_scripts/ci_post_clone.sh" >"$LOG_PATH" 2>&1; then
  echo "FAIL: ci_post_clone.sh accepted a malformed VOLUMEARC_RELAY_SIGNING_KEY" >&2
  exit 1
fi
if ! grep -q "VOLUMEARC_RELAY_SIGNING_KEY must be a single base64 value" "$LOG_PATH"; then
  echo "FAIL: ci_post_clone.sh did not explain the malformed relay signing key" >&2
  exit 1
fi

if SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0" \
  VOLUMEARC_AI_RELAY_URL="https://relay.volumearc.app" \
  CI_XCODEBUILD_ACTION="archive" \
  SKIP_HYGIENE_GATE=1 \
  PATH="$TMP_DIR/bin:$PATH" \
  bash "$TMP_DIR/ci_scripts/ci_post_clone.sh" >"$LOG_PATH" 2>&1; then
  echo "FAIL: ci_post_clone.sh accepted an archive relay URL without VOLUMEARC_RELAY_SIGNING_KEY" >&2
  exit 1
fi
if ! grep -q "VOLUMEARC_RELAY_SIGNING_KEY is required for archive workflows" "$LOG_PATH"; then
  echo "FAIL: ci_post_clone.sh did not explain the missing archive relay signing key" >&2
  exit 1
fi

echo "ci_post_clone config patch test passed"
