#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

# VOL-88: pinning DerivedData to the workspace keeps local developer
# runs and CI runner jobs isolated from global Xcode caches. Overridable
# via `DERIVED_DATA_PATH` env var.
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
mkdir -p "$DERIVED_DATA_PATH"

# VOL-164 round 2 (2026-05-10): defense in depth against hung test runs.
# Two layers:
#   1. Per-test execution-time allowance via xcodebuild's
#      `-test-timeouts-enabled YES` + `-default-test-execution-time-allowance`
#      + `-maximum-test-execution-time-allowance`. XCTest kills any
#      individual test method that runs past its allowance.
#   2. Wall-clock outer timeout via a shell watchdog around the
#      `xcodebuild test` invocation, in case the XCTRunner itself fails
#      to come up (the "Timed out waiting for AX loaded notification"
#      pattern documented below). Per-test timeouts can't catch that
#      because no test has started yet.
#
# PR #147's first run hung 76 minutes inside `Run tests` before being
# cancelled — exactly the failure shape this defense is for. The
# defaults below give tests room to complete on a slow runner while
# bounding the worst case to ~35 min total instead of "forever."
UNIT_TEST_DEFAULT_ALLOWANCE="${UNIT_TEST_DEFAULT_ALLOWANCE:-60}"
UNIT_TEST_MAX_ALLOWANCE="${UNIT_TEST_MAX_ALLOWANCE:-180}"
UNIT_TEST_WALL_TIMEOUT="${UNIT_TEST_WALL_TIMEOUT:-1200}"   # 20 min
UI_TEST_DEFAULT_ALLOWANCE="${UI_TEST_DEFAULT_ALLOWANCE:-180}"
UI_TEST_MAX_ALLOWANCE="${UI_TEST_MAX_ALLOWANCE:-360}"
UI_TEST_WALL_TIMEOUT="${UI_TEST_WALL_TIMEOUT:-2100}"        # 35 min

# Run a command with a wall-clock timeout. Returns the command's exit
# status, or 124 if killed by the watchdog. The command must be a
# function or simple binary — pipelines should be wrapped in a function
# so PIPESTATUS resolves inside the subshell.
run_with_wallclock_timeout() {
  local timeout_sec="$1"
  local label="$2"
  shift 2

  ( "$@" ) &
  local cmd_pid=$!

  (
    sleep "$timeout_sec"
    if kill -0 "$cmd_pid" 2>/dev/null; then
      echo "::error::${label} exceeded ${timeout_sec}s wall-clock timeout; killing pid $cmd_pid"
      kill -TERM "$cmd_pid" 2>/dev/null || true
      pkill -TERM -P "$cmd_pid" 2>/dev/null || true
      sleep 10
      kill -KILL "$cmd_pid" 2>/dev/null || true
      pkill -KILL -P "$cmd_pid" 2>/dev/null || true
    fi
  ) &
  local watchdog_pid=$!

  set +e
  wait "$cmd_pid" 2>/dev/null
  local status=$?
  set -e

  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true

  if [ "$status" -gt 128 ]; then
    # 128 + signal number — treat as timeout-killed.
    return 124
  fi
  return "$status"
}

. "$ROOT/scripts/simulators.sh"

IOS_TEST_DEVICE_NAME="$(resolve_ios_test_device)"

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

run_unit_tests() {
  xcodebuild \
    -project "VolumeArcApple.xcodeproj" \
    -scheme "VolumeArcAppTests" \
    -destination "platform=iOS Simulator,name=$IOS_TEST_DEVICE_NAME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
    -enableCodeCoverage YES \
    -resultBundlePath "$TEST_RESULT_BUNDLE" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$UNIT_TEST_DEFAULT_ALLOWANCE" \
    -maximum-test-execution-time-allowance "$UNIT_TEST_MAX_ALLOWANCE" \
    CODE_SIGNING_ALLOWED=NO \
    test
}

if ! run_with_wallclock_timeout "$UNIT_TEST_WALL_TIMEOUT" "Unit tests" run_unit_tests; then
  status=$?
  if [ "$status" = "124" ]; then
    echo "::error::Unit-test wall-clock timeout fired. The likely cause is the XCTRunner failing to launch on the simulator (search prior runs for 'Timed out waiting for AX loaded notification'). Inspect the .xcresult bundle for the last test method that started; that's where execution stalled."
  fi
  exit "$status"
fi

# XCUITests (journey coverage)
reset_app_state

# VOL-88: on self-hosted CI runners,
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
  local device="$IOS_TEST_DEVICE_NAME"
  echo "Pre-warming '$device' for UI tests (AX daemon stabilization)..."
  xcrun simctl boot "$device" 2>/dev/null || true
  # `bootstatus -b` blocks until the device reports `system_app == true`,
  # which is a stronger signal than `-c` (which only waits for boot
  # completion). Without this the AX daemon may not be ready when
  # XCTRunner connects.
  xcrun simctl bootstatus "$device" -b
  # Belt-and-suspenders: even after bootstatus reports ready, the AX
  # daemon can take a few additional seconds to initialize. 15s
  # eliminates the flake observed on CI runs of PR #83.
  sleep 15
  echo "Simulator '$device' is ready for XCUITests."
}
warm_simulator_for_ui_tests

ui_test_pipeline() {
  local log_path="$1"
  xcodebuild \
    -project "VolumeArcApple.xcodeproj" \
    -scheme "VolumeArcAppUITests" \
    -destination "platform=iOS Simulator,name=$IOS_TEST_DEVICE_NAME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$UI_TEST_DEFAULT_ALLOWANCE" \
    -maximum-test-execution-time-allowance "$UI_TEST_MAX_ALLOWANCE" \
    CODE_SIGNING_ALLOWED=NO \
    test 2>&1 | tee "$log_path"
  return "${PIPESTATUS[0]}"
}

run_ui_tests_once() {
  local attempt="$1"
  local log_path="$DERIVED_DATA_PATH/ui-test-attempt-${attempt}.log"

  set +e
  run_with_wallclock_timeout "$UI_TEST_WALL_TIMEOUT" "UI test attempt $attempt" \
    ui_test_pipeline "$log_path"
  local status=$?
  set -e

  if [ "$status" = "124" ]; then
    echo "::error::UI-test attempt $attempt hit ${UI_TEST_WALL_TIMEOUT}s wall-clock timeout (xcodebuild was likely stuck before any test method ran — see ui-test-attempt-${attempt}.log)."
  fi
  return "$status"
}

is_simulator_busy_preflight_failure() {
  local log_path="$1"
  grep -Eq \
    'Application failed preflight checks|SBMainWorkspace.*Busy|Simulator device failed to launch .*xctrunner' \
    "$log_path"
}

if run_ui_tests_once 1; then
  :
else
  first_ui_status=$?
  first_ui_log="$DERIVED_DATA_PATH/ui-test-attempt-1.log"
  if is_simulator_busy_preflight_failure "$first_ui_log"; then
    echo "::warning::XCUITest runner hit a simulator Busy preflight failure; rebooting simulator and retrying once."
    xcrun simctl shutdown "$IOS_TEST_DEVICE_NAME" 2>/dev/null || true
    sleep 10
    warm_simulator_for_ui_tests
    reset_app_state
    run_ui_tests_once 2
  else
    exit "$first_ui_status"
  fi
fi
