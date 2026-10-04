#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Apple preflight requires macOS" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit the candidate before qualification" >&2; exit 1; }
command -v ruby >/dev/null
ruby -rxcodeproj -e 'puts Xcodeproj::VERSION'
./scripts/test_xcode_project_regen_idempotent.sh
./scripts/test_xcode_project_determinism.sh
ruby scripts/test_watch_app_embedding.rb
ruby scripts/validate_watch_app_icon_asset.rb
./scripts/validate_release_config.sh --no-build
swiftlint --strict
printf 'Static Apple preflight passed for %s. Run VOL-PR/VOL-Main build, unit/UI and device tests locally before manual Xcode Cloud admission.\n' "$(git rev-parse HEAD)"
