# Testing

## Test architecture

VolumeArc currently ships with **540+ test functions** across unit + integration + XCUITest journey + performance suites (audited 2026-05-22; count: `find Tests -name '*.swift' -exec grep -h 'func test' {} \; | wc -l`). The headline shapes:

- 80% line-coverage gate enforced on `VolumeArcCore` (VOL-52), targeted to rise to **90%** under [VOL-140](https://linear.app/mabry-ventures/issue/VOL-140) (sharpened by [VOL-205](https://linear.app/mabry-ventures/issue/VOL-205)). New gates: `VolumeArcUI` (≥85% target, **18%** staged floor after the VOL-135 snapshot ratchet), `VolumeArcCoreWatch` (≥85% target, **25%** Phase A floor — measured baseline 28.77% from [VOL-138](https://linear.app/mabry-ventures/issue/VOL-138) Phase A; ratchets up once `WatchWorkoutModel` pure logic is extracted), Widgets (≥75% target — view-layer snapshot coverage started under [VOL-139](https://linear.app/mabry-ventures/issue/VOL-139); line-coverage gate remains pending a dedicated target).
- 6-metric performance budget (cold launch, scroll fps, scroll hitches, memory, coach P50, coach P95) tag-gated in CI (VOL-99).
- 20-fixture coach eval matrix with hermetic template-layer assertions in CI; response-layer harness runs on nightly cron (`coach-evals-nightly.yml`) targeting `relay.volumearc.app` after VOL-223 fixed the dead default URL.
- User-journey catalog at [`USER_JOURNEYS.md`](USER_JOURNEYS.md); current coverage **18%** (11/62), target **100%** under [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141) (sharpened by [VOL-200](https://linear.app/mabry-ventures/issue/VOL-200) — CI parser gate).
- Visual regression: SnapshotTesting is wired with bundled baselines for VAButton, the next-workout widget, core VAUI card/toast surfaces, the active-workout Live Activity lock-screen/banner and watch surfaces, coach transcript bubbles, and the Premium paywall loaded-empty/failure shell; onboarding, RootDashboard tab, and remaining Live Activity matrices continue under [VOL-135](https://linear.app/mabry-ventures/issue/VOL-135).

```
Tests/VolumeArcAppTests/
├── Evals/
│   └── CoachEvalTests.swift                      # 3 tests (template-layer eval harness, VOL-100)
├── Exercise/
│   └── ExerciseCatalogTests.swift                # 19 tests
├── TestSupport/
│   ├── Fixtures.swift                            # Shared deterministic fixtures
│   ├── Mocks.swift                               # Protocol-boundary doubles and helpers
│   └── MocksUsageSmokeTests.swift                # 12 tests
├── FeatureFlagProviderTests.swift                # 10 tests (VOL-61 runtime gating)
├── VolumeArcAppConfigurationTests.swift          # 10 tests
├── VolumeArcCloudSyncTests.swift                 # 39 tests (post VOL-74 split)
├── VolumeArcCoachMemoryRetentionTests.swift      # 5 tests
├── VolumeArcCoachPromptTemplateTests.swift       # 6 tests
├── VolumeArcCoreCoverageTests.swift              # 63 tests (targets the 80% gate)
├── VolumeArcDashboardIntegrationTests.swift      # 13 tests, @MainActor, in-memory SwiftData
├── VolumeArcMaterialsTests.swift                 # 5 tests (Liquid Glass fallback — VOL-69)
├── VolumeArcMigrationTests.swift                 # 21 tests
├── VolumeArcPersistenceTests.swift               # 10 tests, real VolumeArcPersistenceController
├── VolumeArcProgressionTests.swift               # 8 tests
├── VolumeArcReadinessTests.swift                 # 6 tests
├── VolumeArcRelaySessionTests.swift              # 8 tests, real VolumeArcRelaySessionProvider
├── VolumeArcRelayURLValidationTests.swift        # 17 tests
├── VolumeArcSecureStoreFallbackTests.swift       # 5 tests
└── VolumeArcSentryPIIScrubberTests.swift         # 33 tests (VOL-72)

Tests/VolumeArcAppUITests/
├── VolumeArcAppUITests.swift                     # launch/navigation smoke tests
├── VolumeArcAppJourneyTests.swift                # onboarding, paywall, StoreKit, workout journey
├── VolumeArcAccessibilityJourneyTests.swift      # Dynamic Type + pseudo-locale sweep
├── VolumeArcHealthKitPermissionJourneyTests.swift # HealthKit permission prompt simulation
├── VolumeArcWatchSimulationJourneyTests.swift    # deterministic Watch payload simulation
└── VolumeArcScreenshotTests.swift                # fastlane App Store screenshots

Tests/VolumeArcAppPerfTests/
└── VolumeArcPerfTests.swift                      # 4 performance-regression tests (VOL-99)

Tests/VolumeArcWidgetUITests/                     # VOL-139 Phase A — widget XCUITest target
└── VolumeArcWidgetUITests.swift                  # 2 smoke tests (host + WidgetKit linkage)

Tests/VolumeArcWatchTests/                        # VOL-138 Phase A — watchOS unit bundle
├── WatchPayloadCodecTests.swift                  # 8 tests (dict + Codable round-trip)
├── WatchPendingPayloadStoreTests.swift           # 7 tests (offline-replay queue)
└── WatchConnectivityCoordinatorTests.swift       # 9 tests (send / queue / flush, FakeTransport)
```

A `.swiftlint.yml` under `Tests/` scopes length and implicit-unwrap rules out of the test directory so `sut` + fixture force-unwraps don't get flagged as production bugs.

The XCUITest and PerfTests targets are real first-class targets generated by `scripts/generate_xcode_project.rb`. Their `TEST_TARGET_NAME` is wired to `VolumeArcApp`, so the UI / perf suites launch the shipping iOS app bundle rather than a duplicate host.

## Running tests

```bash
./scripts/test_apple_targets.sh
```

That script regenerates the Xcode project and runs all three test schemes:

- `VolumeArcAppTests` — unit + integration coverage (single xcodebuild invocation, produces `TestResults.xcresult`)
- `VolumeArcWatchTests` — VOL-138 Phase A watchOS unit bundle covering `WatchPayload` / `WatchSessionSnapshot` codec, `UserDefaultsWatchPendingPayloadStore`, and `WatchConnectivityCoordinator` (watch simulator; `resolve_watch_test_device` in `scripts/simulators.sh` self-heals if no watch sim is installed)
- `VolumeArcAppUITests` — XCUITest journey coverage, **sharded** into four partitions that run sequentially with per-shard simulator warm-up and retry budget (VOL-231; see [XCUITest sharding](#xcuitest-sharding-vol-231))

Or via Xcode: run `VolumeArcAppTests`, `VolumeArcWatchTests`, or `VolumeArcAppUITests` directly with the corresponding scheme selected.

### Watch test target (VOL-138)

The Watch surface is positioned as first-class in `docs/PRODUCT_POSITIONING.md`, which means the same tier of unit coverage applied to the iOS slice of `VolumeArcCore` belongs on the watchOS slice (`VolumeArcCoreWatch`). The Phase A bundle exercises the connectivity / payload / queue types compiled against the watchOS SDK so a Foundation behavior change between iOS and watchOS (Codable `Date` encoding, UserDefaults serialization, actor isolation semantics) is caught at the right platform layer.

Phase A landed 24 tests covering the codec + offline replay queue + reachability state machine, measured at **28.77%** line coverage on `VolumeArcCoreWatch`. The CI gate sits at **25%** as a staged-ratchet floor.

Phase B/C (long-term path to the 85% target from the VOL-138 acceptance criteria):
- Extract `WatchWorkoutModel` pure logic (rest-timer math, set-decision flow, coach-cue request lifecycle) into watch-only source files inside `VolumeArcCore` so they ship in `VolumeArcCoreWatch` but not in the iOS `VolumeArcCore` build.
- Cover the extracted logic with hermetic tests in `Tests/VolumeArcWatchTests/`.
- Ratchet the gate up to 85% in the same PR.

### XCUITest sharding (VOL-231)

The UI test target runs as four shards instead of one mega-invocation. Each shard gets its own `xcodebuild` call, its own `TestResults-ui-<shard>.xcresult` bundle, and a fresh `warm_simulator_for_tests` (boot + AX-daemon kick) before it starts:

| Shard                       | Classes                                                                                                                                                          | Why                                                                                                                                |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `smoke`                     | `VolumeArcAppUITests`, `VolumeArcTelemetryProbeMatcherTests`                                                                                                     | Fast regression detection; matcher parsing isolated from full-app journeys                                                         |
| `journeys-core`             | `VolumeArcAppJourneyTests`, `VolumeArcCoachJourneyTests`, `VolumeArcTodayJourneyTests`                                                                           | Heaviest user-flow journeys; isolating them keeps a single hang from the parent journey suite from poisoning lighter shards        |
| `journeys-aux`              | `VolumeArcProfileJourneyTests`, `VolumeArcFeedbackJourneyTests`, `VolumeArcSignalsJourneyTests`, `VolumeArcHealthKitPermissionJourneyTests`, `VolumeArcWatchSimulationJourneyTests`, `VolumeArcChaosJourneyTests` | Mid-cost flows + permission-dialog interrupts + chaos / watch-simulation                                                          |
| `accessibility-screenshots` | `VolumeArcAccessibilityJourneyTests`, `VolumeArcScreenshotTests`                                                                                                 | Known AX-daemon wedge cause (`accessibility5` + `NSDoubleLocalizedStrings`); when the daemon dies, the wedge stays inside this shard |

The shard map lives in `scripts/test_apple_targets.sh` (`UI_SHARDS` + `ui_shard_classes`). A `verify_shard_coverage` gate at the top of the UI test block fails the build if you add a new `XCTestCase` class and forget to assign it to a shard — so a forgotten class can't silently stop running in CI.

**Local diagnostics.** Run a single shard while iterating on a flake:

```bash
SHARD_FILTER=accessibility-screenshots ./scripts/test_apple_targets.sh
```

`SHARD_FILTER` skips every shard whose name doesn't match. Unit tests still run first (they're not currently filterable; if you need to skip them locally, edit the script).

**Failure semantics.** Shards run independently — if shard 1 fails, shards 2-4 still execute so you get a full picture. The script exits non-zero only after all shards have run, and a final summary table lists per-shard pass / fail + executed-method counts. The per-shard sim-busy retry from earlier flake mitigations (`run_ui_shard_attempt 1 → reboot → attempt 2`) is preserved per shard, so one failure mode in one shard doesn't cascade.

**CI matrix readiness.** Today shards run sequentially in the single `Build & Test` job because we have one self-hosted runner. The per-shard log + xcresult layout (`ui-test-<shard>-attempt-N.log`, `TestResults-ui-<shard>.xcresult`) lets a future second runner trivially fan shards into a GitHub Actions `strategy.matrix` without touching the script — set `SHARD_FILTER` per matrix node.

## XCUITests

The UI suite is intentionally **smoke-level** today:

- cold launch reaches foreground
- app remains stable after launch
- root dashboard identity is visible (`root.dashboard` or a visible tab bar)
- launch performance metric collection

This suite stays shallow on purpose because tab bar element identity can vary across SwiftUI runtime revisions, which makes deep navigation assertions brittle. Deeper end-to-end behavior is covered by `VolumeArcDashboardIntegrationTests`, which exercise the create → log → complete chain against in-memory SwiftData. The smoke suite still runs in CI on every PR.

### Telemetry-as-UAT (VOL-149)

A `TelemetryEvent` recorded during a journey is a much stabler assertion target than a "did this accessibility identifier appear" check. Tab bars, button positions, and view hierarchies churn across SwiftUI revisions; the event a flow emits doesn't. VOL-149 wired a deterministic-mode-only probe that lets XCUITests assert on those events without polling shared state.

How it works:

1. In deterministic mode (`-UITestMode 1`), `VolumeArcAppFactories.makeTelemetrySink` returns an `InMemoryTelemetrySink` constructed with `postsNotificationOnRecord: true`. Every recorded event fires a `.volumeArcTelemetryDidRecord` `Notification.Name` with the `TelemetryEvent` in `userInfo`.
2. `VolumeArcTelemetryDebugProbe` (an `ObservableObject` owned by `VolumeArcApp`) observes that notification and maintains a JSON-encoded rolling 50-event buffer of `{c, n, s}` records (category / name / severity).
3. A hidden 1×1 accessibility overlay in the root `View` renders the JSON string with `accessibilityIdentifier("debug.telemetry.events")`. Production builds skip the overlay because the deterministic-mode gate is false.
4. `VolumeArcAppUITestSupport.assertTelemetryFired(in:category:name:within:test:)` polls the overlay's `label`, parses the JSON, and returns when the target `(category, name)` appears — or attaches a snapshot and `XCTFail`s with the most-recent label on timeout.

Pattern:

```swift
func testOnboardingFiresCompletedEvent() throws {
    let app = makeOnboardingApp()
    app.launch()
    // ... drive Continue × N and Finish ...
    VolumeArcAppUITestSupport.assertTelemetryFired(
        in: app,
        category: "onboarding",
        name: "completed",
        test: self
    )
}
```

This is preferred over "did the dashboard tab appear" assertions for any flow that has a canonical completion event. The probe buffer holds the last 50 events; bursty flows are fine, but if your journey emits more events than that you'll need to clear the buffer mid-run (currently not exposed — file a follow-up if you hit it).

#### Observer-bounce hazard (VOL-175)

The probe's `NotificationCenter` observer fires its callback on `.main` already (`addObserver(... queue: .main)`), but the closure is typed `@Sendable` under Swift 6 strict concurrency. To call MainActor-isolated `self.append` from inside, **use `MainActor.assumeIsolated`, not `Task { @MainActor in ... }`**. The Task variant adds an asynchronous scheduling hop; under simulator load (e.g., when the test bundle grows from adding a new test class), that hop can be deprioritized past the test's poll window, dropping events on the floor — even though the event itself fired and the probe is healthy. `assumeIsolated` runs synchronously on the current thread and trusts the `queue: .main` guarantee, so the append lands the moment the notification fires.

This was the root cause behind VOL-175's "probe flakes when chaos journey is in the bundle" symptom. The fix is one line and lives in `App/VolumeArcTelemetryDebugProbe.swift`. Future contributors adding probes or notification observers should reach for `MainActor.assumeIsolated` whenever the notification queue is already `.main`.

**Parser unit test:** `Tests/VolumeArcAppUITests/VolumeArcTelemetryProbeMatcherTests.swift` exercises the JSON parser in isolation so a regression in the matcher surfaces there instead of as a confusing XCUITest timeout downstream.

**Phase 2 (follow-up):** wire every journey in the suite to the canonical events listed in the VOL-149 acceptance criteria — onboarding, workout start/log/complete, coach session, paywall, watch sync, HealthKit permission.

## Chaos / fault injection (VOL-168)

[`docs/CHAOS.md`](CHAOS.md) is the source of truth. The short version: every chaos flag is a `-CHAOS_*` launch argument that the `ChaosController` (`App/Debug/`) reads, which causes `VolumeArcAppFactories` to wrap the matching subsystem in a fault-injecting decorator. Paired journeys in `VolumeArcChaosJourneyTests` exercise the fault and assert graceful degradation — including the diagnostic telemetry event via VOL-149's `assertTelemetryFired` helper. The wiring is `#if DEBUG`-gated everywhere so Release builds compile every chaos check down to `return false`. Phase 1 ships the HealthKit-auth-denied flag + journey; Phase 2 extends to WatchConnectivity / StoreKit / BGTaskScheduler / AIRelay.

## StoreKit edge cases (VOL-142)

Apple's IAP reviewers stress the unhappy paths — refund, family sharing, grace period, billing retry, ask-to-buy. Happy-path purchase tests (`testPremiumPurchaseFlowWithStoreKitTest` in `VolumeArcAppJourneyTests`) pass before submission and fail at review.

The Phase 1 coverage lives in `Tests/VolumeArcAppTests/StoreKitSubscriptionRevocationTests.swift` and uses `SKTestSession` against the shared `Tests/VolumeArcAppUITests/VolumeArcTests.storekit` configuration. Pattern:

```swift
let session = try SKTestSession(configurationFileNamed: "VolumeArcTests")
session.disableDialogs = true
session.clearTransactions()
let store = StoreKitSubscriptionStore(productIDs: ..., telemetry: telemetry)
// ... purchase ...
let transactions = session.allTransactions  // synchronous property; not async
try await session.refundTransaction(identifier: UInt(txn.identifier))
// ... assert revocation + telemetry ...
```

The store now routes every `Transaction.updates` event through `applyTransactionUpdate(_:)`, which inspects `revocationDate` and either inserts or removes the productID from `purchasedProductIDs`. Telemetry events (`subscription.entitlement.granted`, `subscription.entitlement.revoked`, `subscription.entitlement.purchase_pending`) fire on every state change so support correlations between "I got refunded" and the model's actual state are direct.

Phase 2+ (separate PRs): family sharing (`ownershipType == .familyShared`), grace period (`subscription.renewalState == .inGracePeriod`), billing retry, ask-to-buy approve/deny flow driven from `SKTestSession.askToBuyEnabled`, receipt-validation edge cases, `showManageSubscriptions(in:)` deep-link smoke test.

## Performance tests (VOL-99)

The perf suite (`Tests/VolumeArcAppPerfTests/VolumeArcPerfTests.swift`) enforces four budgets:

- `testColdLaunchTime()` — `XCTApplicationLaunchMetric`, 1.2s budget
- `testTodayScrollPerformance()` — `XCTOSSignpostMetric.scrollingAndDecelerationMetric` against 50 seeded rows, 58+ fps / <2 hitches/sec
- `testMemoryFootprintDuringWorkout()` — `XCTMemoryMetric`, <150 MB steady-state
- `testCoachFirstTokenLatency()` — `XCTClockMetric` from Ask Coach tap to first streaming bubble, <800 ms P50 / <2s P95

All budgets are declared in [`performance-budgets.json`](performance-budgets.json) and summarized in [`PERFORMANCE.md`](PERFORMANCE.md). The suite is **not** run on every PR because each measured test runs 3–5 iterations per metric. It runs on tag builds (`on: push: tags: ['v*']`) via the `perf-regression` job in `.github/workflows/ci.yml`. A regression above `failThreshold` breaks the build, and each run appends one row to [`performance-trend.json`](performance-trend.json) for historical visibility.

Run locally:

```bash
./scripts/test_performance.sh  # regenerate xcodeproj, boot simulator, run suite
./scripts/check_performance.sh # enforce budgets + append trend entry
```

The perf suite relies on the `-PerfTestMode 1` launch argument, which flips `VolumeArcRuntimeFlags.isPerformanceTestMode` on, seeds 50 deterministic history sessions via the launch bootstrapper, and removes the Today tab's `.prefix(3)` cap on recent sessions so the scroll test has real rows to scroll past.

## Snapshot regression (VOL-135)

Visual regression coverage for VAUI components and the critical screens (Onboarding, Paywall, RootDashboard tabs, Live Activity layouts) is **in flight**:

- **Phase 1 (this PR's introduction):** `pointfreeco/swift-snapshot-testing` v1.19 wired into the `VolumeArcAppTests` target. `Tests/VolumeArcAppTests/Snapshots/` is the canonical home; one infrastructure smoke test (`VolumeArcSnapshotInfrastructureTests`) proves the dependency links and the directory layout works. No baseline PNGs yet.

- **Phase 2+ (follow-up PRs):** active bundled baselines cover `VAButton` primary, the next-workout widget, core VAUI card/toast surfaces, the active-workout Live Activity lock-screen/banner and watch surfaces, `VACoachBubble` transcript states in light/dark plus accessibility Dynamic Type, and the Premium paywall loaded-empty/failure shell. Each additional component / screen should land in its own PR with its baseline PNG committed under `Tests/VolumeArcAppTests/Snapshots/__Snapshots__/`. The generated project copies that folder into the `VolumeArcAppTests` bundle so Xcode Cloud can compare snapshots even when the source checkout is not mounted during the test phase. See VOL-135's acceptance criteria for the full matrix (light + dark, `.medium` + `.accessibility5` Dynamic Type, reduce-transparency on/off).

### Recording a new snapshot

1. Add the test under `Tests/VolumeArcAppTests/Snapshots/<Surface>SnapshotTests.swift`.
2. Run **on the same simulator CI uses** (iPhone 17, iOS 26.5) so the PNG matches CI's pixel output. The helper script writes a temporary `.record-snapshots` marker because Xcode does not reliably pass arbitrary shell environment variables through to the XCTest process:

   ```bash
   SNAPSHOT_TEST_FILTER=<YourSnapshotTestClass> ./scripts/record_snapshots.sh
   ```

   The first run writes the PNG; subsequent runs compare against it.

3. Commit the generated PNG(s) under `Tests/VolumeArcAppTests/Snapshots/__Snapshots__/`. PRs that don't include baselines for new snapshot tests will silently auto-record on CI and never actually gate — reviewers should reject any new snapshot test missing its PNG.

### Diff workflow when CI fails

If a snapshot test fails on CI, the xcresult bundle (`TestResults-<run-id>` artifact) contains both the expected PNG and the recorded PNG plus a diff overlay. Download the artifact, open `TestResults.xcresult` in Xcode, find the failing test under the Tests tab. If the visual change is intentional (e.g. you updated `VA.Colors.accent`), re-record locally and commit the new baseline. If unintentional, fix the regression.

### Why not auto-record on CI

The library's default record mode is `.missing`: if there's no baseline, the test silently records one and passes. VolumeArc's `assertVolumeArcSnapshot` wrapper overrides the default to `.never` unless `SNAPSHOT_TESTING_RECORD` is set, so CI fails when a baseline is missing. The discipline above (record locally, commit baseline, CI compares the bundled copy) keeps the gate honest.

## Writing unit tests

Unit tests should:

- Test **real** production code, not surrogate copies
- Use mocks from `TestSupport/Mocks.swift` for protocol boundaries
- Use fixture builders from `TestSupport/Fixtures.swift` for test data
- Name test methods `test<Behavior>` (e.g., `testPersistenceFallbackChain`)
- Use `XCTAssert` helpers, not raw `assert`
- Be deterministic — no random values, no real network calls, no real filesystem unless the behavior under test is specifically a filesystem abstraction using temp dirs

## Coverage expectations

The 2026-05-01 audit established a project-level commitment to **90%+ coverage across all appropriate surfaces** (tracked in [VOL-140](https://linear.app/mabry-ventures/issue/VOL-140)). The current gates enforce staged floors on Core, UI, and Watch while the suite ratchets toward the target state.

| Layer | Current | Target (post VOL-140) | Enforced |
|-------|---------|------------------------|----------|
| `VolumeArcCore` business logic | 80%+ | **90%+** | Yes (CI gate) |
| `VolumeArcCore` data models | 60%+ | folded into 90% module gate | Yes (CI gate) |
| `VolumeArcUI` design system + screens | 18%+ staged floor | **85%+** | Yes (CI gate; ratcheted by VOL-135 snapshots) |
| `VolumeArcApp` host wiring | 40%+ | **75%+** | Pending (VOL-140) |
| `VolumeArcWatch` (new test target) | 25%+ staged floor | **85%+** | Yes (CI gate; Phase A from [VOL-138](https://linear.app/mabry-ventures/issue/VOL-138)) |
| `VolumeArcWidgets` + `WatchWidgets` | view-layer snapshots started | **75%+** | Pending line-coverage gate ([VOL-139](https://linear.app/mabry-ventures/issue/VOL-139)) |
| Subsystems with new fakes (HealthKit / CloudKit) | (integration only) | **90%+** on the subsystem | Pending ([VOL-136](https://linear.app/mabry-ventures/issue/VOL-136), [VOL-137](https://linear.app/mabry-ventures/issue/VOL-137)) |

### VolumeArcCore 80% line-coverage gate (VOL-52)

`scripts/test_apple_targets.sh` runs `xcodebuild test -enableCodeCoverage YES -resultBundlePath …`, producing a `TestResults.xcresult` bundle in `${DERIVED_DATA_PATH}` (defaults to `./.build/derived-data`). The CI workflow then runs `scripts/check_coverage.sh`, which:

1. Calls `xcrun xccov view --report --json $TEST_RESULT_BUNDLE` to extract per-target coverage data.
2. Looks for the `libVolumeArcCore.a` target (VolumeArcCore is built as a static library, so xccov reports it under that name) and prints its line coverage rounded to two decimals.
3. Fails the build if the line coverage drops below `${COVERAGE_THRESHOLD:-80}`.

The threshold is hard-coded to **80%** in CI. Override it locally for diagnostic runs:

```bash
COVERAGE_THRESHOLD=85 ./scripts/check_coverage.sh   # try a tighter floor
COVERAGE_TARGET=VolumeArcUI ./scripts/check_coverage.sh   # measure a different target
```

### Coverage artifacts

CI publishes three coverage surfaces per run so reviewers never need to scrape the raw log (VOL-97). VOL-140 Phase 1 (2026-05-11) extended each surface to include every non-test target xccov reports, not just the gated `VolumeArcCore` — the additional rows are measure-only until per-target thresholds get calibrated in Phase 2.

**1. GitHub step summary.** `scripts/check_coverage.sh` writes a Markdown block to `$GITHUB_STEP_SUMMARY` on every run: the headline `VolumeArcCore: XX.XX%` number, the pass/fail gate, a top-10 uncovered-files table for the gated target, and an "All measured targets" table with per-target coverage / executable / covered counts. Test targets (anything ending in `Tests`, `TestSupport`, or `UITests-Runner`) are filtered out. The block lives on the workflow run page under the "Summary" tab.

**2. xcresult artifact.** Every run (success or failure) uploads `TestResults-<run-id>` containing the full `.xcresult` bundle with 14-day retention. Download from the workflow run page, then `open TestResults.xcresult` in Xcode for the interactive per-line coverage browser. Useful when the top-10 table doesn't tell the whole story.

**3. Sticky PR comment.** PR runs post (or update) a single coverage comment on the pull request. It renders one row per measured target — gated modules show `passed (>= N%)` / `FAILED (< N%)`, ungated modules show `(measure only)`. Gets rewritten on every re-run, so the comment always reflects the latest CI. Implemented via `actions/github-script` with a hidden `<!-- volumearc-coverage-comment -->` marker.

**4. Historical trend file.** After each merge to `main`, CI appends a record to `coverage-trend.json` on the **`metrics` branch** (not main). Each record now includes a `targets` map keyed by module name with `coverage`/`executable`/`covered` per target alongside the legacy top-level `coverage`/`passed` for back-compat. Main is protected by the `Require AI Code Reviews` ruleset, so bot pushes to main are rejected — VOL-166 moved the trend storage to an unprotected, data-only branch. The coverage badge at the top of [`docs/PLATFORM.md`](PLATFORM.md) reads the tail record from `https://raw.githubusercontent.com/Mabry-Ventures/mv-volumearc/metrics/coverage-trend.json` via a dynamic-json shields.io endpoint. The placeholder [`docs/coverage-trend.json`](coverage-trend.json) on main is documentation only — do not edit it. The file on `metrics` is append-only; tampering with old records is a correctness bug.

The trend file on `metrics` is bootstrapped automatically on the first main push that produces coverage data: the workflow checks out `origin/metrics` if it exists, otherwise creates an orphan `metrics` branch with a tiny README and the trend JSON. Subsequent main pushes append-and-push.

### Inspecting coverage locally

```bash
./scripts/test_apple_targets.sh
./scripts/check_coverage.sh

# Open the xcresult bundle in Xcode for an interactive coverage browser:
open .build/derived-data/TestResults.xcresult

# Or list per-target totals from the command line:
xcrun xccov view --report --only-targets .build/derived-data/TestResults.xcresult

# And per-file totals for VolumeArcCore:
xcrun xccov view --report --files-for-target libVolumeArcCore.a .build/derived-data/TestResults.xcresult
```

The Xcode Test Navigator's "Coverage" tab also surfaces per-line covered/uncovered annotations once the xcresult bundle is open.

### Adding new code without dropping the gate

When adding new VolumeArcCore code:
- Add tests in the same PR. The CI gate fires before review, so an untested module landed alone will fail the build.
- Prefer pure-logic unit tests over end-to-end integration tests for new code paths — they're cheaper to write and don't add to the simulator runtime.
- Use the `Mocks.swift` doubles (`FailingAICoachProvider`, `CapturingTelemetrySink`, `RecordingHealthStore`, etc.) to exercise fallback / error paths without standing up real infrastructure.

## Flaky test policy

Flaky tests are worse than no tests — they erode trust in the suite. If a test flakes:

1. Immediately mark it as `XCTSkip` with a TODO and ticket reference
2. Open a P1 ticket to fix or delete it
3. Do not merge code that leaves flaky tests behind

## CI runner flake taxonomy (VOL-227 cluster)

When CI fails on the `mv-volumearc-runner` self-hosted host, the failure is almost always one of a small set of recurring **infrastructure** flakes — distinct from test-code flakes (the policy above). Each entry below maps the symptom to the responsible mitigation so on-call can attribute failures fast.

| Symptom string in CI log | Failure shape | Mitigation | Source |
|---|---|---|---|
| `Waiting on System App` repeated for >5 min during `Pre-warming '<device>'` | Host-level orphan `launchd_sim` keeps the System App in a half-booted state; `xcrun simctl bootstatus -b` hangs indefinitely | 5-min wallclock around `bootstatus -b` (`SIM_BOOTSTATUS_TIMEOUT` env override). Fails fast with an actionable error pointing at host cleanup instead of burning 18+ min before the outer wallclock kills xcodebuild | VOL-227 round 3 / PR #244 in `scripts/test_apple_targets.sh::warm_simulator_for_tests` |
| `xctest encountered an error (Failed to establish communication with the test runner. (Channel disconnected))` | XCTest runner died after launch; xcresult bundle may be incomplete | Shell-level per-attempt retry. First failure → shutdown sim, sleep 10s, re-warm, re-run unit tests once. xcodebuild-level `-test-iterations` was tried in VOL-231 round 1 (PR #233) but corrupted the bundle; reverted in #234 | VOL-227 round 2 / PR #241 in `scripts/test_apple_targets.sh::is_channel_disconnect_failure` |
| `Mach error -308 - (ipc/mig) server died` after the accessibility-stress XCUITests | `AccessibilityUIServer` daemon wedged by `accessibility5` + `NSDoubleLocalizedStrings YES` simultaneously; next test bundle install dies | Per-shard isolation — accessibility-stress tests live in their own UI-shard partition (`accessibility-screenshots`) so the wedge can't poison other shards; pre-emptive `simctl spawn killall AccessibilityUIServer` before every shard | VOL-231 / PR #236 `verify_shard_coverage` + per-shard warm-up |
| `Application failed preflight checks` / `SBMainWorkspace.*Busy` | XCTRunner install raced against the simulator's SpringBoard | Per-shard sim-busy preflight retry — on first hit, shutdown sim + sleep 10s + re-warm + re-run that one shard | Existing in `scripts/test_apple_targets.sh::run_ui_shard` |
| `Test crashed with signal kill before establishing connection` / `Early unexpected exit, operation never finished bootstrapping` | OOM or process-watchdog killed the test runner before it bootstrapped; common signature when host is under memory pressure | No PR-side mitigation today — falls to runner-host investigation (see [runner-host operational notes](#runner-host-operational-notes-mv-volumearc-runner)) |  |
| `Unable to getenv("TESTMANAGERD_SIM_SOCK") while not booting or booted. Current state: Shutdown` | Simulator transitioned to Shutdown mid-test; usually paired with high concurrent-job pressure on the host | No PR-side mitigation today — host-level | |
| `The result bundle could not be opened as it is incomplete. Xcode might have failed to finish writing the result bundle.` | xcresult bundle finalization failed; downstream Coverage gate can't read it | Avoid xcodebuild-level retries (`-test-iterations` corrupts the bundle); use shell-level retry per #241 instead | VOL-231 round 1 lesson |
| `No space left on device` during build | Module cache / DerivedData filled the runner disk | Manual cleanup. `~/Library/Developer/Xcode/DerivedData/`, `~/Library/Developer/CoreSimulator/Caches/`, `~/Library/Logs/CoreSimulator/`, plus the workspace `.build/derived-data/` are the four high-yield targets | Host-level — see runner-host runbook |

### Runner-host operational notes (`mv-volumearc-runner`)

CI runs on the **Mabry Ventures macOS runner fleet on MVGHRUN01** — a single Mac Studio M4 Max 128GB macOS Tahoe 26.5 host that registers multiple per-tenant runner instances. The `mv-shared-01..04` slot suffixes you'll see in CI run logs are the flex pool on the *same physical host*, not separate machines. See [`docs/CONTRIBUTING.md` → Runner fleet topology](CONTRIBUTING.md#runner-fleet-topology-mvghrun01) for the canonical reference (account UIDs, ASC-key access matrix, env vars, trust boundary, host paths).

A root **watchdog** runs every 2 minutes on the host and kills orphan processes. Active job processes are protected via sentinels (`/var/run/mv-active-jobs/<runner>.sentinel`, pgid-keyed). Long `simctl` operations are protected up to **1h cumulative**; `launchd_sim` orphans past **4h** are killed unconditionally. This is the layer that *prevents* the most common form of orphan-launchd_sim wedge — when you see one anyway, the watchdog's protection window expired or the orphan slipped the sentinel.

Failure modes that need host-level intervention (no PR can fix them):

- **Disk-full** — module-cache writes start failing, cascading into simulator boot wedges + xctest bootstrap failures. Symptom: `'No space left on device'` in the build log. The four high-yield cleanup directories live in [`CONTRIBUTING.md` → Runner maintenance](CONTRIBUTING.md#runner-maintenance). **Prevention** tracked in [VOL-243](https://linear.app/mabry-ventures/issue/VOL-243) — daily watchdog at a 50 GB free-disk floor, well above the 10 GB Pre-flight hard floor, so the operator gets warning before a build hits the cliff. The 2026-05-19 incident exhibited exactly this cascade — see [`docs/incident-log.md`](incident-log.md#2026-05-20-0251-utc--self-hosted-runner-cascading-flake-cluster--disk-full-sev2).
- **iOS simulator runtime missing after Xcode upgrade** — Xcode minor-bump auto-updates don't always pull the matching simulator runtime. Symptom: `xcodebuild: error: Unable to find a destination matching ... iOS X.Y is not installed`. The host has an operator-triggered, idle-gated `sim-recovery.sh` that handles the partial-upgrade case; for simple cases, `xcodebuild -downloadPlatform iOS`. Open a Linear ticket if CI consistently fails with the destination-specifier error — the owner SSHs in.
- **Memory pressure** — test runners get `SIGKILL`-ed by the OS before they can bootstrap. Symptom: `Test crashed with signal kill before establishing connection`. The host has 128 GB and multi-job concurrency, so this should be rare; when it recurs, audit recent dependency additions (Sentry, swift-snapshot-testing) for leaks. Mitigation lever for emergencies: reduce concurrent-slot count via workflow `concurrency.group`.

If a single CI run hits two or more of these failure modes back-to-back, treat the host as wedged and pause the merge queue. The 2026-05-19 overnight burndown exhibited exactly this: disk-full triggered cascading sim-wedge + bundle-corruption across 8 PRs, all of which only cleared after the host was upgraded out-of-band.

## Test naming

```swift
func testPersistenceFallsBackToInMemoryWhenLocalFails() { ... }
func testRelaySessionExpiresTokensWithin60SecondsOfDeadline() { ... }
func testProgressionEngineAddsWeightWhenUpperRepBoundHit() { ... }
```

Be specific. A test name should describe both the condition and the expected behavior.

## User-journey catalog

[`USER_JOURNEYS.md`](USER_JOURNEYS.md) is the canonical inventory of every distinct user-facing flow in VolumeArc. Each row maps Journey ID → pre-conditions → steps → success criteria → telemetry events → paired XCUITest method. When you add or change a journey:

1. Update the journey row in `USER_JOURNEYS.md`.
2. Update or add the paired XCUITest.
3. **In the same PR, bump `JOURNEY_COVERAGE_THRESHOLD`** in `.github/workflows/ci.yml`'s "Journey coverage gate" step to match the new percentage. Same ratchet contract as the per-target coverage gate (VOL-205) — the threshold tracks current coverage at-or-above, never drops.

The gate (`scripts/check_journey_coverage.sh`, VOL-200 Phase 1) runs in CI after the per-target coverage gates. It parses the table, counts rows with paired XCUITests vs. `[ ]` (uncovered), and fails the build below the threshold. Default threshold is **18%** (the audited 2026-05-18 baseline: 11/62 covered). Coverage target: **100%** of journeys covered by an XCUITest paired with telemetry assertions ([VOL-149](https://linear.app/mabry-ventures/issue/VOL-149) telemetry-as-UAT helper); burn-down tracked under [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141) and [VOL-200](https://linear.app/mabry-ventures/issue/VOL-200).

## Snapshot / visual regression

**Phase 1 infrastructure landed (VOL-201).** pointfreeco SnapshotTesting is linked into `VolumeArcAppTests`, and `scripts/record_snapshots.sh` is the canonical helper for regenerating baselines locally. Phase 2+ (the actual baselines per surface family) is filed under [VOL-201](https://linear.app/mabry-ventures/issue/VOL-201) and rolls out one PR per family. Audit target:

- Every VAUI design-system component (`VAButton`, `VACard`, `VACoachBubble`, `VAToast`, metric displays, `VAReadinessHero`)
- Critical screens: `OnboardingView`, `PaywallView`, `RootDashboardView` (each tab), `ActiveWorkoutLiveActivity` lock-screen + Dynamic Island
- Widgets (3 sizes × 2 themes)
- Variants per surface: light + dark × default + `.accessibility5` Dynamic Type × reduce-transparency on/off

### Per-trait `assertSnapshot` pattern

For every surface, snapshot it under the full trait matrix in one test method so the captured PNG filenames carry the trait combination:

```swift
func testPaywallSnapshots() {
    let view = PaywallView(...)
    let traits: [(String, UITraitCollection)] = [
        ("light", UITraitCollection(traitsFrom: [
            .init(userInterfaceStyle: .light),
            .init(preferredContentSizeCategory: .medium),
        ])),
        ("light_xxl", UITraitCollection(traitsFrom: [
            .init(userInterfaceStyle: .light),
            .init(preferredContentSizeCategory: .accessibilityExtraExtraLarge),
        ])),
        ("dark", UITraitCollection(traitsFrom: [
            .init(userInterfaceStyle: .dark),
            .init(preferredContentSizeCategory: .medium),
        ])),
        ("dark_xxl", UITraitCollection(traitsFrom: [
            .init(userInterfaceStyle: .dark),
            .init(preferredContentSizeCategory: .accessibilityExtraExtraLarge),
        ])),
    ]
    for (suffix, traits) in traits {
        assertVolumeArcSnapshot(
            of: view,
            as: .image(on: .iPhone17, traits: traits),
            named: suffix,
            in: self
        )
    }
}
```

Each iteration writes `__Snapshots__/<TestClass>/testPaywallSnapshots.<suffix>.png`. CI compares against the committed PNG and fails on any pixel-level drift.

### Simulator-OS pinning (important)

pointfreeco SnapshotTesting captures pixel-identical baselines that **drift between simulator OS minor versions** (a baseline captured on iOS 26.5 will mismatch CI's 26.4 sim). The mitigation:

- `scripts/record_snapshots.sh` defaults to `SNAPSHOT_SIMULATOR_OS=26.5` and `SNAPSHOT_SIMULATOR_NAME="iPhone 17"`.
- `.github/workflows/ci.yml`'s test job uses the same destination (already pinned via the existing `xcodebuild -destination` argument).
- If CI's runner image bumps to a newer minor, regenerate baselines via `./scripts/record_snapshots.sh` on the new image in a dedicated maintenance PR, and pin both env vars to the new value.

### Local workflow

1. Author the snapshot test in `Tests/VolumeArcAppTests/Snapshots/<TestClass>.swift`.
2. Run `./scripts/record_snapshots.sh` (or `SNAPSHOT_TEST_FILTER=<TestClass> ./scripts/record_snapshots.sh` for a single family). The script sets `SNAPSHOT_TESTING_RECORD=all` and writes a temporary `.record-snapshots` marker, which makes `assertVolumeArcSnapshot` write into the source-tree `__Snapshots__` directory.
3. Review the generated PNGs under `Tests/VolumeArcAppTests/Snapshots/__Snapshots__/<TestClass>/`.
4. Commit the PNGs in the same PR as the surface change.
5. CI runs with default (non-recording) mode and asserts.

Recording new baselines without committing them fails CI because compare mode uses `.never` and reads the bundled reference directory. Always commit the PNG in the same PR.

Current bundled baseline families: `VAButtonSnapshotTests`, `VADesignSystemSnapshotTests`, `NextWorkoutWidgetSnapshotTests`, `ActiveWorkoutLiveActivitySnapshotTests`, `VACoachBubbleSnapshotTests`, and `PaywallSnapshotTests`.

`PaywallSnapshotTests` is enforced locally and on the self-hosted runner, but skips inside Xcode Cloud's `TestProducts.xctestproducts` runtime because XC renders that SwiftUI paywall surface differently from the same bundled references.

CI failures from snapshot diffs block merge on the same gate as unit tests.
