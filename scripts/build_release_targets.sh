#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcApp" \
  -sdk iphonesimulator \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcWidgets" \
  -sdk iphonesimulator \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcWatch" \
  -sdk watchsimulator \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build
