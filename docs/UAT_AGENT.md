# Exploratory UAT Agent

`VOL-169` adds a nightly, LLM-driven exploratory UAT lane for the iOS app. It does not replace the PR XCUITest journey suite; it is the asynchronous backstop that tries fuzzy user stories against a fresh deterministic app launch and reports suspicious states.

## What Runs

- Workflow: `.github/workflows/uat-agent-nightly.yml`
- Harness script: `scripts/run_uat_agent.sh`
- XCUITest bridge: `VolumeArcExploratoryUATAgentTests/testNightlyExploratoryStories`
- Story prompts: `Tests/UATAgentStories/nightly.json`

Each story launches the app in `-UITestMode 1` with seeded fixtures and optional tab-selection launch args. At each step the bridge captures:

- the app accessibility tree (`XCUIApplication().debugDescription`)
- a screenshot attachment
- the previous action transcript

The model receives that state through the OpenAI Responses API and returns one bounded JSON action: `tap`, `typeText`, `swipe`, `wait`, or `finish`. The bridge executes only safe in-app actions; destructive actions, purchases, sign-out, external links, and system permission prompts are out of scope.

## Reports

The test emits `report.json` and attaches screenshots/JSON to the xcresult bundle. The workflow also builds `report.md`, uploads both files as artifacts, and posts a sticky GitHub issue report titled `Nightly exploratory UAT report`.

By default, high-severity anomalies fail the workflow after the report is published:

```bash
UAT_AGENT_FAIL_ON_HIGH=1 ./scripts/run_uat_agent.sh
```

Local compile/smoke validation without an API key:

```bash
UAT_AGENT_DRY_RUN=1 ./scripts/run_uat_agent.sh
```

## Configuration

The nightly workflow consumes an `OPENAI_API_KEY` repository secret and defaults to `gpt-5.5`. The request uses `store: false`; screenshots are passed as PNG data URLs with low detail to keep nightly token usage bounded.

Manual dispatch supports:

- `max_steps` - max model actions per story, default `5`
- `fail_on_high` - whether high anomalies fail the workflow, default `1`

The runner cleans its dedicated DerivedData path by default to avoid stale simulator signing artifacts. Set `UAT_AGENT_CLEAN_DERIVED_DATA=0` for faster local reruns when the cache is known-good.

## Story Contract

`Tests/UATAgentStories/nightly.json` must contain at least five story objects:

```json
{
  "id": "coach-recovery-question",
  "prompt": "Ask Coach for advice after a hard session...",
  "launchArguments": ["-OpenCoachOnLaunch", "1"]
}
```

The prompts should cover surfaces or cross-surface combinations that deterministic journeys do not fully exercise. Keep them launch-safe and bounded; the model chooses the path, but the test still owns the guardrails.
