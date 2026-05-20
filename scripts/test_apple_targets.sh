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

# VOL-231 / VOL-224: warm the simulator (boot + AX-daemon kick) BEFORE
# unit tests too. Earlier the warm step lived only in front of UI
# tests; PR #230 then hit a flake where the UNIT-test xcodebuild
# itself hung indefinitely waiting for the simulator to come up
# clean (1200s wall-clock timeout). Unit tests run inside a
# simulator-hosted test runner — they need the same healthy boot
# state UI tests do. `warm_simulator_for_tests` (defined below) is
# idempotent; calling it twice (here + before UI tests) is safe and
# only adds the second AX-daemon kill, which is the whole point.
warm_simulator_for_tests() {
  local device="$IOS_TEST_DEVICE_NAME"
  echo "Pre-warming '$device' for tests (AX daemon stabilization)..."
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
  # VOL-231 / VOL-224: pre-emptively restart `AccessibilityUIServer`
  # inside the booted simulator. The accessibility-stress XCUITests
  # (`VolumeArcAccessibilityJourneyTests` at `.accessibility5` +
  # `-NSDoubleLocalizedStrings YES`) reliably push the AX daemon
  # into a wedged state where the next test-runner install dies with
  # `Mach error -308 - (ipc/mig) server died`. Killing the daemon
  # here is safe — `launchd` respawns it within ~1s in a clean
  # state. `|| true` because the daemon may not yet be running on
  # the very first boot.
  echo "Restarting AccessibilityUIServer inside '$device' (VOL-231 mitigation)..."
  xcrun simctl spawn "$device" killall AccessibilityUIServer 2>/dev/null || true
  sleep 2
  echo "Simulator '$device' is ready for tests."
}
warm_simulator_for_tests

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

# VOL-88 / VOL-231: re-warm the simulator + restart AccessibilityUIServer
# between unit and UI tests. Unit tests may have left the AX daemon in
# a degraded state (the accessibility-stress XCUITests aren't the only
# trigger — any heavy XCTest workload can wedge `AccessibilityUIServer`
# on M4 self-hosted runners). `warm_simulator_for_tests` is idempotent
# (boot is a no-op if already booted), so this is just the AX-daemon
# kick again. See the function definition above for the full rationale.
warm_simulator_for_tests

ui_test_pipeline() {
  local log_path="$1"
  # VOL-231 round 2: the original mitigation added
  # `-test-iterations 2 -retry-tests-on-failure` (PR #233). It
  # successfully retried flaky tests, but the result bundle
  # finalization crashed every time a retry was triggered — the
  # `Coverage gate (VolumeArcCore >= 80%)` step then failed with:
  #   `xccov: The result bundle could not be opened as it is
  #    incomplete. Xcode might have failed to finish writing the
  #    result bundle.`
  # Pattern observed on 2 PRs (#229, #230) within hours of PR #233
  # landing on the M4 self-hosted runner. xcodebuild-level retry
  # was the wrong layer — the shell-level
  # `run_ui_tests_once 1 / once 2` retry below (which restarts
  # xcodebuild from scratch on simulator-busy preflight failures)
  # is the correct mitigation. Reverted to the pre-#233
  # invocation. The XCUITest runner-crash flake stays open as
  # VOL-231 with sharding marked as the medium-term fix.
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
    warm_simulator_for_tests
    reset_app_state
    run_ui_tests_once 2
  else
    exit "$first_ui_status"
  fi
fi

# VOL-227 sanity check: assert UI tests actually executed test methods.
# Before VOL-227, four pre-existing unit-test failures triggered an
# xcodebuild non-zero exit code that the script's `set -e` silently
# absorbed mid-flight (the `if ! run_with_wallclock_timeout ...; then`
# branch never ran because the wait semantics returned 0). UI tests
# never ran for ~7 days while CI reported green. This guard fails
# loudly if the UI test xcodebuild produced zero `Test Case` lines.
#
# Floor of 1 is intentional — the failure mode is "no tests ran at
# all", not "fewer tests than expected". The journey-coverage gate
# (VOL-200) is the right place to track per-surface execution counts.
UI_LOG_TO_CHECK="$DERIVED_DATA_PATH/ui-test-attempt-1.log"
if [ ! -f "$UI_LOG_TO_CHECK" ]; then
  UI_LOG_TO_CHECK="$DERIVED_DATA_PATH/ui-test-attempt-2.log"
fi
if [ -f "$UI_LOG_TO_CHECK" ]; then
  UI_METHODS_EXECUTED="$(grep -cE "^Test Case '-\[VolumeArcAppUITests\." "$UI_LOG_TO_CHECK" 2>/dev/null || echo 0)"
  if [ "$UI_METHODS_EXECUTED" -lt 1 ]; then
    echo "::error::VOL-227 sanity check failed — UI test xcodebuild produced $UI_METHODS_EXECUTED 'Test Case' lines. The XCUITest suite did not actually execute any methods. Inspect $UI_LOG_TO_CHECK for the failure mode (sim boot, AX daemon, build).";
    exit 1
  else
    echo "VOL-227 sanity check: UI tests executed $UI_METHODS_EXECUTED methods."
  fi
else
  echo "::error::VOL-227 sanity check failed — neither ui-test-attempt-1.log nor ui-test-attempt-2.log exists in $DERIVED_DATA_PATH. The UI test pipeline never wrote a log file.";
  exit 1
fi
