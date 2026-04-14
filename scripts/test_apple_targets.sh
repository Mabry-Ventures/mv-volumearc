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
# SBMainWorkspace rejects the next launch. Shutting down every booted
# simulator before each test invocation clears that state and lets
# xcodebuild boot the iPhone 17 fresh. Safe on developer machines too
# because xcodebuild will just re-boot whatever it needs.
reset_simulators() {
  xcrun simctl shutdown all 2>/dev/null || true
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
