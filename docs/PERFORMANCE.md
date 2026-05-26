# Performance budgets (VOL-99)

This document is the human-readable companion to [`performance-budgets.json`](performance-budgets.json). The JSON file is the machine-readable source of truth — the perf-regression gate (`scripts/check_performance.sh`) parses it directly, so keep the two in sync when a budget moves.

## Budget table

All measurements are taken on an **iPhone 17 iOS Simulator** running the host `VolumeArcApp` bundle with `-PerfTestMode 1` launch arguments (deterministic seed, 50-session history pool).

| ID | Metric | Budget | Fail threshold | Source |
|---|---|---|---|---|
| `cold_launch` | Cold-launch wall clock (XCTApplicationLaunchMetric) | 1.2s | 1.44s (+20%) | VOL-99 Linear |
| `today_scroll_frame_rate` | Today scroll mean frame rate | >= 58 fps | < 46 fps (-20%) | VOL-99 Linear |
| `today_scroll_hitches` | Today scroll hitches per second | < 2/s | > 2.4/s (+20%) | VOL-99 Linear |
| `memory_footprint_workout` | Memory footprint during a workout iteration | < 150 MB | > 180 MB (+20%) | VOL-99 Linear |
| `coach_first_token_p50` | Coach first-token latency P50 | < 800 ms | > 960 ms (+20%) | VOL-99 Linear |
| `coach_first_token_p95` | Coach first-token latency P95 | < 2000 ms | > 2400 ms (+20%) | VOL-99 Linear |

## How it runs

1. **Local:** `./scripts/test_performance.sh` regenerates the Xcode project, boots an iPhone 17 simulator, and runs the `VolumeArcAppPerfTests` scheme with `-enablePerformanceTestsDiagnostics YES`. The resulting `.xcresult` bundle lands under `.build/perf-results.xcresult`.
2. **Gate:** `./scripts/check_performance.sh` parses the bundle with `xcrun xcresulttool get-result-bundle --format json`, extracts each metric's mean / percentiles, and compares against `performance-budgets.json`. A metric above `failThreshold` exits nonzero.
3. **Trend:** on success, the same script appends a new entry to `performance-trend.json` with the commit SHA, ref, and measured values. The file is committed back by CI so the project's perf history is visible in git.
4. **CI:** the suite runs as a hard gate on **tag builds** (`on: push: tags: ['v*']`) and as a warning-only signal on same-repo PRs after the normal Build & Test job — see the `perf-regression` job in `.github/workflows/ci.yml`. PR runs set `PERF_SKIP_TREND_WRITE=1` so they surface drift in the job summary without mutating `docs/performance-trend.json`.

## Bundle Size Signals

Release/archive size is still measured from the exported IPA by `scripts/check_ipa_size.sh`. That gate uses the `ipa_size_*` and `app_size_*` metrics in `performance-budgets.json` and should run only after a real archive/export because compression, signing, and device slices matter.

Pull requests get a lighter proxy via `scripts/check_pr_size_proxy.sh`. The separate `PR bundle size proxy (VOL-215)` CI job runs `scripts/build_all_targets.sh`, measures the Debug simulator products under `.build/derived-data`, and compares the `pr_size_proxy_*` metrics in `performance-budgets.json`. This is a non-required PR signal meant to catch obvious asset or dependency bloat before a release archive; it does not replace the signed IPA measurement.

## Test anatomy

The four measurement tests live in `Tests/VolumeArcAppPerfTests/VolumeArcPerfTests.swift`:

- `testColdLaunchTime()` — `XCTApplicationLaunchMetric`, 5 iterations. Each iteration tears down the app process and re-launches, which is the closest XCTest gets to a true cold launch.
- `testTodayScrollPerformance()` — `XCTOSSignpostMetric.scrollDraggingAnimation` + `XCTMemoryMetric`. Performs 5 swipe-ups and 5 swipe-downs on the Today tab's `ScrollView`. The 50-session fixture pool is populated by `-PerfTestMode 1` via the launch bootstrapper.
- `testMemoryFootprintDuringWorkout()` — `XCTMemoryMetric`, 3 iterations. Compresses "5 minutes" into 45s per iteration while the Workouts tab's rest timer runs; long enough to capture real steady-state, short enough to keep CI bounded.
- `testCoachFirstTokenLatency()` — `XCTClockMetric`, 5 iterations. Taps the Ask Coach quick action, types a prompt, taps Send, and waits for the first coach bubble to have non-empty content (`coach.firstResponse` accessibility identifier is only assigned once content arrives). In perf-mode the coach runs the `LocalHeuristicAICoachProvider` fallback so the test is hermetic — no relay dependency.

## Budget provenance

All budgets in this file trace directly back to the VOL-99 acceptance criteria. Any change to a budget needs a Linear ticket — update `performance-budgets.json` in the same PR so the gate tracks the new number.

## Related

- [`TESTING.md`](TESTING.md) — general test architecture and how the perf suite fits in.
- [`PLATFORM.md`](PLATFORM.md) — canonical status table (includes Performance testing row).
