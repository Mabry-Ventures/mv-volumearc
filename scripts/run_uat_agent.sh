#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data-uat-agent}"
RUN_DIR="${UAT_AGENT_OUTPUT_DIR:-$ROOT/.build/uat-agent}"
STORIES_FILE="${UAT_AGENT_STORIES_FILE:-$ROOT/Tests/UATAgentStories/nightly.json}"
MAX_STEPS="${UAT_AGENT_MAX_STEPS:-5}"
MODEL="${UAT_AGENT_MODEL:-gpt-5.5}"
DRY_RUN="${UAT_AGENT_DRY_RUN:-0}"
FAIL_ON_HIGH="${UAT_AGENT_FAIL_ON_HIGH:-1}"

mkdir -p "$DERIVED_DATA_PATH" "$RUN_DIR"

if [[ ! -f "$STORIES_FILE" ]]; then
  echo "::error::UAT agent stories file missing: $STORIES_FILE" >&2
  exit 66
fi

stories_json="$(
  ruby -rjson -rtime -e '
    path = ARGV.fetch(0)
    stories = JSON.parse(File.read(path))
    unless stories.is_a?(Array) && stories.length >= 5
      abort("UAT agent requires at least 5 story prompts")
    end
    print(JSON.generate(stories))
  ' "$STORIES_FILE"
)"

if [[ "$DRY_RUN" != "1" && -z "${OPENAI_API_KEY:-}" ]]; then
  echo "::error::OPENAI_API_KEY is required unless UAT_AGENT_DRY_RUN=1" >&2
  exit 78
fi

. "$ROOT/scripts/simulators.sh"
IOS_TEST_DEVICE_NAME="$(resolve_ios_test_device)"

REPORT_PATH="$RUN_DIR/report.json"
LOG_PATH="$RUN_DIR/xcodebuild.log"
RESULT_BUNDLE="$RUN_DIR/ExploratoryUATAgent.xcresult"
rm -f "$REPORT_PATH" "$LOG_PATH"
rm -rf "$RESULT_BUNDLE"

enabled="1"
if [[ "$DRY_RUN" = "1" ]]; then
  enabled="0"
fi

echo "Running VOL-169 exploratory UAT agent"
echo "  model: $MODEL"
echo "  stories: $STORIES_FILE"
echo "  max steps/story: $MAX_STEPS"
echo "  simulator: $IOS_TEST_DEVICE_NAME"
echo "  dry run: $DRY_RUN"

set +e
env \
  UAT_AGENT_ENABLED="$enabled" \
  UAT_AGENT_MODEL="$MODEL" \
  UAT_AGENT_MAX_STEPS="$MAX_STEPS" \
  UAT_AGENT_STORIES_JSON="$stories_json" \
  UAT_AGENT_OUTPUT_PATH="$REPORT_PATH" \
  xcodebuild \
    -project "VolumeArcApple.xcodeproj" \
    -scheme "VolumeArcAppUITests" \
    -destination "platform=iOS Simulator,name=$IOS_TEST_DEVICE_NAME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 600 \
    -maximum-test-execution-time-allowance 900 \
    -only-testing:VolumeArcAppUITests/VolumeArcExploratoryUATAgentTests/testNightlyExploratoryStories \
    CODE_SIGNING_ALLOWED=NO \
    test 2>&1 | tee "$LOG_PATH"
xcode_status="${PIPESTATUS[0]}"
set -e

if [[ ! -s "$REPORT_PATH" ]]; then
  awk '
    /UAT_AGENT_REPORT_JSON_BEGIN/ { capture = 1; next }
    /UAT_AGENT_REPORT_JSON_END/ { capture = 0 }
    capture == 1 { print }
  ' "$LOG_PATH" > "$REPORT_PATH"
fi

if [[ "$DRY_RUN" = "1" && ! -s "$REPORT_PATH" ]]; then
  ruby -rjson -rtime -e '
    puts JSON.pretty_generate({
      generatedAt: Time.now.utc.iso8601,
      model: ENV.fetch("UAT_AGENT_MODEL", "gpt-5.5"),
      dryRun: true,
      stories: [],
      summary: {
        totalStories: 0,
        highAnomalies: 0,
        mediumAnomalies: 0,
        lowAnomalies: 0
      }
    })
  ' > "$REPORT_PATH"
fi

if [[ ! -s "$REPORT_PATH" ]]; then
  echo "::error::UAT agent did not produce $REPORT_PATH" >&2
  exit "${xcode_status:-1}"
fi

ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$REPORT_PATH"

high_count="$(
  ruby -rjson -e '
    report = JSON.parse(File.read(ARGV.fetch(0)))
    puts(report.dig("summary", "highAnomalies").to_i)
  ' "$REPORT_PATH"
)"
medium_count="$(
  ruby -rjson -e '
    report = JSON.parse(File.read(ARGV.fetch(0)))
    puts(report.dig("summary", "mediumAnomalies").to_i)
  ' "$REPORT_PATH"
)"

echo "UAT agent report: $REPORT_PATH"
echo "UAT agent xcresult: $RESULT_BUNDLE"
echo "Anomalies: high=$high_count medium=$medium_count"

if [[ "$xcode_status" != "0" ]]; then
  exit "$xcode_status"
fi

if [[ "$FAIL_ON_HIGH" = "1" && "$high_count" -gt 0 ]]; then
  echo "::error::VOL-169 exploratory UAT found $high_count high-severity anomaly/anomalies" >&2
  exit 2
fi
