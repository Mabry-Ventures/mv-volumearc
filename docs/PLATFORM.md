# VolumeArc Platform — Canonical Reference

[![CI](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml/badge.svg)](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FMabry-Ventures%2Fmv-volumearc%2Fmetrics%2Fcoverage-trend.json&label=coverage&query=%24.records%5B-1%3A%5D.coverage&suffix=%25&color=brightgreen)](docs/TESTING.md#coverage-artifacts)

This is the canonical source of truth for the VolumeArc Apple platform. AI-powered strength training coach for iOS and watchOS. Tracks workouts, provides real-time coaching via voice and text, syncs across devices with CloudKit, and surfaces training signals through widgets and Live Activities.

**Owner:** Mabry Ventures (`com.mabryventures.VolumeArc`)

> **How to keep this current:** Whenever a PR changes the implementation status of a system (a stub becomes real, a feature ships, scope changes), update the relevant row in the [Implementation Status](#implementation-status) table and the matching system description below in the same PR. The status table here is the single source of truth — `CLAUDE.md` is just a pointer at this file. Topic-specific deep dives live in their own siblings: [`ARCHITECTURE.md`](ARCHITECTURE.md), [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md), [`TESTING.md`](TESTING.md), [`USER_JOURNEYS.md`](USER_JOURNEYS.md), [`RELEASE.md`](RELEASE.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), [`AUDIT.md`](AUDIT.md).

## Table of contents

- [Implementation Status](#implementation-status)
- [Targets](#targets)
- [Key Components](#key-components)
- [Data Models](#data-models-swiftdata)
- [Telemetry](#telemetry)
- [Notifications](#notifications)
- [Feature Flags](#feature-flags)
- [Network Reachability](#network-reachability)
- [Subscriptions](#subscriptions)
- [Configuration](#configuration)
- [Build System](#build-system)
- [Code Conventions](#code-conventions)

## Implementation Status

> **Status: Pre-production — hardening, coverage uplift, killer-app additions.** The original post-95/95 launch blockers (VOL-55, 56, 57, 58, 59, 62, 63, 65, 67) shipped in PRs [#23](https://github.com/Mabry-Ventures/mv-volumearc/pull/23)–[#31](https://github.com/Mabry-Ventures/mv-volumearc/pull/31) between 2026-04-14 and 2026-04-20. The Go-Live Readiness sweep (VOL-70 through VOL-77, VOL-89, VOL-95, VOL-100) landed in PRs [#43](https://github.com/Mabry-Ventures/mv-volumearc/pull/43)–[#63](https://github.com/Mabry-Ventures/mv-volumearc/pull/63) between 2026-04-22 and 2026-04-23, closing the App Store submission blockers and hygiene gaps.
>
> A **forensic production-readiness audit on 2026-05-01** (full report: [`AUDIT.md`](AUDIT.md)) scored the platform at **84/100** and surfaced 27 net-new gaps. **Re-scored 2026-05-09: 88/100** after Wave-1 closures (launch chain end-to-end on rc26 + AI review gate confirmed enforcing + dSYM auto-upload + fork-PR guard + marketing site live). 8 new tickets filed during the May-9 review (VOL-163 through VOL-170): rc26 hardware verification, UI test cascade flakiness, branch hygiene, coverage trend pipeline fix, AUDIT re-score (this commit), chaos infrastructure, LLM-driven exploratory UAT, property-based testing. All open work lives in the [**VolumeArc Production Readiness**](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d) Linear project, planned across four waves over cycles 4–11 (2026-05-03 → 2026-07-12). Project-level commitments include: **90%+ test coverage on all appropriate surfaces** (VOL-140), **100% user journeys documented + paired XCUITest** (VOL-141, see [`USER_JOURNEYS.md`](USER_JOURNEYS.md)), and two killer-app differentiators (**curated programs library** VOL-144, **HealthKit-depth coach prompt** VOL-145) shipped before broad public launch.
>
> ### Open items by theme
>
> **App Store submission blockers (May 9 update)**: launch chain shipped end-to-end through rc26 / Build 11. Closed: `aps-environment` split per-config (VOL-70 / PR #43), paywall Terms/Privacy wired through `LegalLinks` (VOL-71 / PR #44), privacy manifest (VOL-73 / PR #45), Sentry PII scrubbing (VOL-72 / PR #46), TestFlight pipeline proven (VOL-126), iCloud/CloudKit launch crash + entitlement runtime probe (PRs #114–#125), Cloudflare relay custom domain `relay.volumearc.app` (PR #128–#129), Sentry DSN + AI Relay URL injection from Xcode Cloud env (PRs #132–#143), watch app archive validation (PRs #134–#143). **Remaining open**: VOL-124 (legal pages content), VOL-125 (App Store metadata + screenshots), VOL-127 (UAT permission journeys), VOL-131 (device family decision — recommend iPhone-only for v1.0).
>
> **Known hygiene gaps**: closed.
> - **VOL-61** — `FeatureFlagProvider` is now wired via `FlagGateTelemetry` into voice, sync, Live Activities, and Foundation Models (PR [#56](https://github.com/Mabry-Ventures/mv-volumearc/pull/56))
> - **VOL-66** — `AIRelayCoachProvider.streamCoachResponse` now consumes real `text/event-stream` from the Worker with Gemini 3.1 (PR [#57](https://github.com/Mabry-Ventures/mv-volumearc/pull/57))
> - **VOL-69** — VAUI adopts real iOS 26 Liquid Glass APIs (`SwiftUI.Glass`, `View.glassEffect`, `GlassEffectContainer`) via the `View.vaGlassBackground(...)` modifier in `Materials.swift`. Surfaces using the modifier today (10 call sites): cards + toasts + components (Components.swift), coach bubbles (CoachPlanningComponents.swift), coach composer (CoachView.swift), paywall (PaywallView.swift), onboarding (OnboardingView.swift), Today metric blocks (TodayView.swift), Workouts list (WorkoutsView.swift), session metric grid (SessionDetailView.swift), plus token definitions in Tokens.swift. Initial PR [#54](https://github.com/Mabry-Ventures/mv-volumearc/pull/54); subsequent surface additions tracked under VAUI design-system burndown.
> - **VOL-74** — `CloudSync.swift` (1489 lines) split into focused files under `VolumeArcCore/CloudSync/`. Initial 6 in PR [#50](https://github.com/Mabry-Ventures/mv-volumearc/pull/50); now 8 after subsequent factorings: `CloudKitSyncTransport`, `CloudSyncCoordinator`, `CloudSyncTypes`, `RetryingCloudSyncTransport`, `SyncPayloadApplier`, `SyncPayloadApplier+PerKind`, `SyncPayloadCodec`, `SyncPayloadCodec+LegacySynthesis`.
>
> **Infrastructure / release**: closed. SwiftLint pre-flight + hard-fail live on the runner (VOL-77 / PR #47), `CI_TAG_BUILD=1` is now set on the deploy job (PR #47), CODEOWNERS + Dependabot + PR/Issue templates are checked in under `.github/`, Package.resolved tracked at repo root (PR #60), deterministic Xcode project generation with a CI gate (VOL-95 / PR #61), coverage artifacts + trend file published per run (PR #62).
>
> The status table below reflects current reality. Do not flip any row from a gap to Implemented without (a) a PR that wires the code and (b) a Linear ticket transition.

| System | Status | Notes |
|--------|--------|-------|
| iPhone UI | Implemented | Full tab bar (Today, Workouts, Coach, Signals, Profile). `RootDashboardView` presents `OnboardingView` via `fullScreenCover` on first launch. `ProfileView` presents `PaywallView` via sheet on upgrade tap. Localized, accessible, Dynamic Type, hero transitions, toast presenter all working |
| AI coaching | Implemented (streaming — VOL-66; tier-gated — VOL-91) | Three-provider chain works end-to-end. All three providers (`AIRelayCoachProvider`, `LocalHeuristicAICoachProvider`, `FoundationModelCoachProvider`) route their outbound prompts through `CoachPromptTemplate.render(intent:contextBlock:question:style:)` so the system prompt, intent envelope, structured context block, and template marker are identical across the cloud, on-device, and offline paths. `AIRelayCoachProvider.streamCoachResponse` consumes `text/event-stream` from the `volumearc-ai-relay` Cloudflare Worker and yields Gemini 3.1 tokens progressively (VOL-66 / PR #57); the synthetic word-chunking default is retained for providers without native streaming. Cloud tier is entitlement-gated: `VolumeArcAIRuntimeFactory.makeCoachProvider(subscriptionStore:)` installs `AIRelayCoachProvider` with `tier: .pro` (`X-Coach-Tier: pro` → Gemini Pro on the Worker) for premium users, `tier: .flashLite` (→ Gemini Flash Lite) for free. On-device FM and local heuristic fallback are the same for both tiers |
| Voice coaching | Implemented (single-turn) | `AIRelayVoiceTransport` delegates to the same relay-backed `AICoachProvider` chain; `LiveVoiceCoachOrchestrator` exposes `speak(prompt:context:)` and lifecycle hooks. Live duplex audio is explicit future work |
| Cloud sync | Implemented (entitlement-gated at runtime) | CloudKit container ID is a compile-time constant (`App/VolumeArcCloudConfiguration.swift`). `CKModifyRecordsOperation` push + `CKFetchRecordZoneChangesOperation` pull + cursor persistence work on device/TestFlight builds with entitlements. Every repository write path calls `stageUpsert` into `OutboundSyncQueue`, which `CloudSyncCoordinator` drains on `syncCycle`. Simulator Debug builds fall back to `UnavailableCloudSyncTransport` because they lack the entitlement |
| Watch app | Implemented | HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder`, rest timer, decisions, accessibility, offline payload queue, real phone/watch sync via WCSession |
| Widgets | Implemented | `NextWorkoutWidget` + `WatchWidgets` extension read real shared state via `PlatformSurfaceDefaultsReader`, design-system-tokened, accessibility-labelled |
| Live Activities | Implemented | `ActiveWorkoutLiveActivity` with real updates from workout session state, Dynamic Island layouts |
| Notifications | Implemented | Scheduler wired into rest timer completion and training plan reminders, actionable categories (REST_TIMER, WORKOUT_REMINDER) |
| Background tasks | Implemented | `App/VolumeArcBackgroundTasks.swift` registers `appRefresh` + `appProcessing`. `App/Info.plist` declares `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes` so iOS accepts the registrations |
| Persistence | Implemented | Four-tier fallback chain, seed data, schema, real repository CRUD all work. `VolumeArcSchemaMigrationPlan` bridges the legacy V1 training-plan shape through V2 to V3, with on-disk round-trip migration tests |
| Secure storage | Implemented | Keychain with fallback, device ID stability |
| Relay auth | Implemented | Actor-based session provider, token caching, expiration skew, real test coverage against production types |
| Telemetry | Implemented | Fanout sink architecture. `SentryTelemetrySink` forwards events as breadcrumbs and captures `.error` severity as Sentry messages. `UserDefaultsTelemetrySink` and `OSLogTelemetrySink` persist/log for diagnostics. PII scrubbing via `VolumeArcSentryPIIScrubber` is installed as Sentry `beforeSend` / `beforeBreadcrumb` (VOL-72 / PR #46) — redacts user identifiers, emails, phone numbers, and drops deny-listed categories before any payload leaves the device |
| Feature flags | Implemented | `LocalFeatureFlagProvider` is wired through `FlagGateTelemetry` into `VolumeArcAIRuntimeFactory.makeVoiceCoach`, `CloudSyncCoordinator.syncCycle`, the Live Activity controller, and the Foundation Models provider selection (VOL-61 / PR #56). First resolution per flag per launch emits a `feature.flag.applied` `.info` telemetry event |
| Subscriptions | Implemented (entitlement gating — VOL-91) | StoreKit 2 store and `PaywallView` are wired, presented from `ProfileView`, and drive entitlement state. `StoreKitSubscriptionStore` conforms to `PremiumEntitlementProviding` and threads through `VolumeArcAIRuntimeFactory` at launch: premium unlocks Gemini Pro (coach tier) and live voice (gated AND on `.voiceCoaching` flag); free stays on Flash Lite + `UnavailableVoiceTransport`. Cloud sync, Foundation Models, and Live Activities are currently free for all — gating decision parked in the VOL-91 PR for product to revise. One-shot `premium.entitlement.gated` telemetry event per feature per launch records which tier/transport was installed. Terms/Privacy links open placeholder URLs (`https://volumearc.app/terms`, `/privacy`) via `LegalLinks` (VOL-71 / PR #44) — marketing pages stand up closer to launch. Guideline 3.1.2 auto-renewal disclosure present |
| Build pipeline | Implemented | Ruby-generated Xcode project (byte-identical output across regens — VOL-95 / PR #61), CI on the dedicated M4 self-hosted runner label `mv-shared` (VOL-88), Fastlane, archive script, hard-failing `validate_release_config.sh` on Info.plist keys/URL schemes/BGTask IDs + Release `aps-environment = production` (VOL-70 / PR #43) and on signed entitlements in the built `.xcarchive` — iCloud container identifier, HealthKit, App Groups — via `codesign -d --entitlements -` (VOL-92). The Fastlane `beta` lane runs the validator after `gym` but before `upload_to_testflight` so entitlement regressions fail the lane before anything hits App Store Connect. SwiftLint is pre-flight-checked on the runner and hard-fails on errors (VOL-77 / PR #47). `CI_TAG_BUILD=1` is set in the deploy job so `VERSION`-bump enforcement fires on tag builds. Package.resolved is tracked at repo root as the canonical SPM lockfile (PR #60) |
| Testing | Implemented (80% VolumeArcCore gate enforced — VOL-52; uplift to 90%+ in flight via VOL-140) | 356 test functions (unit + integration + XCUITest journey + performance) pass, including onboarding, paywall, StoreKit Test purchase, active workout completion, HealthKit prompt simulation, Dynamic Type/pseudo-locale, and Watch payload simulation. `VolumeArcLaunchArguments` are live and wire into `VolumeArcLaunchBootstrapper`. Dashboard integration tests cover the create → log → complete chain against in-memory SwiftData. CI blocks merges that drop `VolumeArcCore` line coverage below 80%; raise to 90% + add `VolumeArcUI` (≥85%) / `VolumeArcWatch` (≥85% pending VOL-138) / Widgets (≥75% pending VOL-139) gates is tracked in [VOL-140](https://linear.app/mabry-ventures/issue/VOL-140). Visual regression (snapshot tests) pending [VOL-135](https://linear.app/mabry-ventures/issue/VOL-135). HealthKit + CloudKit fake unit-test harnesses pending [VOL-136](https://linear.app/mabry-ventures/issue/VOL-136) / [VOL-137](https://linear.app/mabry-ventures/issue/VOL-137). User-journey catalog ([`USER_JOURNEYS.md`](USER_JOURNEYS.md)) at 15%, target 100% via [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141). Coverage artifacts (xcresult bundle, step summary, sticky PR comment, `docs/coverage-trend.json`) published per run (VOL-97 / PR #62). See [`docs/TESTING.md`](TESTING.md#coverage-expectations) for the per-target gate map |
| Performance testing (VOL-99) | Implemented (tag-gated) | Four `XCTMetric`-family budgets (cold launch, Today scroll, memory, coach first-token) in `VolumeArcAppPerfTests` enforced by `scripts/check_performance.sh` against `docs/performance-budgets.json`. Tag-gated `perf-regression` job in `.github/workflows/ci.yml` runs the suite on `v*` tags, blocks TestFlight deploy on budget breach, and appends each run to `docs/performance-trend.json`. See [`docs/PERFORMANCE.md`](PERFORMANCE.md) for the budget table |
| AI coach eval harness | Implemented (template-layer hermetic; response-layer manual/nightly — VOL-100) | 20 JSON fixtures under `Tests/Evals/CoachEvalFixtures/` cover readiness (45/60/72/82/88) × intent (progression, deload, form, recovery, substitution, free) × history (empty/1/5 sessions) × style (motivational, analytical, minimal). `CoachEvalTests` (iOS test bundle) asserts template-layer invariants — template marker, intent envelope, system prompt persona per style, verbatim context/question preservation, per-intent envelope fragment, renderer determinism — against every fixture and fails if any axis loses coverage. `scripts/run_coach_evals.sh` POSTs the fixtures to the live relay (`VOLUMEARC_RELAY_SIGNING_KEY` required) and asserts response-quality expectations (sentence cap, numeric grounding, banned phrases, pain-signal flagging). See [`docs/COACH_EVALS.md`](COACH_EVALS.md) for per-fixture notes and the latest run table. Nightly CI wiring tracked as a follow-up |
| App Store readiness | Code blockers closed | `aps-environment = production` for Release (VOL-70 / PR #43), paywall Terms/Privacy routed through `LegalLinks` (VOL-71 / PR #44), privacy manifest completeness verified (VOL-73 / PR #45), Sentry PII scrubbing live (VOL-72 / PR #46). Non-code remainder: marketing pages at `volumearc.app/terms` and `/privacy`, final App Store Connect metadata, screenshots, and a TestFlight review pass — tracked in Linear Production Readiness project |
| Marketing site | Live ([volumearc.app](https://volumearc.app)) | Next.js 16 + Tailwind CSS v4 + shadcn/ui app under [`marketing/`](../marketing). Adapted from Tailwind Plus Pocket and refreshed to match the iOS app's design language: real `AppIcon-Light.png` rendered in `Logo.tsx` + favicon/apple-touch/OG via Next.js conventions; sunrise palette ported from `VA.Colors` (peach → orange → coral) as `--color-sunrise-*` and `--color-coral-*` Tailwind tokens; Liquid Glass approximated via `va-glass` utility (backdrop-blur). Pages: `/`, `/terms`, `/privacy`, `/support`, `/quality`. Deployed to Vercel at `volumearc.app` (apex canonical) with `volumearc.com`, `www.*` 308-redirecting (VOL-160 done). Cloudflare DNS-only, Let's Encrypt via Vercel. CI build/lint gate at [`.github/workflows/marketing.yml`](../.github/workflows/marketing.yml). Legal-counsel content review (VOL-124) and copywriting polish (VOL-161) ongoing. See [`MARKETING.md`](MARKETING.md) for architecture and deploy flow |

## Targets

| Target | Type | Platform | Bundle ID |
|--------|------|----------|-----------|
| VolumeArcApp | iOS Application | iOS 26.0 | `com.mabryventures.VolumeArc` |
| VolumeArcWatch | watchOS Application | watchOS 26.4 | `com.mabryventures.VolumeArc.watchkitapp` |
| VolumeArcWidgets | Widget Extension | iOS 26.0 | `com.mabryventures.VolumeArc.widgets` |
| VolumeArcWatchWidgets | Widget Extension | watchOS 26.4 | `com.mabryventures.VolumeArc.watchwidgets` |
| VolumeArcAppTests | Unit Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.tests` |
| VolumeArcAppUITests | UI Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.uitests` |
| VolumeArcAppPerfTests | UI Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.perftests` |
| VolumeArcCore | Static Library | iOS 26.0 | -- (from `VolumeArcNative/`) |
| VolumeArcCoreWatch | Static Library | watchOS 26.4 | -- (same `VolumeArcCore` module, built for watchOS from `VolumeArcNative/`) |
| VolumeArcUI | Static Library | iOS 26.0 | -- (from `VolumeArcNative/`) |

### Supported device families (VOL-131)

| Family | v1.0 TestFlight + App Store | Rationale |
|---|---|---|
| **iPhone** (iOS 26.0+) | ✅ Supported (primary surface) | Full feature set: tab bar, onboarding, paywall, coach, Live Activity, widgets, watch pairing. `TARGETED_DEVICE_FAMILY = 1`. |
| **Apple Watch** (watchOS 26.4+) | ✅ Supported (paired with iPhone) | Watch app + widgets ship in the same iPhone build per the iOS / watchOS pairing requirement. Documented in App Store description. |
| **iPad** | ❌ Not supported in v1.0 | Layout has not been audited for the iPad form factor (multitasking, regular size class, sidebar nav). Deferred until [VOL-158](https://linear.app/mabry-ventures/issue/VOL-158) completes the UX-audit pass. `TARGETED_DEVICE_FAMILY` is `1` (iPhone only); the App Store listing will be set to "iPhone only" until the audit signs off. |
| **visionOS** | ❌ Explicitly not supported | App Store metadata sets the platform compatibility flag to exclude visionOS. Revisit post-launch once we have iPhone telemetry to validate the form-factor strategy. |
| **macOS Catalyst** | ❌ Explicitly not supported | The coaching surfaces depend on touch + haptics + a paired Apple Watch; Catalyst doesn't deliver that experience cleanly. Revisit per [VOL-159](https://linear.app/mabry-ventures/issue/VOL-159) (Apple Intelligence) and platform sales data. |

**TestFlight + App Store screenshot matrix** (`fastlane/Snapfile`) is intentionally iPhone-only (`iPhone 17`, `iPhone 17 Pro Max`, `Apple Watch Series 11 (46mm)`) to match the supported-device declaration. Adding iPad later means: re-running VOL-158 audit, flipping `TARGETED_DEVICE_FAMILY` to `1,2`, adding iPad devices to Snapfile, regenerating screenshots, and updating the App Store description.

**Dependency graph:** `VolumeArcUI -> VolumeArcCore`. iOS app, iOS widgets, and tests depend on the iOS `VolumeArcCore` target. The watch app and watch widgets depend on `VolumeArcCoreWatch`, which compiles the same sources as module `VolumeArcCore` for watchOS so archive builds do not cross-link the iOS static library. The iOS app and tests also depend on `VolumeArcUI`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full module breakdown and data flow.

## Key Components

**App entry point** (`VolumeArcApp.swift`): Wires all dependencies into `WorkoutDashboardModel` and installs `RootDashboardView`. Handles deep links, Watch Connectivity payloads, HealthKit background updates, widget snapshot changes, and Live Activity lifecycle.

**Persistence** (`VolumeArcPersistenceController.swift`): SwiftData with cascading fallback -- CloudSynced -> LocalFallback -> InMemoryFallback -> Unavailable. Seeds default `UserProfileRecord` and `TrainingPlanRecord` on first launch.

**AI coaching** (`VolumeArcAIRuntimeFactory.swift`): Three-tier provider chain with `AsyncThrowingStream` streaming, memory append via `CoachMemoryRepository`, and structured output parsing. Every provider routes its outbound prompt through `CoachPromptTemplate.render(...)` so the system prompt, per-intent envelope, structured context block, and template marker are identical across the cloud, on-device, and offline paths — a regression that bypasses the template drops the marker and trips `VolumeArcCoachPromptTemplateTests`:
1. `FoundationModelCoachProvider` (on-device, iOS 26.0+ only)
2. `AIRelayCoachProvider` (cloud relay)
3. `LocalHeuristicAICoachProvider` (offline fallback)

**Voice coaching** (`VolumeArcCore/AI/VoiceCoach.swift`, `VolumeArcAIRuntimeFactory.swift`): `LiveVoiceCoachOrchestrator` backed by `AIRelayVoiceTransport` (single-turn — delegates to the same relay-backed `AICoachProvider` chain used by the text coach) or `UnavailableVoiceTransport` when relay is unconfigured. The orchestrator exposes `speak(prompt:context:)` for question/response turns and lifecycle hooks (`start`, `interrupt`, `end`) which are no-ops for the single-turn transport. A future feature will introduce a real `OpenAIRealtimeWebRTCTransport` that maintains a persistent duplex audio session against the OpenAI Realtime API; the protocol shape supports both transports without rework.

**Cloud sync** (`VolumeArcCloudConfiguration.swift`): `CloudSyncCoordinator` drives `CloudKitSyncTransport` using zone `VolumeArcSyncZone` in container `iCloud.com.mabryventures.VolumeArc`. Push uses `CKModifyRecordsOperation`; pull uses `CKFetchRecordZoneChangesOperation` with cursor persistence in `FileSyncStateStore`. `DefaultSyncPayloadApplier` writes changes into SwiftData with conflict resolution. Falls back to `UnavailableCloudSyncTransport` if unconfigured.

**Relay auth** (`VolumeArcRelaySessionProvider.swift`): Actor that manages device-ID-based session tokens for the AI relay. Tokens cached in Keychain with ISO8601 expiration and 60-second refresh skew.

**Secure storage** (`VolumeArcSecureStore.swift`): Keychain wrapper with `UserDefaults` fallback in Debug/Simulator builds.

**Watch app** (`WatchWorkoutView.swift`): `WatchWorkoutModel` manages `HKWorkoutSession` + `HKLiveWorkoutBuilder` for real HealthKit workout tracking, rest timers (90s default), coach cue requests, and set decisions (increase/hold/decrease). Communicates with iPhone via `WatchConnectivityCoordinator` with real `WCSession` transfer and offline payload queue replay when the phone is unreachable.

**Widgets** (`VolumeArcWidgets.swift`, `WatchWidgets/`): `NextWorkoutWidget` (systemSmall, systemMedium) and the watchOS widget extension read from `PlatformSurfaceDefaultsReader` which returns real snapshots written by the app on state changes. `ActiveWorkoutLiveActivity` shows exercise, target, and rest timer on lock screen and Dynamic Island with real updates driven by the workout session controller.

**App Intents** (`VolumeArcIntents.swift`): Six Siri Shortcuts -- StartNextWorkout, AskCoach, OpenSignals, StartWorkoutSession, LogRecommendedSet, SyncVolumeArc. All open the app via `VolumeArcDeepLink` and `RootDashboardView` consumes `DashboardNavigationModel.selectedTab` + `coachPrompt` to route to the correct destination. Dashboard action methods drive real state changes through the repository layer.

## Data Models (SwiftData)

Schema: current `VolumeArcSchemaV3` with `VolumeArcSchemaMigrationPlan` bridging `VolumeArcSchemaV1 -> VolumeArcSchemaV2 -> VolumeArcSchemaV3` (migration-tested).

- `UserProfileRecord` -- coaching style, privacy mode, advancement level, equipment, rep ranges, time budget, training days, via `SwiftDataUserProfileRepository`
- `WorkoutRecord` -- via `SwiftDataWorkoutRepository` (create, append set with aggregate update, complete, fetch recent, history projection)
- `TrainingPlanRecord` -- weekly schedule, via `SwiftDataTrainingPlanRepository` (upsert, fetch)
- `CoachMemoryRecord` -- AI coach context, via `SwiftDataCoachMemoryRepository` (append, fetch recent)

## Telemetry

Fanout sink: `InMemoryTelemetrySink` (bootstrap) + `UserDefaultsTelemetrySink` (persistent, NSLock-guarded) + `OSLogTelemetrySink` + `SentryTelemetrySink` (when configured). Startup signals surface degraded persistence, missing AI relay, missing CloudKit config, or missing Sentry DSN. `SentryTelemetrySink` forwards events as breadcrumbs and captures `.error` severity as Sentry messages.

## Notifications

**Notification scheduler** (`VolumeArcNotificationScheduler.swift`): Schedules local notifications for rest timer expiration and workout reminders from the training plan. Registers actionable notification categories (`REST_TIMER` with Dismiss, `WORKOUT_REMINDER` with Start Workout / Dismiss). Called from rest timer completion handlers and the training plan scheduler.

## Feature Flags

`FeatureFlagProvider` protocol in `VolumeArcCore` with `LocalFeatureFlagProvider` (UserDefaults-backed). Flags: `voiceCoaching`, `cloudSync`, `liveActivities`, `foundationModelCoach`. Overridable per-flag for development. Wired into feature gates on the paywall, runtime factory, and live activity controller.

## Network Reachability

`NetworkReachabilityMonitor` in `VolumeArcCore` wraps `NWPathMonitor` for connectivity detection. Exposes `isReachable`, `isCellular`, and `isConstrained` properties with a `start(onChange:)` callback. Used by `WatchConnectivityCoordinator` offline queue replay and `CloudSyncCoordinator` back-off logic.

## Subscriptions

StoreKit 2 with two products and `@Published` entitlement state:
- `com.mabryventures.VolumeArc.premium.monthly`
- `com.mabryventures.VolumeArc.premium.yearly`

`StoreKitSubscriptionStore` drives a full `PaywallView` (plans, features, restore, terms/privacy links) and exposes `isPremium: Bool` via the `PremiumEntitlementProviding` protocol that `VolumeArcAIRuntimeFactory` reads at launch.

**Premium unlocks (VOL-91):**
- **AI coach tier.** Premium users get Gemini Pro (`AIRelayCoachProvider(tier: .pro)` → `X-Coach-Tier: pro` header → Worker routes to Pro). Free users get Gemini Flash Lite.
- **Live voice coaching.** `AIRelayVoiceTransport` installs only when `isPremium == true` AND the `.voiceCoaching` flag is on; every other combination falls through to `UnavailableVoiceTransport` so `LiveVoiceCoachOrchestrator.speak` throws `AIRuntimeIntegrationError.relayUnavailable`.

**Not gated (currently free for all):** cloud sync, Foundation Models (on-device coach), Live Activities. This decision is parked in the VOL-91 PR body for product to revise — switching any of these to premium is a one-line change at the factory / coordinator call site that threads the `subscriptionStore` in.

**Telemetry.** `PremiumGateTelemetry` (mirrors the VOL-61 `FlagGateTelemetry` pattern) emits one `.info` event per premium-gated feature per launch: category `premium.entitlement.gated`, name `coach_tier` | `live_voice`, metadata `{"premium": "true" | "false"}`. Dedupe is NSLock-guarded so multiple factory invocations inside `VolumeArcApp.init` don't double-count.

## Configuration

### Environment / Info.plist Keys

| Key | Source | Purpose |
|-----|--------|---------|
| `VOLUMEARC_AI_RELAY_URL` | Env var or `VolumeArcAIRelayURL` in Info.plist | AI relay base URL for cloud coach + voice |
| `VolumeArcCloudKitContainer` | Info.plist | CloudKit container identifier (`iCloud.com.mabryventures.VolumeArc`) |
| `VOLUMEARC_SENTRY_DSN` | Env var or `VolumeArcSentryDSN` in Info.plist | Sentry DSN for crash reporting and telemetry |

The AI relay URL is bootstrapped into Keychain at launch. If neither source provides it, cloud AI and live voice are disabled with a startup warning.

### Crash Reporting

Sentry (`sentry-cocoa`) is integrated via `VolumeArcSentryConfiguration`. It follows the same pattern as the AI relay — DSN loaded from Keychain, environment variable, or Info.plist. A `SentryTelemetrySink` is added to the telemetry fanout when configured, forwarding telemetry events as Sentry breadcrumbs and capturing `.error` severity events as Sentry messages. If unconfigured, the app runs without crash reporting and surfaces a startup warning.

### Entitlements

**iOS App:** HealthKit, CloudKit, iCloud Containers (`iCloud.com.mabryventures.VolumeArc`), App Groups (`group.com.mabryventures.volumearc`), Push Notifications (`aps-environment`)

**watchOS:** HealthKit, App Groups (`group.com.mabryventures.volumearc`)

**Widgets:** App Groups (`group.com.mabryventures.volumearc`)

### Deep Link Scheme

URL scheme: `volumearc://`

Routes: `.today`, `.nextWorkout`, `.coach(prompt:)`, `.signals`, `.action(.startWorkoutSession)`, `.action(.logRecommendedSet)`, `.action(.syncNow)`

## Build System

The Xcode project is **generated** -- do not edit `project.pbxproj` by hand. Run `ruby scripts/generate_xcode_project.rb` to regenerate.

**Requirements:** Ruby with the `xcodeproj` gem, Xcode 26.4+

**Swift version:** 6.0

### Versioning

`MARKETING_VERSION` is read from the `VERSION` file at the repo root (e.g., `1.0.0`). `CURRENT_PROJECT_VERSION` (build number) is pinned to `1` in the committed pbxproj so `ruby scripts/generate_xcode_project.rb` is a true no-op against `main` (VOL-106 — prior behavior derived it from `git rev-list --count HEAD`, which bumped on every merge and cascaded 300-line UUID churn through `predictabilize_uuids`). Release tooling overrides it at build time: `scripts/archive_for_distribution.sh` exports `BUILD_NUMBER=$(git rev-list --count HEAD)` into the generator and passes `CURRENT_PROJECT_VERSION=$BUILD_NUMBER` to `xcodebuild archive`; Fastlane's `ios beta` lane calls `increment_build_number` with the same count before `build_app`; Xcode Cloud's `ci_post_clone.sh` patches the throwaway checked-out project to `CI_BUILD_NUMBER` before archive because Xcode Cloud exposes that value only as a shell environment variable. So TestFlight/App Store uploads still ship monotonic build numbers; only local dev builds see `CURRENT_PROJECT_VERSION = 1`. The `DEVELOPMENT_TEAM` can be passed as an env var for signing builds.

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/generate_xcode_project.rb` | Generates `VolumeArcApple.xcodeproj` from scratch, configuring all targets, dependencies, and build settings |
| `scripts/build_all_targets.sh` | Debug build of all targets (iOS simulator + watchOS simulator) |
| `scripts/build_release_targets.sh` | Release build of all targets |
| `scripts/test_apple_targets.sh` | Runs both `VolumeArcAppTests` (unit + integration) and `VolumeArcAppUITests` (XCUITest smoke) on iPhone 17 simulator |
| `scripts/test_performance.sh` | VOL-99. Runs the `VolumeArcAppPerfTests` suite on iPhone 17 simulator and writes an xcresult bundle to `.build/perf-results.xcresult`. Tag-gated in CI |
| `scripts/check_performance.sh` | VOL-99. Parses the perf xcresult bundle, compares each metric against `docs/performance-budgets.json`, fails on any `failThreshold` breach, and appends to `docs/performance-trend.json` |
| `scripts/validate_release_config.sh` | Hard-fails on `ENABLE_TESTABILITY = YES` in Release, `DEBUG_INFORMATION_FORMAT` ≠ `dwarf-with-dsym`, missing entitlements, leaked demo symbols, missing privacy manifests, or unchanged `VERSION` on tag builds |
| `scripts/archive_for_distribution.sh` | Archives and exports a signed IPA for App Store / TestFlight. Requires `DEVELOPMENT_TEAM` env var |

All build scripts call `generate_xcode_project.rb` first, so the project is always fresh.

### CI / CD

GitHub Actions CI runs on the dedicated Apple Silicon self-hosted runner currently registered with the `mv-shared` label (`runs-on: [self-hosted, mv-shared]`). The workflow (`.github/workflows/ci.yml`) triggers on pushes to `main`, pull requests, and version tags (`v*`).

**CI pipeline:** Checkout → Pre-flight (Xcode / Ruby / xcodeproj / SwiftLint / disk headroom) → Generate Xcode project → Xcode project determinism gate (regenerate twice, diff SHA256 — VOL-95) → Xcode project no-op regen gate (regenerate over committed state, fail on any drift — VOL-106) → Seed SPM lockfile → Clear stale DerivedData → Build all targets (Debug) → Run unit + integration tests → XCUITest smoke suite → Coverage gate (VolumeArcCore ≥ 80% — VOL-52) → Upload xcresult + coverage-summary artifacts → Sticky PR coverage comment → Trend-append on main push → SwiftLint hard-fail → Validate release config. The two-bot AI review gate (CodeRabbit Pro primary + Codex Code Review secondary) runs in a separate workflow (`.github/workflows/ai-review-gate.yml`), posts current-head review requests for both bots, and must observe both review signals on the current head SHA within the wait window for the gate to pass.

**TestFlight deploy:** On version tags (`v*`), a second job runs `fastlane ios beta` to archive, sign, and upload to TestFlight. Requires `DEVELOPMENT_TEAM` and `APP_STORE_CONNECT_API_KEY_PATH` secrets.

**Fastlane:** `Gemfile` + `fastlane/Fastfile` with three lanes: `test` (run tests with coverage), `beta` (build + upload to TestFlight), `release` (submit to App Store review).

### Privacy Manifests

Each target includes a `PrivacyInfo.xcprivacy` declaring required reason API usage (UserDefaults, FileTimestamp). These are added to targets by `generate_xcode_project.rb` and validated by `validate_release_config.sh`.

### Localization

Every user-facing string in `VolumeArcUI/Screens/` and `Watch/` goes through `String(localized:comment:)` with a translator comment. Currently English-only, but the full catalog is extractable to a String Catalog (`.xcstrings`) without code changes. Plural-bearing strings use Apple's `^[\(count) thing](inflect: true)` syntax for CLDR plural agreement. Enum display labels live in `VolumeArcNative/Sources/VolumeArcUI/LocalizedLabels.swift` as extensions on `AdvancementLevel`, `CoachingStyle`, `Equipment`, and `PrivacyMode` so translators see all enum-derived labels in one place.

### Accessibility

- `VA.Typography` tokens use `Font.system(TextStyle, design:, weight:)` so every text style scales with Dynamic Type from `.xSmall` through `.accessibility5`.
- `VAButton`, `VACoachBubble`, `VACard`, and metric displays expose combined accessibility elements with VoiceOver labels, hints, and the `.isButton` trait where interactive.
- Readiness hero, rest timer, coach bubbles, and recent session rows all announce meaningful values (e.g., "Readiness score 82 out of 100", "42 seconds remaining").
- `VAToastPresenter` toasts announce their kind prefix ("Success: Set logged").
- Hero transitions respect `@Environment(\.accessibilityReduceMotion)` and fall back to cross-fade.

### Building

```bash
# Generate project + debug build
./scripts/build_all_targets.sh

# Run tests
./scripts/test_apple_targets.sh

# Validate release config
./scripts/validate_release_config.sh

# Archive for App Store / TestFlight
DEVELOPMENT_TEAM=A886EMZZW6 ./scripts/archive_for_distribution.sh
```

## Code Conventions

- **Conditional compilation everywhere:** All platform-specific APIs guarded with `#if canImport(...)` and `#available(...)` for graceful degradation across platforms and OS versions.
- **Factory pattern for runtime dependencies:** Platform-specific implementations chosen at init time via static factory methods on the app or model types.
- **Unavailable stubs:** Each integration has an `Unavailable*` fallback (e.g., `UnavailableHealthStore`, `UnavailableCloudSyncTransport`, `UnavailableVoiceTransport`) so the app always launches.
- **Actor isolation:** Network-bound providers (`VolumeArcRelaySessionProvider`, `VolumeArcVoicePermissionStore`) use Swift actors for thread safety.
- **No Package.swift at root:** The Xcode project is Ruby-generated, not SPM-based. `VolumeArcNative/` contains the Swift package structure for shared frameworks.
- **Localized strings:** All user-facing strings use `String(localized:comment:)` for future translation support. Plural-bearing strings use `^[count thing](inflect: true)`. Enum labels live in `LocalizedLabels.swift`.
- **Accessibility:** All interactive and data-display elements in Watch and Widget views have VoiceOver labels, hints, and values. Design system components carry built-in accessibility so screens that use them inherit it.
- **Codable payloads:** Watch-to-phone payloads use `Codable` structs encoded via `SyncPayloadCodec` rather than ad-hoc string formatting.
