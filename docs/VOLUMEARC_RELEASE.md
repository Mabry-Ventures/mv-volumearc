# VolumeArc Release

Last updated: 2026-06-11

This is the operating plan for the `VolumeArc Release` initiative. It supersedes the older release-readiness project framing for active launch work. Historical audit context remains in [`AUDIT.md`](AUDIT.md); implementation status remains in [`PLATFORM.md`](PLATFORM.md).

## 2026-06-11 Replan

WWDC26 (June 8) and Google's Fitbit relaunch changed the competitive floor for generic coaching: Apple's Workout Buddy ships free and phone-less in watchOS 27 (with Apple's deeper Health coach delayed to 27.1-27.4), iOS 27 opens a public `LanguageModel` protocol with PCC Small Business free inference (tracked post-v1 as VOL-282), and Google's Gemini Health Coach is $9.99/mo on iOS or free with Google AI Pro/Ultra. Jared's directive: be 99/100 ship-ready within the week as the **AI strength programming coach** — the prescriptive strength specialist (progressive overload, readiness-driven set/rep/load prescriptions, autoregulation, recovery-timed deloads). The positioning is a binding product-voice rule in [`PRODUCT_POSITIONING.md`](PRODUCT_POSITIONING.md) and is enforced by `check_release_hygiene.sh`. Pricing decided: $9.99/month, $59.99/year, applied in-repo and provisioned in App Store Connect (group "VolumeArc Premium", all territories, equalized).

### Descope register (v1 surface set)

| Decision | Scope | Rationale |
|---|---|---|
| Canceled: VOL-238 | Watch-face complication pack with one-tap install presets | Cut from v1; **no watch-face install claims may appear in metadata or screenshots** (VOL-125 carries the verification) |
| Canceled: VOL-258 / VOL-259 | VolumeArcUI 18%→50% and Watch 25%→50% coverage ratchets | Post-v1 ratchet path; the staged widget coverage floor (VOL-263 Phase A) stays active |
| Retained full scope: VOL-270 | Complete Claude Design parity including Watch/runtime, widgets, marketing caveat, physical visual review | Jared rejected the descope — "we need the visual consistency from the Claude Design work" |
| Retained full scope: VOL-275 | Full co-design capability including template build, dedicated screen, Watch start/sync | Jared rejected the descope — "need the full capability to compete" |
| Added as launch gates: VOL-278 epic (VOL-283..287) | Provider-agnostic coach safety case: pre-generation gate, prescription clamps, per-tier eval taxonomy, kill switches, onboarding disclaimer + age 16 | Safety is a hard launch condition; the binding contract is [`COACH_SAFETY.md`](COACH_SAFETY.md) |
| Added: VOL-279 / VOL-280 / VOL-281 | Product copy + marketing repositioning + this re-baseline | The positioning shift must reach every surface and the gates that measure it |

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

Statuses synced to the live Linear board on 2026-06-11. "On branch" means landed on `fix/volumearc-ga-readiness` (PR #363) pending CI + merge.

| Issue | Severity | Status | Launch gate | Summary |
|---|---|---|---|---|
| VOL-277 | P0 | Xcode Cloud recovered (PR runs green 2026-06-11); TestFlight cut pending | Yes | Cut the next TestFlight build for UAT. |
| VOL-269 | P0 | Harness fixed on branch (negation-aware scan, per-tier axis); first staging smoke 9/10 → green expected; full 55-fixture trend publish open | Yes | Publish post-fix green coach response eval trends. |
| VOL-278 (+283..287) | P0/P1 | All five children on branch with tests, telemetry, runbook, and signed constants (age 16, clamp bounds) | Yes | Coach safety overhaul: pre-gate proofs, prescription clamps, per-tier evals, kill switches, onboarding disclaimer. |
| VOL-267 / VOL-268 / VOL-272 / VOL-276 | P0/P1 | In Review — fixed on branch, CI proof rides PR #363 | Yes | Sentry artifact hydration, COPY_PHASE_STRIP, security gates, release hygiene. |
| VOL-270 | P1 | Partial on branch; full scope retained | Yes | iOS surface snapshots done; Watch/runtime parity, widgets, marketing caveat, physical visual review remain. |
| VOL-271 | P1 | Automated journey coverage 100%; paired iPhone/Watch UAT open | Yes | Physical-device UAT manifest (`RELEASE_UAT_EVIDENCE.md`) completion. |
| VOL-273 | P2 | Pricing decided and applied; legal counsel pass open | Yes | Finalize legal/marketing copy status. |
| VOL-274 | P2 | In Review — routing pinned on branch; live eval/cost proof rides VOL-269 | Yes | Production AI model routing + deprecation policy. |
| VOL-275 | P2 | Partial on branch; full capability retained | Conditional | Template build, dedicated-screen parity, Watch start/sync remain. |
| VOL-279 | P1 | Landed on branch 2026-06-11 (in-app sweep + metadata handoff) | Yes | Reposition all product copy as AI strength programming coach. |
| VOL-280 | P1 | Open | Yes | Marketing site repositioning + safety/disclaimer surfaces. |
| VOL-281 | P1 | This re-baseline (landed with this doc) | Yes | Codify descoped v1 surface set + ship-ready target. |
| VOL-125 | P1 | In Progress — metadata files repositioned on branch; screenshots + rating answers + submission package open | Yes | App Store metadata + screenshot package. |
| VOL-230 / VOL-262 / VOL-246 | P2/P3 | In progress / review / backlog | Supporting | XCUITest investigations, perf budget calibration, /download redirect. |

## Branch Evidence Snapshot

As of the 2026-06-11 pass (rows below updated in place where superseded; the 2026-06-06 baseline otherwise stands):

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
| Coach eval release gate | `scripts/check_coach_eval_trend.sh` now requires the docs and marketing trend files to be mirrored, current within 7 days, and green across all 55 fixtures per enabled cloud tier (`flash-lite` + `pro`; rows keyed `<id>@<tier>`, per-provider rollup required) with no axis or fixture failures, and `mustNotMention` is negation-aware so protective phrasing cannot fail a fixture. `VOLUMEARC_RELEASE_READY=1 ./scripts/validate_release_config.sh` runs this gate before UAT evidence so release signoff cannot skip the stale/failing public quality record. |
| Security/supply chain | Semgrep, TruffleHog full-history scan, marketing `npm audit --audit-level=moderate`, marketing SBOM generation, relay tests/typecheck, and relay `npm audit --audit-level=high` pass locally. Dependabot alert #36 for Ruby `jwt` CVE-2026-45363 is addressed on this branch by locking `jwt` to patched `2.10.3`; GitHub will close the alert only after the fix reaches the default branch. |
| Marketing | `npm run lint`, `check:legal`, `build`, `test:e2e`, `test:a11y`, and `test:lighthouse` pass; local browser smoke covers desktop, pricing anchor, and mobile navigation. |
| Xcode Cloud / ASC | Local ASC key permissions tightened to owner-only without reading key contents. Fastlane now builds the App Store Connect API key object in memory from Key ID, Issuer ID, and the raw `.p8` path instead of passing the `.p8` as `api_key_path`. Live ASC workflow inventory checked on 2026-06-06: `VolumeArc PR` builds/tests PRs, `VolumeArc Main` tests `main`, and `Internal Testing` is a manual `main` archive to internal TestFlight. No tag-triggered TestFlight workflow exists today. Xcode Cloud worker startup recovered on 2026-06-11: PR builds run real actions and pass on current heads (VOL-277 acceptance criterion 1 met). No fresh TestFlight artifact is counted as complete until the Internal Testing archive produces a visible processed build. |
| Release UAT evidence | `docs/RELEASE_UAT_EVIDENCE.md` is now the canonical manifest for physical-device and TestFlight-only proof. `scripts/check_release_uat_evidence.sh` requires build metadata, 35 physical journey rows, and 5 launch signoffs; `VOLUMEARC_RELEASE_READY=1 ./scripts/validate_release_config.sh` blocks until the manifest is complete for the exact TestFlight build under review. |
| Coach safety epic (VOL-278) | All five children are on the branch: `SafetyFilteredCoachProvider` composition proofs across every factory chain, `CoachPrescriptionClamp` with signed constants and the `scheduleWorkoutPlan` backstop, 55 fixtures x 2 tiers with `maxPrescribedLoadLb`, relay + FM kill switches with the `INCIDENTS.md` runbook, and the onboarding safety disclaimer with the age-16 acknowledgment. The relay serves deterministic safety copy from a dedicated 10x rate bucket before the normal quota, and the binding contract is [`COACH_SAFETY.md`](COACH_SAFETY.md). |
| UI-test stabilization | The June 7 Build & Test regression was bisected to `939d69e` + `316c925`: an XCUITest accessibility-snapshot starvation on the active-workout surface (lazy container re-placing every resident card on each 1Hz rest-timer tick, plus per-event AX mutations and os_log streaming amplification) and an orphaned co-design identifier. Fixed via eager VStack for the session container, memoized illustration thumbnails, coalesced telemetry-probe publishes, updates-frequently rest timer, non-animated tick-driven progress rings, and `OS_ACTIVITY_MODE=disable` for the app under test. Co-design, accessibility5, intent, and HealthKit journeys verified green locally. |
| Review state | All 56 review threads on PR #363 (the former reviewer + Codex, rounds 1-5) are replied-to and resolved, including two reviewer-confirmed P1 safety fixes and a sweep-discovered false positive where any "I haven't ..." prompt escalated to emergency copy. |
| Positioning sweep (VOL-279) | Onboarding promise, paywall value framing, HealthKit usage description, and App Store subtitle/keywords/promotional text/description repositioned to prescriptive strength programming; 16 snapshot baselines re-recorded and verified; the product-voice rule is codified in `PRODUCT_POSITIONING.md` and enforced by `check_release_hygiene.sh`. |
| Remaining launch gates | VOL-269 live coach eval trend, fresh TestFlight/Xcode Cloud proof, remaining VOL-270 watch/marketing/widget visual parity and tab-chrome drift signoff, VOL-271 paired iPhone/Watch UAT, VOL-273 App Store/legal/pricing, VOL-274 live eval/cost/deprecation proof, and remaining VOL-275 co-design template/dedicated-screen/Watch proof remain open. The branch now blocks release-ready validation on stale/failing coach trend evidence instead of relying on manual memory. |

## Competitor Baseline

The release strategy keeps VolumeArc focused on Apple-native strength coaching instead of trying to out-breadth every competitor.

| Competitor | Current official signal | VolumeArc response |
|---|---|---|
| Fitbod | App Store copy emphasizes personalized AI workouts, 1000+ exercises, video demos, Apple Health, Strava, Fitbit, Apple Watch, Editors' Choice, and a large ratings base. | Win on Apple-native depth, Watch-first speed, readiness prescription, privacy, and craft; do not claim the broadest exercise library. |
| WHOOP | 2026 updates include WHOOP AI plus Strength Trainer, AI workout generation, passive muscular load, and AI-linked exercises after lifting. | Make readiness and strength prescription the first-run aha, with Apple Health and Watch data changing the actual workout. |
| Future | App Store copy emphasizes adaptive data-driven training, real-time feedback, instant adjustments, audio guidance, Apple Watch integration, and HealthKit. | Do not compete on human-coach framing; win on faster, lower-friction, automated Apple-native coaching. |

References: [Fitbod App Store](https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543), [WHOOP 2026 updates](https://www.whoop.com/us/en/thelocker/2026-whats-new/), [Future App Store](https://apps.apple.com/us/app/future-personalized-workouts/id6744624390).
