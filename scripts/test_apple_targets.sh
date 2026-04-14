#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

# Unit tests
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcAppTests" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  CODE_SIGNING_ALLOWED=NO \
  test

# XCUITests (journey coverage)
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcAppUITests" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  CODE_SIGNING_ALLOWED=NO \
  test
