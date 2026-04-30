#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

# VOL-88: Tart runners are ephemeral, but pinning DerivedData to the
# workspace keeps local developer runs and any fallback runner isolated
# from global Xcode caches. Overridable via `DERIVED_DATA_PATH` env var.
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
mkdir -p "$DERIVED_DATA_PATH"

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcApp" \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWidgets" \
  -sdk iphonesimulator \
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

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWatchWidgets" \
  -sdk watchsimulator \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build
