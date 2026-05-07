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

source "$ROOT/scripts/simulators.sh"
IOS_BUILD_DEVICE="$(resolve_ios_test_device)"

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcApp" \
  -destination "platform=iOS Simulator,name=$IOS_BUILD_DEVICE" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWidgets" \
  -destination "platform=iOS Simulator,name=$IOS_BUILD_DEVICE" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWatchWidgets" \
  -sdk watchsimulator \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWatch" \
  -sdk watchsimulator \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build
