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
