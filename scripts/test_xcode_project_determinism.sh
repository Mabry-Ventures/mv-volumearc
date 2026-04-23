#!/usr/bin/env bash
# VOL-95: verify that `ruby scripts/generate_xcode_project.rb` produces
# byte-identical output on every run.
#
# The xcodeproj gem otherwise assigns random UUIDs via SecureRandom on
# every object creation, which would thrash all ~360 pbxproj object
# UUIDs plus every scheme's BlueprintIdentifier on each regeneration.
# That makes merges a game of whack-a-mole.
#
# The generator monkey-patches `Xcodeproj::Project::UUIDGenerator` and
# calls `predictabilize_uuids` twice before `project.save` (see comments
# in `scripts/generate_xcode_project.rb`). This script proves the result
# is deterministic by regenerating twice and comparing hashes.
#
# Runs from CI so a regression fails loudly instead of silently
# re-introducing the merge-conflict churn this ticket closed.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="VolumeArcApple.xcodeproj"
FIRST_HASH_FILE="$(mktemp)"
SECOND_HASH_FILE="$(mktemp)"
trap 'rm -f "$FIRST_HASH_FILE" "$SECOND_HASH_FILE"' EXIT

hash_project() {
  local target="$1"
  shasum -a 256 "$PROJECT/project.pbxproj" > "$target"
  # xcscheme files live in xcshareddata/xcschemes. Sort so the order is
  # stable regardless of filesystem enumeration order.
  find "$PROJECT/xcshareddata/xcschemes" -name '*.xcscheme' -print0 \
    | sort -z \
    | xargs -0 shasum -a 256 \
    >> "$target"
}

echo "==> Run 1: regenerating Xcode project..."
rm -rf "$PROJECT"
ruby scripts/generate_xcode_project.rb > /dev/null
hash_project "$FIRST_HASH_FILE"

echo "==> Run 2: regenerating Xcode project..."
rm -rf "$PROJECT"
ruby scripts/generate_xcode_project.rb > /dev/null
hash_project "$SECOND_HASH_FILE"

echo "==> Comparing SHA256 hashes..."
if diff -u "$FIRST_HASH_FILE" "$SECOND_HASH_FILE"; then
  echo "OK: Xcode project generation is deterministic."
  echo ""
  echo "Hashes:"
  cat "$FIRST_HASH_FILE"
  exit 0
else
  echo ""
  echo "FAIL: Regenerating produced different output."
  echo "Something in scripts/generate_xcode_project.rb has re-introduced"
  echo "non-deterministic UUID assignment. See VOL-95 for background."
  exit 1
fi
