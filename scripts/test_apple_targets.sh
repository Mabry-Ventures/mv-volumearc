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

# VOL-57/59 fixup: the self-hosted runner keeps running into
# "Application failed preflight checks / Busy" when launching the
# XCUITest runner app. Stale simulator state from a previous CI run
# leaves SBMainWorkspace rejecting the next launch. `shutdown all` +
# `erase all` wipes installed apps and data so xcodebuild boots a
# pristine device. Safe on developer machines — only affects simulators.
# `xcrun` is invoked directly so `xcode-select` PATH settles on runners
# without DEVELOPER_DIR pointing at Xcode.app at script entry.
reset_simulators() {
  xcrun simctl shutdown all 2>/dev/null || true
  xcrun simctl erase all 2>/dev/null || true
}

# Unit tests
reset_simulators
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcAppTests" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  test

# XCUITests (journey coverage)
reset_simulators
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcAppUITests" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  test
