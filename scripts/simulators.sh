#!/usr/bin/env bash

resolve_ios_test_device() {
  local requested="${IOS_TEST_DEVICE:-iPhone 17}"
  local mode="${1:-allow-fallback}"

  if xcrun simctl list devices available \
    | awk -v requested="$requested" '
        /^[[:space:]]+iPhone / && $0 !~ /unavailable/ {
          name = $0
          sub(/^[[:space:]]+/, "", name)
          sub(/[[:space:]][(].*/, "", name)
          if (name == requested) {
            found = 1
          }
        }
        END { exit found ? 0 : 1 }
      '; then
    echo "$requested"
    return
  fi

  if [[ "$mode" == "--no-fallback" ]]; then
    echo "::error::Requested iOS simulator '$requested' not found" >&2
    exit 1
  fi

  local fallback
  fallback="$(
    xcrun simctl list devices available \
      | awk '/^[[:space:]]+iPhone / && $0 !~ /unavailable/ {
          sub(/^[[:space:]]+/, "");
          sub(/[[:space:]][(].*/, "");
          print;
          exit
        }'
  )"
  if [[ -z "$fallback" ]]; then
    echo "::error::No available iPhone simulator found" >&2
    exit 1
  fi

  echo "::warning::Requested iOS simulator '$requested' not found; using '$fallback'" >&2
  echo "$fallback"
}

# VOL-138: companion resolver for the watchOS unit test bundle. Returns
# the name of an available Apple Watch simulator (preferring
# `WATCHOS_TEST_DEVICE` env, falling back to any available Series-class
# watch). If no watch sim is available at all — the CI runner's
# simulator inventory churns and may transiently lack one — creates a
# fresh one against the latest watchOS runtime so the test step is
# self-healing instead of failing with "no destinations matched."
resolve_watch_test_device() {
  local requested="${WATCHOS_TEST_DEVICE:-Apple Watch Series 11 (46mm)}"
  local mode="${1:-allow-fallback}"

  if xcrun simctl list devices available \
    | awk -v requested="$requested" '
        /^[[:space:]]+Apple Watch / && $0 !~ /unavailable/ {
          name = $0
          sub(/^[[:space:]]+/, "", name)
          sub(/[[:space:]][(][0-9A-F-]{36}[)].*/, "", name)
          sub(/[[:space:]]+$/, "", name)
          if (name == requested) {
            found = 1
          }
        }
        END { exit found ? 0 : 1 }
      '; then
    echo "$requested"
    return
  fi

  if [[ "$mode" == "--no-fallback" ]]; then
    echo "::error::Requested watchOS simulator '$requested' not found" >&2
    exit 1
  fi

  local fallback
  fallback="$(
    xcrun simctl list devices available \
      | awk '/^[[:space:]]+Apple Watch / && $0 !~ /unavailable/ {
          sub(/^[[:space:]]+/, "");
          sub(/[[:space:]][(][0-9A-F-]{36}[)].*/, "");
          sub(/[[:space:]]+$/, "");
          print;
          exit
        }'
  )"

  if [[ -n "$fallback" ]]; then
    echo "::warning::Requested watchOS simulator '$requested' not found; using '$fallback'" >&2
    echo "$fallback"
    return
  fi

  # Last resort: create a watch sim. CI runner images can transiently
  # lack any watch sim if a prior job deleted the device inventory.
  # `simctl create` is idempotent against the device-type / runtime
  # pair; we use the latest available watchOS runtime.
  local latest_watch_runtime
  latest_watch_runtime="$(
    xcrun simctl list runtimes available \
      | awk '/watchOS/ {print $NF}' \
      | sort -V \
      | tail -n 1
  )"
  if [[ -z "$latest_watch_runtime" ]]; then
    echo "::error::No watchOS runtimes installed; cannot create a watch sim" >&2
    exit 1
  fi

  local created_name="VolumeArc-Watch-Test"
  echo "::warning::No Apple Watch sim available; creating '$created_name' against $latest_watch_runtime" >&2
  if ! xcrun simctl create "$created_name" \
        "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm" \
        "$latest_watch_runtime" >/dev/null 2>&1; then
    echo "::error::Failed to create watch simulator '$created_name'" >&2
    exit 1
  fi
  echo "$created_name"
}
