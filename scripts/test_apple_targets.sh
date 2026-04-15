#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

# VOL-57/59 fixup: the self-hosted runner keeps running into
# "Application failed preflight checks / Busy" when launching the
# XCUITest runner app. That's stale simulator state from a previous
# CI run — any previously-installed copy of com.mabryventures.VolumeArc
# or its .xctrunner partner app leaves the simulator in a state where
# SBMainWorkspace rejects the next launch. We've seen `shutdown all`
# alone be insufficient when a prior run crashed mid-install; `erase all`
# wipes installed apps and data so xcodebuild boots a pristine device.
# Both are safe on developer machines — they only affect simulators,
# not the user's real data.
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
  CODE_SIGNING_ALLOWED=NO \
  test

# XCUITests (journey coverage)
reset_simulators
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcAppUITests" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  CODE_SIGNING_ALLOWED=NO \
  test
