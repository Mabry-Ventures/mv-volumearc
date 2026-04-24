#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

# VOL-75 P2 / runner isolation: pin DerivedData to the workspace so concurrent
# CI jobs on the same self-hosted Mac don't race on the shared
# ~/Library/Developer/Xcode/DerivedData/VolumeArcApple-* path. SPM extracts
# XCFrameworks into DerivedData; two jobs extracting into the same directory
# at once produce "checkdir error: cannot create ..." and "could not resolve
# package dependencies" failures. Keeping DerivedData inside $ROOT means each
# worktree / job has its own copy, and `git clean -ffdx` wipes it between runs.
# Overridable via `DERIVED_DATA_PATH` env var for developers who want to share
# a cache across scripts.
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
