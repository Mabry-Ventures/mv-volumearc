#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

# VOL-75 P2 / runner isolation: pin DerivedData to the workspace so concurrent
# CI jobs on the same self-hosted Mac don't race on the shared
# ~/Library/Developer/Xcode/DerivedData/VolumeArcApple-* path. Without this,
# two jobs extracting the Sentry XCFramework at once produce "checkdir
# error: cannot create ..." and two jobs running XCUITest launch concurrently
# produce "Cannot launch simulated executable: no file found at VolumeArc.app"
# because one run wipes the other's freshly-built bundle. Keeping DerivedData
# inside $ROOT means each worktree has its own copy, cleaned by `git clean
# -ffdx` between runs. Overridable via `DERIVED_DATA_PATH` env var.
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
mkdir -p "$DERIVED_DATA_PATH"

# VOL-75 P2: the previous `shutdown all` + `erase all` was destructive at
# system scope — when two CI jobs ran concurrently on the same Mac
# (multiple runner instances share the simulator fleet), one job's reset
# would kill the other job's in-progress test with "Process spawn via
# launchd failed: Operation canceled." Replaced with a surgical uninstall
# of our app bundles from whatever simulator xcodebuild brings up;
# xcodebuild itself owns simulator lifecycle per run.
reset_app_state() {
  while read -r device_id; do
    [[ -z "$device_id" ]] && continue
    xcrun simctl uninstall "$device_id" com.mabryventures.VolumeArc 2>/dev/null || true
    xcrun simctl uninstall "$device_id" com.mabryventures.VolumeArc.tests 2>/dev/null || true
    xcrun simctl uninstall "$device_id" com.mabryventures.VolumeArc.uitests 2>/dev/null || true
  done < <(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' || true)
}

# Unit tests
# VOL-52: -enableCodeCoverage YES + -resultBundlePath give us an .xcresult
# bundle that check_coverage.sh parses via `xcrun xccov view --report --json`
# to enforce the 80% VolumeArcCore line-coverage gate. Remove any stale
# xcresult from a prior run before this invocation — xcodebuild refuses to
# write to an existing resultBundlePath.
TEST_RESULT_BUNDLE="${TEST_RESULT_BUNDLE:-$DERIVED_DATA_PATH/TestResults.xcresult}"
rm -rf "$TEST_RESULT_BUNDLE"
reset_app_state
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcAppTests" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  -enableCodeCoverage YES \
  -resultBundlePath "$TEST_RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  test

# XCUITests (journey coverage)
reset_app_state

# VOL-88: on Tart VM runners (iOS Simulator inside a virtualized macOS),
# the XCUITest test runner ("VolumeArcAppUITests-Runner") sometimes
# fails to initialize with:
#   "Timed out waiting for AX loaded notification"
# This is the iOS Accessibility daemon failing to come up before
# XCTRunner's connect timeout. Standard pattern for virtualized
# simulator environments: explicitly boot the destination simulator
# and wait for `bootstatus -b` (which includes a Springboard wait)
# before invoking xcodebuild test. Idempotent — if the simulator is
# already booted, `simctl boot` returns "Already booted" (handled by
# `|| true`).
warm_simulator_for_ui_tests() {
  local device="iPhone 17"
  echo "Pre-warming '$device' for UI tests (Tart VM AX daemon stabilization)..."
  xcrun simctl boot "$device" 2>/dev/null || true
  # `bootstatus -b` blocks until the device reports `system_app == true`,
  # which is a stronger signal than `-c` (which only waits for boot
  # completion). Without this the AX daemon may not be ready when
  # XCTRunner connects.
  xcrun simctl bootstatus "$device" -b
  # Belt-and-suspenders: even after bootstatus reports ready, the AX
  # daemon can take a few additional seconds to initialize. 15s
  # eliminates the flake observed on Tart VM runs of PR #83.
  sleep 15
  echo "Simulator '$device' is ready for XCUITests."
}
warm_simulator_for_ui_tests

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcAppUITests" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  test
