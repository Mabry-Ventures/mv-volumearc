#!/usr/bin/env bash
# Wraps each PNG in App/Assets.xcassets/ExerciseIllustrations/ as a SwiftUI-loadable imageset.
# Idempotent — safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT/App/Assets.xcassets/ExerciseIllustrations"

cd "$DIR"

# Move loose PNGs into per-exercise .imageset folders.
for png in *.png; do
    [ -f "$png" ] || continue
    id="${png%.png}"
    imageset="${id}.imageset"
    mkdir -p "$imageset"
    mv "$png" "$imageset/"
    cat > "$imageset/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "${id}.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
done

# Group-level Contents.json so Xcode treats this directory as a folder of assets.
cat > Contents.json <<JSON
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "provides-namespace" : true
  }
}
JSON

echo "Wrapped $(ls -d *.imageset | wc -l | tr -d ' ') imagesets in $DIR"
