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
WATCH_TEST_WALL_TIMEOUT="${WATCH_TEST_WALL_TIMEOUT:-600}"  # 10 min
UI_TEST_DEFAULT_ALLOWANCE="${UI_TEST_DEFAULT_ALLOWANCE:-180}"
UI_TEST_MAX_ALLOWANCE="${UI_TEST_MAX_ALLOWANCE:-360}"
UI_TEST_WALL_TIMEOUT="${UI_TEST_WALL_TIMEOUT:-2100}"        # 35 min

terminate_process_tree() {
  local root_pid="$1"
  local signal="$2"
  local child_pid

  while IFS= read -r child_pid; do
    [ -z "$child_pid" ] && continue
    terminate_process_tree "$child_pid" "$signal"
  done < <(pgrep -P "$root_pid" 2>/dev/null || true)

  kill "-$signal" "$root_pid" 2>/dev/null || true
}

# Run a command with a wall-clock timeout. Returns the command's exit
# status, or 124 if killed by the watchdog. The command must be a
# function or simple binary — pipelines should be wrapped in a function
# so PIPESTATUS resolves inside the subshell.
run_with_wallclock_timeout() {
  local timeout_sec="$1"
  local label="$2"
  shift 2

  echo "::notice::${label} watchdog armed for ${timeout_sec}s."

  ( "$@" ) &
  local cmd_pid=$!

  (
    sleep "$timeout_sec"
    if kill -0 "$cmd_pid" 2>/dev/null; then
      echo "::error::${label} exceeded ${timeout_sec}s wall-clock timeout; killing pid $cmd_pid"
      terminate_process_tree "$cmd_pid" TERM
      sleep 10
      terminate_process_tree "$cmd_pid" KILL
    fi
  ) &
  local watchdog_pid=$!

  set +e
  wait "$cmd_pid" 2>/dev/null
  local status=$?

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
# Fail-fast threshold for `simctl bootstatus -b`. The "Waiting on
# System App" wedge (orphan `launchd_sim` left over from a prior CI
# run) used to burn 18+ minutes here before the outer
# UNIT_TEST_WALL_TIMEOUT killed the run. Five minutes is well above
# the legit boot time (~30s warm, ~90s cold) and far below the
# wedge cliff, so a >5min bootstatus reliably means the host needs
# orphan-process cleanup, not more patience.
SIM_BOOTSTATUS_TIMEOUT="${SIM_BOOTSTATUS_TIMEOUT:-300}"

warm_simulator_for_tests() {
  local device="$IOS_TEST_DEVICE_NAME"
  echo "Pre-warming '$device' for tests (AX daemon stabilization)..."
  xcrun simctl boot "$device" 2>/dev/null || true
  # `bootstatus -b` blocks until the device reports `system_app == true`,
  # which is a stronger signal than `-c` (which only waits for boot
  # completion). Without this the AX daemon may not be ready when
  # XCTRunner connects.
  #
  # VOL-227 round 3 (2026-05-20): the M4 self-hosted runner has been
  # hitting a "Waiting on System App" wedge during this step — PRs
  # #237 and #238 both burned ~18 minutes here before the outer
  # wallclock killed xcodebuild and the CI step exited with 137. The
  # root cause is a host-level orphan `launchd_sim` left over from a
  # prior run (the user has documented the manual cleanup, but it
  # needs to happen out-of-band). Wrap bootstatus in a 5-minute
  # wallclock so the failure mode surfaces 13 min faster with a
  # clear actionable error message instead of "process killed."
  set +e
  run_with_wallclock_timeout "$SIM_BOOTSTATUS_TIMEOUT" "Simulator bootstatus" \
    xcrun simctl bootstatus "$device" -b
  local bootstatus_status=$?
  set -e

  if [ "$bootstatus_status" = "124" ]; then
    echo "::error::Simulator '$device' bootstatus wedged in 'Waiting on System App' for >${SIM_BOOTSTATUS_TIMEOUT}s. This is the host-level orphan launchd_sim issue. The runner host needs to clean up the stale launchd_sim processes — see docs/INCIDENTS.md (or kill orphan launchd_sim processes outside any active xcrun simctl tree). No PR-side change will help until the host is recovered."
    exit "$bootstatus_status"
  fi
  if [ "$bootstatus_status" != "0" ]; then
    echo "::error::Simulator bootstatus exited with non-zero status $bootstatus_status (not a wedge — investigate the simctl output above)."
    exit "$bootstatus_status"
  fi

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

  # VOL-231 / iOS 26.5 LLDB instability: clear the LLDB VersionStore cache
  # on the runner host. `DebuggerLLDB.DebuggerVersionStore.StoreError error 0`
  # is triggered when the cached LLDB debug-info index is stale after an iOS
  # simulator version update. Deleting the store forces LLDB to rebuild it on
  # next use, which takes ~1-2s but never produces the StoreError wedge.
  # `|| true` because the directory may not exist on a fresh runner.
  LLDB_STORE="${HOME}/Library/Developer/Xcode/LLDB"
  if [ -d "$LLDB_STORE" ]; then
    echo "Clearing LLDB VersionStore cache (iOS 26.5 instability mitigation)..."
    rm -rf "$LLDB_STORE" 2>/dev/null || true
  fi

  echo "Simulator '$device' is ready for tests."
}
warm_simulator_for_tests

unit_test_pipeline() {
  local log_path="$1"
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
    test 2>&1 | tee "$log_path"
  return "${PIPESTATUS[0]}"
}

# VOL-227 round 2 (2026-05-19): the iOS unit-test runner on
# `mv-shared-01` / `mv-shared-02` started hitting a consistent
# `xctest encountered an error (Failed to establish communication with
# the test runner. (Channel disconnected))` flake during May 19 batch
# runs (PRs #236, #237, #238 all hit it across three independent
# invocations). The failure timing varies (70s vs 420s into test
# execution), so it's not a specific flaky test — it's a runner-state
# regression. The xcresult bundle gets left incomplete, which
# downstream breaks the Coverage gate with a "Metadata.plist couldn't
# be opened" error.
#
# The shell-level mitigation: detect the channel-disconnect pattern in
# the test log, kill the simulator, re-warm, and retry the unit-test
# invocation once. xcresult bundle is removed before the retry so
# xcodebuild can write a fresh one. Mirrors the per-shard sim-busy
# retry pattern that already exists for UI tests (`run_ui_shard` →
# `run_ui_shard_attempt 2`).
is_channel_disconnect_failure() {
  local log_path="$1"
  # CodeRabbit + Codex (PR #241) flagged that a bare match on
  # `xctest encountered an error` is too broad — it catches unrelated
  # unit-test failures (e.g. compile errors that xctest reports
  # through the same error-print path). Tighten to the exact
  # channel-disconnect signature so non-flake failures keep their
  # existing exit behavior.
  grep -Eq \
    'Failed to establish communication with the test runner|Channel disconnected' \
    "$log_path"
}

# VOL-227 round 4 (2026-05-24): detect the XCTRunner crash/restart
# pattern that neither the preflight check nor channel-disconnect check
# catches. When the app under test or simulator AX stack crashes the
# runner process, xcodebuild logs this marker and resumes later tests,
# but it still reports the interrupted methods as failures.
is_xctest_runner_crash_failure() {
  local log_path="$1"
  grep -Eq \
    'Restarting after unexpected exit, crash, or test timeout|Mach error -308 - \(ipc/mig\) server died|NSMachErrorDomain Code=-308|Failed to install or launch the test runner|DebuggerLLDB\.DebuggerVersionStore\.StoreError' \
    "$log_path"
}

run_unit_tests_attempt() {
  local attempt="$1"
  local log_path="$DERIVED_DATA_PATH/unit-test-attempt-${attempt}.log"

  # xcodebuild refuses to write to an existing -resultBundlePath.
  rm -rf "$TEST_RESULT_BUNDLE"

  set +e
  run_with_wallclock_timeout "$UNIT_TEST_WALL_TIMEOUT" \
    "Unit tests attempt $attempt" \
    unit_test_pipeline "$log_path"
  local status=$?

  if [ "$status" = "124" ]; then
    echo "::error::Unit-test attempt $attempt wall-clock timeout fired. See unit-test-attempt-${attempt}.log."
  fi
  return "$status"
}

# CodeRabbit + Codex (PR #241) flagged that `if ! foo; then $? = $?`
# captures the negation result (0), not the underlying failing exit
# code — so `first_status` and `second_status` end up 0 on real
# failures, masking broken unit tests as green CI. Capture the exit
# code BEFORE any negation by running the attempt with `set +e` first.
set +e
run_unit_tests_attempt 1
first_status=$?
set -e

if [ "$first_status" != "0" ]; then
  first_log="$DERIVED_DATA_PATH/unit-test-attempt-1.log"
  unit_retry_reason=""

  if [ -f "$first_log" ] && is_channel_disconnect_failure "$first_log"; then
    unit_retry_reason="channel-disconnect flake"
  elif [ -f "$first_log" ] && is_xctest_runner_crash_failure "$first_log"; then
    unit_retry_reason="test-runner crash/restart flake"
  fi

  if [ -n "$unit_retry_reason" ]; then
    echo "::warning::Unit-test attempt 1 hit a $unit_retry_reason; rebooting simulator + retrying once."
    # These signatures mean the test-runner process died. The sim state
    # itself may be wedged — shutdown + re-warm to give the second
    # attempt a clean slate.
    xcrun simctl shutdown "$IOS_TEST_DEVICE_NAME" 2>/dev/null || true
    sleep 10
    warm_simulator_for_tests
    reset_app_state

    set +e
    run_unit_tests_attempt 2
    second_status=$?
    set -e

    if [ "$second_status" != "0" ]; then
      if [ "$second_status" = "124" ]; then
        echo "::error::Unit-test attempt 2 also wall-clock-timed-out. The XCTRunner failure mode is now persistent — investigate runner state."
      else
        echo "::error::Unit-test attempt 2 failed (exit $second_status) after a $unit_retry_reason retry. Inspect unit-test-attempt-2.log + the xcresult bundle."
      fi
      exit "$second_status"
    fi
  else
    if [ "$first_status" = "124" ]; then
      echo "::error::Unit-test wall-clock timeout fired. The likely cause is the XCTRunner failing to launch on the simulator (search prior runs for 'Timed out waiting for AX loaded notification'). Inspect the .xcresult bundle for the last test method that started; that's where execution stalled."
    fi
    exit "$first_status"
  fi
fi

# VOL-138: watchOS unit tests.
#
# `VolumeArcWatchTests` links `VolumeArcCoreWatch` and exercises the
# watchOS-compiled flavor of the connectivity / payload / queue types
# that the iOS-side `VolumeArcAppTests` only exercises against the iOS
# SDK. The bundle has no host application — it runs library assertions
# directly on the watch simulator.
#
# Watch tests run AFTER the iOS unit tests and BEFORE the UI test
# shards because:
#   1. They're fast (~7 sec total locally), so the failure signal is
#      cheap and shows up before the expensive UI runs.
#   2. They run on a separate watchOS simulator destination, so they
#      can't poison the iOS test runner's AccessibilityUIServer or
#      sim state.
WATCHOS_TEST_DEVICE_NAME="$(resolve_watch_test_device)"
WATCH_TEST_RESULT_BUNDLE="${WATCH_TEST_RESULT_BUNDLE:-$DERIVED_DATA_PATH/TestResults-watch.xcresult}"
rm -rf "$WATCH_TEST_RESULT_BUNDLE"

# Boot the watch sim ahead of time. `simctl bootstatus -b` blocks until
# the device's system app reports ready, same as the iOS sim warm-up.
echo "Pre-booting '$WATCHOS_TEST_DEVICE_NAME' for watch tests..."
xcrun simctl boot "$WATCHOS_TEST_DEVICE_NAME" 2>/dev/null || true
xcrun simctl bootstatus "$WATCHOS_TEST_DEVICE_NAME" -b
sleep 5

run_watch_tests() {
  xcodebuild \
    -project "VolumeArcApple.xcodeproj" \
    -scheme "VolumeArcWatchTests" \
    -destination "platform=watchOS Simulator,name=$WATCHOS_TEST_DEVICE_NAME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
    -enableCodeCoverage YES \
    -resultBundlePath "$WATCH_TEST_RESULT_BUNDLE" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$UNIT_TEST_DEFAULT_ALLOWANCE" \
    -maximum-test-execution-time-allowance "$UNIT_TEST_MAX_ALLOWANCE" \
    CODE_SIGNING_ALLOWED=NO \
    test
}

# Codex review on PR #237: `if ! foo; then $? = $?` captures the
# negation result (0), not the underlying failure exit code — so
# watch-test failures would slip through as green CI. Run with `set
# +e` and capture `$?` directly. Same pattern as the iOS unit-test
# retry mitigation in `claude/unit-test-channel-disconnect-retry`
# (PR #241).
set +e
run_with_wallclock_timeout "$WATCH_TEST_WALL_TIMEOUT" "Watch unit tests" run_watch_tests
watch_test_status=$?
set -e

if [ "$watch_test_status" != "0" ]; then
  if [ "$watch_test_status" = "124" ]; then
    echo "::error::Watch unit-test wall-clock timeout fired. Check the watchOS simulator state; the test bundle takes <10s locally, so a multi-minute timeout means xcodebuild itself never made progress."
  fi
  exit "$watch_test_status"
fi

# XCUITests (journey coverage) — sharded
#
# VOL-231 round 3: split the UI test target into N partitions so each
# xcodebuild invocation handles a contained subset. Three goals, in
# order of importance:
#
#   1. **Failure-domain isolation.** Pre-sharding, an AX-daemon wedge
#      in the accessibility-stress tests (Mach error -308, daemon
#      ipc/mig server died) brought down the entire UI test run.
#      Isolating that class of tests into its own shard means the
#      wedge only kills its own shard; the others still produce a
#      clean signal.
#
#   2. **Granular retry.** The pre-shard "sim-busy preflight retry"
#      block restarted the whole 35-min UI run. Per-shard retry only
#      restarts the affected shard.
#
#   3. **Matrix-ready.** We have one self-hosted runner today, so
#      shards run sequentially in the same job. The partitioning + per-
#      shard log/xcresult layout is the structural piece that lets a
#      future second runner trivially fan shards into a CI matrix
#      without touching this script.
#
# Shard map (kept here, not in CI yaml, so the contract is shell-
# testable + version-controlled with the test sources):
#
#   smoke                     → fast smoke + telemetry-probe matcher
#   journeys-core             → heaviest user-flow journeys
#   journeys-aux              → auxiliary journeys (profile, feedback,
#                                signals, app intents, healthkit perms,
#                                watch sim, chaos)
#   accessibility-screenshots → AX-stress (known daemon wedge cause)
#                                + screenshot capture
#
# `verify_shard_coverage` below greps `Tests/VolumeArcAppUITests` for
# every `final class … XCTestCase` declaration and fails if any class
# is missing from the map — guards against "added a new test class,
# forgot to shard it" silently skipping coverage.
reset_app_state

UI_TEST_TARGET="VolumeArcAppUITests"
UI_SHARDS=(smoke journeys-core journeys-aux accessibility-screenshots)

ui_shard_classes() {
  local shard="$1"
  case "$shard" in
    smoke)
      cat <<'EOF'
VolumeArcAppUITests
VolumeArcTelemetryProbeMatcherTests
VolumeArcExploratoryUATAgentTests
EOF
      ;;
    journeys-core)
      cat <<'EOF'
VolumeArcAppJourneyTests
VolumeArcCoachJourneyTests
VolumeArcTodayJourneyTests
EOF
      ;;
    journeys-aux)
      cat <<'EOF'
VolumeArcProfileJourneyTests
VolumeArcFeedbackJourneyTests
VolumeArcSignalsJourneyTests
VolumeArcIntentJourneyTests
VolumeArcHealthKitPermissionJourneyTests
VolumeArcWatchSimulationJourneyTests
VolumeArcChaosJourneyTests
EOF
      ;;
    accessibility-screenshots)
      cat <<'EOF'
VolumeArcAccessibilityJourneyTests
VolumeArcScreenshotTests
EOF
      ;;
    *)
      echo "::error::Unknown UI shard: $shard" >&2
      return 1
      ;;
  esac
}

ui_shard_only_testing_args() {
  local shard="$1"
  while read -r class; do
    [ -z "$class" ] && continue
    printf -- '-only-testing:%s/%s\n' "$UI_TEST_TARGET" "$class"
  done < <(ui_shard_classes "$shard")
}

verify_shard_coverage() {
  # bash 3.2 compatibility: use a flat newline-separated string in place
  # of an associative array — macOS ships bash 3.2 and the existing
  # script targets that floor.
  local mapped_list=""
  local mapped_count=0
  local shard class
  for shard in "${UI_SHARDS[@]}"; do
    while IFS= read -r class; do
      [ -z "$class" ] && continue
      mapped_list+="${class}"$'\n'
      mapped_count=$((mapped_count + 1))
    done < <(ui_shard_classes "$shard")
  done

  local missing=()
  local f
  while IFS= read -r f; do
    while IFS= read -r class; do
      [ -z "$class" ] && continue
      if ! printf '%s\n' "$mapped_list" | grep -qFx "$class"; then
        missing+=("$class (in $(basename "$f"))")
      fi
    done < <(
      # CodeRabbit feedback on PR #236: anchor on the `class …: XCTestCase`
      # tail so non-`final` declarations (`class FooTests: XCTestCase`,
      # `public class FooTests: XCTestCase`, etc.) still get picked up.
      # `grep -oE` strips any leading modifiers because the match starts
      # at the literal `class` keyword.
      grep -oE 'class [A-Za-z0-9_]+: XCTestCase' "$f" \
        | sed -E 's/^class ([A-Za-z0-9_]+): XCTestCase$/\1/'
    )
  done < <(find Tests/VolumeArcAppUITests -name '*.swift' -type f)

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "::error::Unmapped XCUITest classes — add them to UI_SHARDS in scripts/test_apple_targets.sh:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    return 1
  fi
  echo "Shard map covers all ${mapped_count} XCUITest classes."
}

is_simulator_busy_preflight_failure() {
  local log_path="$1"
  grep -Eq \
    'Application failed preflight checks|SBMainWorkspace.*Busy|Simulator device failed to launch .*xctrunner' \
    "$log_path"
}

ui_shard_pipeline() {
  local shard="$1"
  local log_path="$2"
  local shard_xcresult="$3"
  local only_testing_args=()
  while IFS= read -r arg; do
    [ -z "$arg" ] && continue
    only_testing_args+=("$arg")
  done < <(ui_shard_only_testing_args "$shard")

  # VOL-231 round 2 lesson: do NOT pass `-test-iterations` /
  # `-retry-tests-on-failure` at the xcodebuild level — it corrupts
  # the xcresult bundle on the self-hosted runner. The shell-level
  # per-shard retry below is the correct retry layer.
  ui_only_testing_pipeline "$log_path" "$shard_xcresult" "${only_testing_args[@]}"
}

ui_only_testing_pipeline() {
  local log_path="$1"
  local shard_xcresult="$2"
  shift 2

  xcodebuild \
    -project "VolumeArcApple.xcodeproj" \
    -scheme "$UI_TEST_TARGET" \
    -destination "platform=iOS Simulator,name=$IOS_TEST_DEVICE_NAME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
    -resultBundlePath "$shard_xcresult" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$UI_TEST_DEFAULT_ALLOWANCE" \
    -maximum-test-execution-time-allowance "$UI_TEST_MAX_ALLOWANCE" \
    "$@" \
    CODE_SIGNING_ALLOWED=NO \
    test 2>&1 | tee "$log_path"
  return "${PIPESTATUS[0]}"
}

ui_crashed_only_testing_args() {
  local xcresult_path="$1"

  [ -d "$xcresult_path" ] || return 1

  xcrun xcresulttool get test-results summary \
    --path "$xcresult_path" \
    --format json \
    | ruby -rjson -e '
        target = ARGV.fetch(0)
        data = JSON.parse(STDIN.read)
        failures = data.fetch("testFailures", [])
        crashed = failures.select do |failure|
          failure.fetch("failureText", "").include?("Test crashed with signal")
        end

        exit 1 if failures.empty? || crashed.length != failures.length

        args = crashed.map do |failure|
          identifier = failure.fetch("testIdentifierString", "").sub(/\(\)\z/, "")
          klass, method = identifier.split("/", 2)
          next if klass.nil? || method.nil? || klass.empty? || method.empty?

          "-only-testing:#{target}/#{klass}/#{method}"
        end.compact.uniq

        exit 1 if args.empty?
        puts args
      ' "$UI_TEST_TARGET"
}

run_ui_shard_attempt() {
  local shard="$1"
  local attempt="$2"
  local log_path="$DERIVED_DATA_PATH/ui-test-${shard}-attempt-${attempt}.log"
  local shard_xcresult="$DERIVED_DATA_PATH/TestResults-ui-${shard}.xcresult"
  # xcodebuild refuses to write to an existing -resultBundlePath.
  rm -rf "$shard_xcresult"

  set +e
  run_with_wallclock_timeout "$UI_TEST_WALL_TIMEOUT" \
    "UI shard '$shard' attempt $attempt" \
    ui_shard_pipeline "$shard" "$log_path" "$shard_xcresult"
  local status=$?

  if [ "$status" = "124" ]; then
    echo "::error::UI shard '$shard' attempt $attempt hit ${UI_TEST_WALL_TIMEOUT}s wall-clock timeout (xcodebuild was likely stuck before any test method ran — see ui-test-${shard}-attempt-${attempt}.log)."
  fi
  return "$status"
}

run_ui_crashed_tests_attempt() {
  local shard="$1"
  local attempt="$2"
  local source_xcresult="$3"
  local args_path="$DERIVED_DATA_PATH/ui-test-${shard}-crashed-attempt-${attempt}.only-testing"
  local log_path="$DERIVED_DATA_PATH/ui-test-${shard}-crashed-attempt-${attempt}.log"
  local shard_xcresult="$DERIVED_DATA_PATH/TestResults-ui-${shard}-crashed-attempt-${attempt}.xcresult"

  if ! ui_crashed_only_testing_args "$source_xcresult" > "$args_path"; then
    echo "::error::UI shard '$shard' failed after retry, but the xcresult did not contain only runner-crashed tests. Inspect ${source_xcresult}."
    return 1
  fi

  local only_testing_args=()
  while IFS= read -r arg; do
    [ -z "$arg" ] && continue
    only_testing_args+=("$arg")
  done < "$args_path"

  if [ "${#only_testing_args[@]}" -lt 1 ]; then
    echo "::error::UI shard '$shard' failed after retry, but no crashed test methods could be extracted from ${source_xcresult}."
    return 1
  fi

  echo "::warning::Shard '$shard' retry still hit runner-crashed tests; rebooting + rerunning only ${#only_testing_args[@]} crashed method(s)."
  xcrun simctl shutdown "$IOS_TEST_DEVICE_NAME" 2>/dev/null || true
  sleep 10
  warm_simulator_for_tests
  reset_app_state
  rm -rf "$shard_xcresult"

  set +e
  run_with_wallclock_timeout "$UI_TEST_WALL_TIMEOUT" \
    "UI shard '$shard' crashed-tests attempt $attempt" \
    ui_only_testing_pipeline "$log_path" "$shard_xcresult" "${only_testing_args[@]}"
  local status=$?

  if [ "$status" = "124" ]; then
    echo "::error::UI shard '$shard' crashed-tests attempt $attempt hit ${UI_TEST_WALL_TIMEOUT}s wall-clock timeout. See ui-test-${shard}-crashed-attempt-${attempt}.log."
  fi
  return "$status"
}

run_ui_shard() {
  local shard="$1"
  echo "::group::UI shard: $shard"
  reset_app_state
  warm_simulator_for_tests

  set +e
  run_ui_shard_attempt "$shard" 1
  local first_status=$?
  set -e

  if [ "$first_status" = "0" ]; then
    echo "::endgroup::"
    return 0
  fi

  local first_log="$DERIVED_DATA_PATH/ui-test-${shard}-attempt-1.log"
  local should_retry=0
  local retry_reason=""
  if [ -f "$first_log" ] && is_simulator_busy_preflight_failure "$first_log"; then
    should_retry=1
    retry_reason="simulator Busy preflight failure"
  elif [ -f "$first_log" ] && is_xctest_runner_crash_failure "$first_log"; then
    # VOL-227 round 4: mid-test runner crash (app crash / AX-stack crash).
    # Kill AccessibilityUIServer before the retry — the iOS 26.5
    # UIAccessibilityLoaderWebShared duplicate class issue leaves the AX
    # daemon in a wedged state after each runner restart. The same
    # `warm_simulator_for_tests` call already does this; the explicit
    # kill here is belt-and-suspenders for the degraded-AX path.
    should_retry=1
    retry_reason="mid-test XCTRunner crash (unexpected exit / crash / timeout)"
  fi

  if [ "$should_retry" = "1" ]; then
    echo "::warning::Shard '$shard' hit a $retry_reason; rebooting + retrying once."
    xcrun simctl shutdown "$IOS_TEST_DEVICE_NAME" 2>/dev/null || true
    sleep 10
    warm_simulator_for_tests
    reset_app_state
    set +e
    run_ui_shard_attempt "$shard" 2
    local second_status=$?
    set -e

    if [ "$second_status" != "0" ]; then
      local second_log="$DERIVED_DATA_PATH/ui-test-${shard}-attempt-2.log"
      local second_xcresult="$DERIVED_DATA_PATH/TestResults-ui-${shard}.xcresult"
      if [ -f "$second_log" ] && is_xctest_runner_crash_failure "$second_log"; then
        set +e
        run_ui_crashed_tests_attempt "$shard" 3 "$second_xcresult"
        local crashed_status=$?
        set -e
        if [ "$crashed_status" = "0" ]; then
          echo "::warning::Shard '$shard' passed after rerunning only runner-crashed methods."
          echo "::endgroup::"
          return 0
        fi
      fi
    fi

    echo "::endgroup::"
    set +e
    return "$second_status"
  fi

  echo "::endgroup::"
  set +e
  return "$first_status"
}

# Verify shard map is complete BEFORE running anything.
verify_shard_coverage

# Filter for local diagnostics: `SHARD_FILTER=accessibility-screenshots
# ./scripts/test_apple_targets.sh` runs just that shard. CI sets nothing
# so all shards run.
SHARD_FILTER="${SHARD_FILTER:-}"

# If SHARD_FILTER is set, validate it matches a real shard name BEFORE
# starting any work. A typo'd filter would otherwise skip every shard
# and silently exit 0 with zero test methods executed.
if [ -n "$SHARD_FILTER" ]; then
  matched=0
  for shard in "${UI_SHARDS[@]}"; do
    if [ "$SHARD_FILTER" = "$shard" ]; then
      matched=1
      break
    fi
  done
  if [ "$matched" != "1" ]; then
    echo "::error::SHARD_FILTER='$SHARD_FILTER' does not match any defined shard. Valid: ${UI_SHARDS[*]}" >&2
    exit 1
  fi
fi

# Run each shard, collecting status. Continue past failures so we get
# a full picture instead of bailing on the first broken shard — the
# point of sharding is independent signal per partition.
declare -a shard_results=()
for shard in "${UI_SHARDS[@]}"; do
  if [ -n "$SHARD_FILTER" ] && [ "$SHARD_FILTER" != "$shard" ]; then
    echo "Skipping shard '$shard' (SHARD_FILTER=$SHARD_FILTER)"
    continue
  fi
  set +e
  run_ui_shard "$shard"
  shard_status=$?
  set -e
  shard_results+=("$shard:$shard_status")
done

# Aggregate exit status + per-shard VOL-227 sanity check.
ui_test_failed=0
total_methods=0
echo ""
echo "===== UI shard summary ====="
for entry in "${shard_results[@]}"; do
  shard="${entry%%:*}"
  status="${entry##*:}"

  log_to_check="$DERIVED_DATA_PATH/ui-test-${shard}-attempt-2.log"
  if [ ! -f "$log_to_check" ]; then
    log_to_check="$DERIVED_DATA_PATH/ui-test-${shard}-attempt-1.log"
  fi

  methods=0
  if [ -f "$log_to_check" ]; then
    methods="$(grep -cE "^Test Case '-\[VolumeArcAppUITests\." "$log_to_check" 2>/dev/null || true)"
    methods="${methods:-0}"
  fi
  total_methods=$((total_methods + methods))

  if [ "$status" != "0" ]; then
    ui_test_failed=1
    echo "  ✗ $shard (exit $status, $methods methods executed)"
    continue
  fi

  # VOL-227: a shard that exited 0 but ran zero test methods is the
  # same silent-pass failure mode that motivated the original sanity
  # check. Floor of 1 per shard — every shard has at least one mapped
  # class, so zero methods means the runner died before any test
  # started.
  if [ "$methods" -lt 1 ]; then
    ui_test_failed=1
    echo "  ✗ $shard (exit 0 but 0 methods executed — VOL-227 sanity failure)"
    echo "::error::VOL-227 sanity check failed for shard '$shard' — 0 test methods executed. Inspect $log_to_check."
    continue
  fi

  echo "  ✓ $shard ($methods methods)"
done
echo "Total UI test methods executed across all shards: $total_methods"

if [ "$ui_test_failed" != "0" ]; then
  exit 1
fi
