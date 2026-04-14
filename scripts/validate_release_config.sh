#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb" >/dev/null

PROJECT="VolumeArcApple.xcodeproj/project.pbxproj"

for path in \
  "App/VolumeArc.entitlements" \
  "Watch/VolumeArcWatch.entitlements" \
  "WatchWidgets/VolumeArcWatchWidgets.entitlements" \
  "Widgets/VolumeArcWidgets.entitlements"; do
  [[ -f "$path" ]] || {
    echo "Missing required entitlement file: $path" >&2
    exit 1
  }
done

for path in \
  "App/PrivacyInfo.xcprivacy" \
  "Watch/PrivacyInfo.xcprivacy" \
  "WatchWidgets/PrivacyInfo.xcprivacy" \
  "Widgets/PrivacyInfo.xcprivacy"; do
  [[ -f "$path" ]] || {
    echo "Missing required privacy manifest: $path" >&2
    exit 1
  }
done

if ! grep -q "aps-environment" "App/VolumeArc.entitlements"; then
  echo "WARNING: aps-environment not found in App/VolumeArc.entitlements — push notifications will not work" >&2
fi

for forbidden in "DemoFixtures" "DemoServices" "VolumeArcDemoSupport"; do
  if rg -n "$forbidden" "$PROJECT" >/dev/null; then
    echo "Generated Xcode project unexpectedly references demo-only symbol: $forbidden" >&2
    exit 1
  fi
done

tmp_settings="$(mktemp)"
trap 'rm -f "$tmp_settings"' EXIT

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcApp" \
  -configuration Release \
  -showBuildSettings >"$tmp_settings"

required_build_settings=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc"
  "CODE_SIGN_ENTITLEMENTS = App/VolumeArc.entitlements"
  "INFOPLIST_KEY_NSHealthShareUsageDescription = VolumeArc reads your workout and recovery data to personalize progression, readiness, and session planning."
  "INFOPLIST_KEY_NSHealthUpdateUsageDescription = VolumeArc writes completed workouts so your training history stays in sync with Apple Health."
  "INFOPLIST_KEY_NSMicrophoneUsageDescription = VolumeArc uses the microphone for live duplex coaching and voice workout logging."
  "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = VolumeArc uses speech recognition to understand live coaching requests and voice workout notes."
  "INFOPLIST_KEY_VolumeArcCloudKitContainer = iCloud.com.mabryventures.VolumeArc"
)

for required in "${required_build_settings[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required app build setting: $required" >&2
    exit 1
  fi
done

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcWatch" \
  -configuration Release \
  -showBuildSettings >"$tmp_settings"

watch_required=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc.watchkitapp"
  "CODE_SIGN_ENTITLEMENTS = Watch/VolumeArcWatch.entitlements"
  "INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.mabryventures.VolumeArc"
)

for required in "${watch_required[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required watch build setting: $required" >&2
    exit 1
  fi
done

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcWidgets" \
  -configuration Release \
  -showBuildSettings >"$tmp_settings"

widget_required=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc.widgets"
  "CODE_SIGN_ENTITLEMENTS = Widgets/VolumeArcWidgets.entitlements"
  "INFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier = com.apple.widgetkit-extension"
)

for required in "${widget_required[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required widget build setting: $required" >&2
    exit 1
  fi
done

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcAppTests" \
  -configuration Debug \
  -showBuildSettings >"$tmp_settings"

test_required=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc.tests"
)

for required in "${test_required[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required app-test build setting: $required" >&2
    exit 1
  fi
done

# --- Deep release checks (added by audit VOL-14) ---

# Re-read app Release build settings for deeper checks
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcApp" \
  -configuration Release \
  -showBuildSettings >"$tmp_settings"

# ENABLE_TESTABILITY should be NO in Release (allows debugger injection if YES)
if grep -F "ENABLE_TESTABILITY = YES" "$tmp_settings" >/dev/null 2>&1; then
  echo "WARNING: ENABLE_TESTABILITY is YES in Release — consider setting to NO for production" >&2
fi

# Verify dSYM generation for crash reporting
if ! grep -F "DEBUG_INFORMATION_FORMAT = dwarf-with-dsym" "$tmp_settings" >/dev/null 2>&1; then
  echo "WARNING: DEBUG_INFORMATION_FORMAT should be dwarf-with-dsym in Release for crash reporting" >&2
fi

# VERSION file should exist
[[ -f "VERSION" ]] || {
  echo "Missing VERSION file at repo root" >&2
  exit 1
}

# Version bump check: if git tags exist, verify VERSION differs from latest tag
if git describe --tags --abbrev=0 >/dev/null 2>&1; then
  latest_tag="$(git describe --tags --abbrev=0)"
  current_version="$(cat VERSION | tr -d '[:space:]')"
  tag_version="${latest_tag#v}"
  if [[ "$current_version" == "$tag_version" ]]; then
    echo "WARNING: VERSION ($current_version) matches latest tag ($latest_tag) — bump VERSION before release" >&2
  fi
fi

echo "Release configuration validation passed."
