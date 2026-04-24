#!/usr/bin/env bash
# VOL-106: verify that `ruby scripts/generate_xcode_project.rb` against the
# committed Xcode project is a true no-op -- zero diff after regeneration.
#
# Distinct from `scripts/test_xcode_project_determinism.sh`, which proves
# two fresh runs match each other. That check can pass while the committed
# pbxproj has silently drifted from what the generator now produces (e.g.
# because a generator input depended on git state, or a contributor added
# a source file without regenerating). This script is the missing gate:
# it catches drift between the committed project and the generator.
#
# A failing run means one of:
#  - a source file was added/removed without running the generator,
#  - the generator script was changed without regenerating the project,
#  - or a volatile input snuck back into the generator
#    (see VOL-106 for how the BUILD_NUMBER git-count input was pinned away,
#    and VOL-95 / commit db92f37 for the original deterministic-gen
#    scaffolding this extends).
#
# Fix: run `ruby scripts/generate_xcode_project.rb` and commit the result.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="VolumeArcApple.xcodeproj"

echo "==> Regenerating Xcode project over committed state..."
ruby scripts/generate_xcode_project.rb > /dev/null

echo "==> Checking for drift against committed project..."
# Compare explicitly against HEAD (not the index) so a developer who
# pre-staged the regen locally still sees the honest "diff vs committed"
# signal this gate is supposed to produce.
if git diff --quiet HEAD -- "$PROJECT"; then
  echo "OK: regeneration is a no-op against the committed $PROJECT."
  exit 0
fi

echo ""
echo "FAIL: regenerating produced a diff against the committed project."
echo "The committed $PROJECT has drifted from what the generator now produces."
echo ""
echo "Run:"
echo "  ruby scripts/generate_xcode_project.rb"
echo "and commit the result."
echo ""
echo "Drift summary:"
git --no-pager diff --stat HEAD -- "$PROJECT"
exit 1
