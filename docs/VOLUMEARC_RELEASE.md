# VolumeArc Release

Last updated: 2026-06-06

This is the operating plan for the `VolumeArc Release` initiative. It supersedes the older release-readiness project framing for active launch work. Historical audit context remains in [`AUDIT.md`](AUDIT.md); implementation status remains in [`PLATFORM.md`](PLATFORM.md).

## Release Gate

VolumeArc does not launch as a paid public product until every condition below is true:

| Gate | Required state |
|---|---|
| World-class scorecard | Every category is 9.5 or higher. |
| Findings | No unresolved P0-P4 finding remains unless explicitly accepted by Jared. |
| Apple build | `build_all_targets.sh`, `test_apple_targets.sh`, coverage, release validation, archive/export, and TestFlight dry run are green. |
| Design | Claude Design parity is signed off across iOS, watchOS, widgets, marketing language, light mode, dark mode, and the warm brand personality. |
| Performance | Real trend data exists and all critical budgets pass on simulator and physical-device UAT. |
| AI | Hermetic and live evals are green, model routing is pinned, and AI remains subtle in product copy. |
| Security | Semgrep, TruffleHog, dependency audits, App Attest, privacy manifests, Sentry scrubbers, and CI permissions are launch-grade. |
| App Store | Metadata, screenshots, pricing, legal counsel review, privacy answers, support paths, and TestFlight review are complete. |

## Linear Structure

Initiative: [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762)

| Project | Purpose |
|---|---|
| Release Baseline And Repo Cleanup | Branch baseline, repo cleanup, stale artifacts, generated-project discipline, release hygiene. |
| Docs, Copy, And Product Voice | Canonical docs, no-emoji policy, product voice, pricing/legal/App Store copy. |
| Claude Design Parity | Claude export parity across app, watch, widgets, tokens, copy, modes, and screenshots. |
| Performance And Resiliency | Fast paths, offline/resume/reconnect, performance budgets, trend data, physical UAT. |
| AI Coach Excellence | Model routing, evals, safety, privacy, fallback behavior, latency, cost, subtle AI UX. |
| Security And Privacy Hardening | App Attest, relay, Sentry, dependency scans, Semgrep, TruffleHog, CI permissions. |
| Feature Superiority | Competitor re-baseline, co-design planning, readiness prescription, feature moat. |
| CI, Coverage, UAT, And App Store | Build/test/coverage, journey proof, screenshots, metadata, TestFlight, submission. |
| Xcode Cloud And Release Automation | ASC key handling, Xcode Cloud, signing, build numbers, archive, dSYM, TestFlight automation. |

## Active Blockers

| Issue | Severity | Status | Project | Launch gate | Summary |
|---|---|---|---|---|---|
| VOL-267 | P0 | Fixed on branch; needs CI proof | Xcode Cloud And Release Automation | Yes | Fix clean Apple build Sentry artifact hydration. |
| VOL-268 | P0 | Fixed on branch; needs CI proof | Security And Privacy Hardening | Yes | Enforce Release `COPY_PHASE_STRIP = YES` from the Xcode generator. |
| VOL-269 | P0 | App/relay safety hardened locally; eval trend still open | AI Coach Excellence | Yes | Publish post-fix green coach response eval trends. |
| VOL-270 | P1 | Partially fixed on branch | Claude Design Parity | Yes | iOS light/dark/warm-brand, light `.accessibility5`, and light/dark/warm-brand reduce-transparency-off dashboard-surface snapshots are implemented; warm token parity is implemented; Watch/runtime parity, marketing caveat, native tab chrome signoff, widget expansion, and physical visual review remain. |
| VOL-271 | P1 | Partially fixed on branch | CI, Coverage, UAT, And App Store | Yes | Automated v1 journey coverage is 100%; complete paired iPhone/Watch UAT. |
| VOL-272 | P1 | Fixed on branch; needs CI ruleset proof | Security And Privacy Hardening | Yes | Promote security and supply-chain scans to launch-grade gates. |
| VOL-273 | P2 | Open | Docs, Copy, And Product Voice | Yes | Finalize pricing, legal, and marketing copy status. |
| VOL-274 | P2 | Fixed on branch; needs live eval/cost proof | AI Coach Excellence | Yes | Pin production AI model routing and deprecation policy. |
| VOL-275 | P2 | Partially fixed on branch | Feature Superiority | Conditional | Schedule persistence, edited prescription persistence, and row-action proof are implemented and locally validated; template decision, dedicated-screen parity, and Watch start/sync remain. |
| VOL-276 | P1 | Fixed on branch; needs CI proof | Release Baseline And Repo Cleanup | Yes | Enforce release hygiene, no-emoji policy, and stale-doc cleanup. |

## Branch Evidence Snapshot

As of the 2026-06-06 release-branch hardening pass:

| Area | Evidence |
|---|---|
| Apple build/test | `build_all_targets.sh`, `test_apple_targets.sh`, `check_coverage.sh`, release validation, and Xcode project determinism pass locally under Xcode 26.5. The 2026-06-06 full Apple script run passed app unit/integration tests, smoke UI, journeys-core, journeys-aux, and accessibility-screenshot shards; the only skip is the existing VOL-230 simulator StoreKit limitation. |
| Performance | `test_performance.sh` and `check_performance.sh` pass; `docs/performance-trend.json` contains a green baseline. |
| Journey coverage | `check_journey_coverage.sh` reports 72/72 (100%). The branch adds deterministic offline coach fallback coverage, no-iCloud launch fallback proof, 401 safe-fallback proof, 401 session-refresh retry proof, Foundation Models unavailable fallback proof, Profile subscription-management proof, HealthKit-unavailable Today fallback proof, onboarding HealthKit grant/deny fixture proof, Workouts rest-timer expiry proof, Workouts history delete proof, onboarding force-quit recovery proof, active-workout force-quit recovery proof, coach-stream force-quit recovery proof, Watch offline replay telemetry proof, WatchConnectivity queue/reconnect notice proof, background refresh/processing proof, background-task wake/relaunch idempotency proof, push-notification tap routing proof, widget small/medium render and embed proof, Live Activity state/telemetry/Dynamic Island render proof, co-design scheduling proof, Coach voice permission/session proof, and additional Watch wire-contract proof. Paired iPhone + Apple Watch UAT remains open. |
| Relay/session recovery telemetry | `relay.session_refreshed` proves a 401 App Attest relay-session refresh and retry; `coach.stream.aborted` proves force-quit stream recovery drops partial coach turns instead of persisting incomplete advice. |
| Co-design planning | `VolumeArcDashboardIntegrationTests.testScheduleCoDesignedWorkoutForTomorrowPersistsPlanAndEmitsTelemetry`, `VolumeArcTodayJourneyTests.testTodayPlanTomorrowSchedulesCoDesignedDraftIntoWorkouts`, and `VolumeArcTodayJourneyTests.testTodayPlanTomorrowEditsExerciseRowsBeforeScheduling` pass locally. `Schedule` now persists tomorrow's edited exercise prescription, refreshes the dashboard weekly plan, and shows the scheduled workout with an exercise preview in Workouts. |
| Design parity | `VADesignTokenParityTests` verifies Claude warm-personality brand colors against native `VA.Colors` in light/dark, and `DashboardSurfaceSnapshotTests` records and compares 42 baselines for Today, Workouts idle, Workouts active, Coach planning, Signals, and Profile in light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand reduce-transparency-off glass variants. Remaining VOL-270 work covers Watch/runtime parity, marketing export caveat, native tab chrome accepted drift, widgets, and physical-device visual signoff. |
| Copy/product voice | Coach safety copy, the persistent Coach disclaimer, privacy-mode copy, paywall feature labels, marketing metadata/FAQ/pricing copy, and customer-facing App Store description/release notes now avoid daily model/provider branding. `check_release_hygiene.sh` blocks the exact AI/provider-branding phrases that previously drifted into SwiftUI, selected marketing, and selected App Store product surfaces while leaving technical, legal, privacy, quality, and App Review disclosures intact. |
| AI coach safety | App-side `CoachSafetyFilter` and relay-side deterministic safety now short-circuit current medical red flags from the athlete question, message history, and the current training-context block before generated advice can stream; both paths also avoid negated and stale historical false positives. Verified locally with `CoachSafetyFilterTests`, local heuristic false-positive tests, and relay tests/typecheck. Live staging response evals remain required before launch. |
| Security/supply chain | Semgrep, TruffleHog full-history scan, marketing `npm audit --audit-level=moderate`, marketing SBOM generation, relay tests/typecheck, and relay `npm audit --audit-level=high` pass locally. |
| Marketing | `npm run lint`, `check:legal`, `build`, `test:e2e`, `test:a11y`, and `test:lighthouse` pass; local browser smoke covers desktop, pricing anchor, and mobile navigation. |
| Xcode Cloud / ASC | Local ASC key permissions tightened to owner-only without reading key contents. Fastlane now builds the App Store Connect API key object in memory from Key ID, Issuer ID, and the raw `.p8` path instead of passing the `.p8` as `api_key_path`. No fresh TestFlight artifact is counted as complete until Xcode Cloud or a signed local archive/upload actually produces a visible build. |
| Release UAT evidence | `docs/RELEASE_UAT_EVIDENCE.md` is now the canonical manifest for physical-device and TestFlight-only proof. `scripts/check_release_uat_evidence.sh` requires build metadata, 35 physical journey rows, and 5 launch signoffs; `VOLUMEARC_RELEASE_READY=1 ./scripts/validate_release_config.sh` blocks until the manifest is complete for the exact TestFlight build under review. |
| Remaining launch gates | VOL-269 live coach eval trend, fresh TestFlight/Xcode Cloud proof, remaining VOL-270 watch/marketing/widget visual parity and tab-chrome drift signoff, VOL-271 paired iPhone/Watch UAT, VOL-273 App Store/legal/pricing, VOL-274 live eval/cost/deprecation proof, and remaining VOL-275 co-design template/dedicated-screen/Watch proof remain open. |

## Competitor Baseline

The release strategy keeps VolumeArc focused on Apple-native strength coaching instead of trying to out-breadth every competitor.

| Competitor | Current official signal | VolumeArc response |
|---|---|---|
| Fitbod | App Store copy emphasizes personalized AI workouts, 1000+ exercises, video demos, Apple Health, Strava, Fitbit, Apple Watch, Editors' Choice, and a large ratings base. | Win on Apple-native depth, Watch-first speed, readiness prescription, privacy, and craft; do not claim the broadest exercise library. |
| WHOOP | 2026 updates include WHOOP AI plus Strength Trainer, AI workout generation, passive muscular load, and AI-linked exercises after lifting. | Make readiness and strength prescription the first-run aha, with Apple Health and Watch data changing the actual workout. |
| Future | App Store copy emphasizes adaptive data-driven training, real-time feedback, instant adjustments, audio guidance, Apple Watch integration, and HealthKit. | Do not compete on human-coach framing; win on faster, lower-friction, automated Apple-native coaching. |

References: [Fitbod App Store](https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543), [WHOOP 2026 updates](https://www.whoop.com/us/en/thelocker/2026-whats-new/), [Future App Store](https://apps.apple.com/us/app/future-personalized-workouts/id6744624390).
