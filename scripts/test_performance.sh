#!/usr/bin/env bash
# VOL-99: run the performance regression suite (`VolumeArcAppPerfTests`)
# on an iPhone 17 simulator, producing an `.xcresult` bundle that
# `scripts/check_performance.sh` parses to enforce the budget gate.
#
# Kept separate from `scripts/test_apple_targets.sh` because the
# measured suite is intentionally expensive: each `measure()` call
# runs 3–5 iterations per metric. Running it on every PR would
# roughly triple CI wall-time for no signal gain on non-perf
# changes.
#
# Tag-gated in CI via `.github/workflows/ci.yml`. Developers can run
# it locally to reproduce a CI regression or to re-baseline a metric
# after an intentional performance change.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data-perf}"
XCRESULT="${PERF_XCRESULT:-$ROOT/.build/perf-results.xcresult}"
SCHEME="VolumeArcAppPerfTests"

mkdir -p "$(dirname "$XCRESULT")"

. "$ROOT/scripts/simulators.sh"

IOS_TEST_DEVICE_NAME="$(resolve_ios_test_device --no-fallback)"

ruby "scripts/generate_xcode_project.rb"

# Wipe any stale perf result bundle — `xcodebuild test` refuses to
# write into an existing path.
rm -rf "$XCRESULT"

# Reset simulators for the same reason `test_apple_targets.sh` does:
# a previous CI run that crashed mid-install leaves the simulator in
# a state where `xcodebuild test` fails preflight checks. The perf
# target's launch path is particularly sensitive because the very
# first thing the cold-launch test measures is simulator boot time.
xcrun simctl shutdown all 2>/dev/null || true
xcrun simctl erase all 2>/dev/null || true

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$IOS_TEST_DEVICE_NAME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$XCRESULT" \
  CODE_SIGNING_ALLOWED=NO \
  test

echo "==> Perf suite finished. Results: $XCRESULT"
