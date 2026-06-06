#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
SOURCE_PACKAGES_PATH="$DERIVED_DATA_PATH/SourcePackages"
PACKAGE_FILE="$SOURCE_PACKAGES_PATH/checkouts/sentry-cocoa/Package.swift"
STATIC_ARTIFACT_PATH="$SOURCE_PACKAGES_PATH/artifacts/sentry-cocoa/Sentry/Sentry.xcframework"

mkdir -p "$DERIVED_DATA_PATH" "$SOURCE_PACKAGES_PATH"

if [ ! -f "$PACKAGE_FILE" ]; then
  xcodebuild \
    -resolvePackageDependencies \
    -project "VolumeArcApple.xcodeproj" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH" \
    >/dev/null
fi

if [ ! -f "$PACKAGE_FILE" ]; then
  echo "FAIL: Cannot hydrate Sentry XCFrameworks; missing $PACKAGE_FILE" >&2
  exit 1
fi

BINARY_TARGETS="$(ruby -e 'text = File.read(ARGV.fetch(0)); rows = text.scan(/\.binaryTarget\(\s*name:\s*"([^"]+)"[\s\S]*?url:\s*"([^"]+)"[\s\S]*?checksum:\s*"([^"]+)"/); abort("missing Sentry binary targets") if rows.empty?; rows.each { |row| puts row.join("\t") }' "$PACKAGE_FILE")"

WORK_DIR="$DERIVED_DATA_PATH/sentry-artifact-hydration"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

hydrated_count=0

while IFS=$'\t' read -r target_name artifact_url expected_checksum; do
  [ -z "$target_name" ] && continue

  artifact_path="$SOURCE_PACKAGES_PATH/artifacts/sentry-cocoa/$target_name/$target_name.xcframework"
  if [ -d "$artifact_path" ]; then
    continue
  fi

  cache_key="$(ruby -e 'puts ARGV.fetch(0).gsub(/[^A-Za-z0-9]/, "_")' "$artifact_url")"
  cache_file="${HOME}/Library/Caches/org.swift.swiftpm/artifacts/$cache_key"
  archive_path="$WORK_DIR/$target_name.xcframework.zip"
  unpack_dir="$WORK_DIR/$target_name-unpacked"

  if [ -f "$cache_file" ]; then
    cp "$cache_file" "$archive_path"
  else
    echo "Downloading $target_name XCFramework from $artifact_url"
    curl --fail --location --show-error --silent "$artifact_url" --output "$archive_path"
  fi

  actual_checksum="$(swift package compute-checksum "$archive_path")"
  if [ "$actual_checksum" != "$expected_checksum" ]; then
    if [ -f "$cache_file" ]; then
      echo "Cached $target_name artifact checksum mismatch; downloading a fresh copy."
      curl --fail --location --show-error --silent "$artifact_url" --output "$archive_path"
      actual_checksum="$(swift package compute-checksum "$archive_path")"
    fi

    if [ "$actual_checksum" != "$expected_checksum" ]; then
      echo "FAIL: $target_name artifact checksum mismatch." >&2
      echo "  expected: $expected_checksum" >&2
      echo "  actual:   $actual_checksum" >&2
      exit 1
    fi
  fi

  mkdir -p "$unpack_dir"
  ditto -x -k "$archive_path" "$unpack_dir"

  source_framework="$(find "$unpack_dir" -maxdepth 2 -type d -name "$target_name.xcframework" -print -quit)"
  if [ -z "$source_framework" ]; then
    echo "FAIL: $target_name.xcframework not found after unpacking $archive_path" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$artifact_path")"
  rm -rf "$artifact_path"
  ditto "$source_framework" "$artifact_path"
  echo "Hydrated $target_name XCFramework at $artifact_path"
  hydrated_count=$((hydrated_count + 1))
done <<<"$BINARY_TARGETS"

if [ ! -d "$STATIC_ARTIFACT_PATH" ]; then
  echo "FAIL: Sentry artifact hydration finished but $STATIC_ARTIFACT_PATH is still missing" >&2
  exit 1
fi

if [ "$hydrated_count" -eq 0 ]; then
  echo "Sentry XCFramework artifacts already hydrated under $SOURCE_PACKAGES_PATH/artifacts/sentry-cocoa"
else
  echo "Hydrated $hydrated_count Sentry XCFramework artifact(s)."
fi

# Xcode can report a freshly hydrated SwiftPM binary artifact as missing for a
# moment immediately after project regeneration. Keep the pause centralized so
# all build/test scripts get the same deterministic behavior.
settle_seconds="${VOLUMEARC_SENTRY_ARTIFACT_SETTLE_SECONDS:-3}"
if [ "$settle_seconds" != "0" ]; then
  sleep "$settle_seconds"
fi
