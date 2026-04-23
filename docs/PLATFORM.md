# VolumeArc Platform — Canonical Reference

[![CI](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml/badge.svg)](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml)

This is the canonical source of truth for the VolumeArc Apple platform. AI-powered strength training coach for iOS and watchOS. Tracks workouts, provides real-time coaching via voice and text, syncs across devices with CloudKit, and surfaces training signals through widgets and Live Activities.

**Owner:** Mabry Ventures (`com.mabryventures.VolumeArc`)

> **How to keep this current:** Whenever a PR changes the implementation status of a system (a stub becomes real, a feature ships, scope changes), update the relevant row in the [Implementation Status](#implementation-status) table and the matching system description below in the same PR. The status table here is the single source of truth — `CLAUDE.md` is just a pointer at this file. Topic-specific deep dives live in their own siblings: [`ARCHITECTURE.md`](ARCHITECTURE.md), [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md), [`TESTING.md`](TESTING.md), [`RELEASE.md`](RELEASE.md), [`CONTRIBUTING.md`](CONTRIBUTING.md).

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

> **Status: Pre-production — hygiene and hardening.** The original post-95/95 launch blockers (VOL-55, 56, 57, 58, 59, 62, 63, 65, 67) shipped in PRs [#23](https://github.com/Mabry-Ventures/mv-volumearc/pull/23)–[#31](https://github.com/Mabry-Ventures/mv-volumearc/pull/31) between 2026-04-14 and 2026-04-20. The end-to-end wiring is now in place, but the app still has App Store blockers (production APS environment, paywall legal links, privacy manifest completeness, Sentry PII scrubbing) and hygiene gaps (dead feature flags, synthetic AI streaming, file-size refactors). **Current open work is tracked in the Linear "Go-Live Readiness" project** on the VolumeArc team.
>
> ### Open items by theme
>
> **App Store submission blockers** (new, from 2026-04-22 audit): `aps-environment` hardcoded to `development`, paywall Terms/Privacy links non-functional, privacy manifest reason-coverage incomplete, Sentry crash reports not PII-scrubbed.
>
> **Known hygiene gaps** (carried from prior audit):
> - **VOL-61** (Backlog) — `FeatureFlagProvider` is dead code; flags gate nothing
> - **VOL-66** (Backlog) — AI streaming is synthetic word-chunking, not real progressive streaming
> - **VOL-69** (Backlog) — Liquid Glass claim — adopt real iOS 26 APIs or update docs
>
> **Infrastructure / release** (new): `Build & Test` must be a required status check, self-hosted runner needs SwiftLint install + SPM cache fix + Ruby upgrade, `CI_TAG_BUILD=1` needs to be set in the deploy job for version-bump enforcement to fire, add CODEOWNERS + Dependabot + PR/Issue templates.
>
> The status table below reflects current reality. Do not flip any row from a gap to Implemented without (a) a PR that wires the code and (b) a Linear ticket transition.

| System | Status | Notes |
|--------|--------|-------|
| iPhone UI | Implemented | Full tab bar (Today, Workouts, Coach, Signals, Profile). `RootDashboardView` presents `OnboardingView` via `fullScreenCover` on first launch. `ProfileView` presents `PaywallView` via sheet on upgrade tap. Localized, accessible, Dynamic Type, hero transitions, toast presenter all working |
| AI coaching | Implemented (synthetic streaming — VOL-66) | Three-provider chain works for non-streaming responses. All three providers (`OpenAIRelayCoachProvider`, `LocalHeuristicAICoachProvider`, `FoundationModelCoachProvider`) route their outbound prompts through `CoachPromptTemplate.render(intent:contextBlock:question:style:)` so the system prompt, intent envelope, structured context block, and template marker are identical across the cloud, on-device, and offline paths. `streamCoachResponse` is still synthetic word-chunking, not real progressive streaming |
| Voice coaching | Implemented (single-turn) | `OpenAIRelayVoiceTransport` delegates to the same relay-backed `AICoachProvider` chain; `LiveVoiceCoachOrchestrator` exposes `speak(prompt:context:)` and lifecycle hooks. Live duplex audio is explicit future work |
| Cloud sync | Implemented (entitlement-gated at runtime) | CloudKit container ID is a compile-time constant (`App/VolumeArcCloudConfiguration.swift`). `CKModifyRecordsOperation` push + `CKFetchRecordZoneChangesOperation` pull + cursor persistence work on device/TestFlight builds with entitlements. Every repository write path calls `stageUpsert` into `OutboundSyncQueue`, which `CloudSyncCoordinator` drains on `syncCycle`. Simulator Debug builds fall back to `UnavailableCloudSyncTransport` because they lack the entitlement |
| Watch app | Implemented | HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder`, rest timer, decisions, accessibility, offline payload queue, real phone/watch sync via WCSession |
| Widgets | Implemented | `NextWorkoutWidget` + `WatchWidgets` extension read real shared state via `PlatformSurfaceDefaultsReader`, design-system-tokened, accessibility-labelled |
| Live Activities | Implemented | `ActiveWorkoutLiveActivity` with real updates from workout session state, Dynamic Island layouts |
| Notifications | Implemented | Scheduler wired into rest timer completion and training plan reminders, actionable categories (REST_TIMER, WORKOUT_REMINDER) |
| Background tasks | Implemented | `App/VolumeArcBackgroundTasks.swift` registers `appRefresh` + `appProcessing`. `App/Info.plist` declares `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes` so iOS accepts the registrations |
| Persistence | Implemented | Four-tier fallback chain, seed data, schema, real repository CRUD all work. `VolumeArcSchemaMigrationPlan` bridges the legacy V1 training-plan shape through V2 to V3, with on-disk round-trip migration tests |
| Secure storage | Implemented | Keychain with fallback, device ID stability |
| Relay auth | Implemented | Actor-based session provider, token caching, expiration skew, real test coverage against production types |
| Telemetry | Implemented (PII scrubbing pending) | Fanout sink architecture. `SentryTelemetrySink` forwards events as breadcrumbs and captures `.error` severity as Sentry messages. `UserDefaultsTelemetrySink` and `OSLogTelemetrySink` persist/log for diagnostics. `beforeSend` scrubbing for user-identifiable data is not yet configured |
| Feature flags | Defined but unused (VOL-61) | `LocalFeatureFlagProvider` ships and is stored on `WorkoutDashboardModel`, but no code anywhere calls `.isEnabled()`. Flags gate nothing |
| Subscriptions | Implemented | StoreKit 2 store and `PaywallView` are wired, presented from `ProfileView`, and drive entitlement state. Terms/Privacy links open placeholder URLs (`https://volumearc.app/terms`, `/privacy`) via `LegalLinks` — marketing pages go live closer to launch (VOL-71). Guideline 3.1.2 auto-renewal disclosure present |
| Build pipeline | Partial | Ruby-generated Xcode project, CI on self-hosted M4, Fastlane, archive script, hard-failing `validate_release_config.sh` on Info.plist keys/URL schemes/BGTask IDs. Open: SwiftLint not installed on runner (silently warn-skipped), `Build & Test` not a required status check, `CI_TAG_BUILD=1` not set in deploy job so version-bump enforcement never fires |
| Testing | Implemented (80% VolumeArcCore coverage gate enforced — VOL-52) | ~290 unit + integration tests pass. XCUITest smoke suite runs on CI. `VolumeArcLaunchArguments` are live and wire into `VolumeArcLaunchBootstrapper`. Dashboard integration tests cover the create → log → complete chain against in-memory SwiftData. CI now blocks merges that drop `VolumeArcCore` line coverage below 80% via `scripts/check_coverage.sh`, which parses the xcresult bundle from `xcodebuild test -enableCodeCoverage YES`. See [`docs/TESTING.md`](TESTING.md#volumearccore-80-line-coverage-gate-vol-52) for the gate mechanics |
| App Store readiness | Blockers open | `aps-environment` entitlement hardcoded to `development` (Release builds will fail production signing), privacy manifest reason-coverage for HealthKit + microphone incomplete, Sentry crash reports lack PII scrubbing. Paywall legal links now wired to placeholder URLs via `LegalLinks` (VOL-71 resolved — marketing pages stand up closer to launch). Tracked in Linear Go-Live Readiness project |

## Targets

| Target | Type | Platform | Bundle ID |
|--------|------|----------|-----------|
| VolumeArcApp | iOS Application | iOS 26.0 | `com.mabryventures.VolumeArc` |
| VolumeArcWatch | watchOS Application | watchOS 26.4 | `com.mabryventures.VolumeArc.watchkitapp` |
| VolumeArcWidgets | Widget Extension | iOS 26.0 | `com.mabryventures.VolumeArc.widgets` |
| VolumeArcWatchWidgets | Widget Extension | watchOS 26.4 | `com.mabryventures.VolumeArc.watchwidgets` |
| VolumeArcAppTests | Unit Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.tests` |
| VolumeArcAppUITests | UI Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.uitests` |
| VolumeArcCore | Static Library | iOS 26.0 | -- (from `VolumeArcNative/`) |
| VolumeArcUI | Static Library | iOS 26.0 | -- (from `VolumeArcNative/`) |

**Dependency graph:** `VolumeArcUI -> VolumeArcCore`. All app targets depend on `VolumeArcCore`. The iOS app and tests also depend on `VolumeArcUI`. The watch and widget targets depend only on `VolumeArcCore`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full module breakdown and data flow.

## Key Components

**App entry point** (`VolumeArcApp.swift`): Wires all dependencies into `WorkoutDashboardModel` and installs `RootDashboardView`. Handles deep links, Watch Connectivity payloads, HealthKit background updates, widget snapshot changes, and Live Activity lifecycle.

**Persistence** (`VolumeArcPersistenceController.swift`): SwiftData with cascading fallback -- CloudSynced -> LocalFallback -> InMemoryFallback -> Unavailable. Seeds default `UserProfileRecord` and `TrainingPlanRecord` on first launch.

**AI coaching** (`VolumeArcAIRuntimeFactory.swift`): Three-tier provider chain with `AsyncThrowingStream` streaming, memory append via `CoachMemoryRepository`, and structured output parsing. Every provider routes its outbound prompt through `CoachPromptTemplate.render(...)` so the system prompt, per-intent envelope, structured context block, and template marker are identical across the cloud, on-device, and offline paths — a regression that bypasses the template drops the marker and trips `VolumeArcCoachPromptTemplateTests`:
1. `FoundationModelCoachProvider` (on-device, iOS 26.0+ only)
2. `OpenAIRelayCoachProvider` (cloud relay)
3. `LocalHeuristicAICoachProvider` (offline fallback)

**Voice coaching** (`VolumeArcCore/AI/VoiceCoach.swift`, `VolumeArcAIRuntimeFactory.swift`): `LiveVoiceCoachOrchestrator` backed by `OpenAIRelayVoiceTransport` (single-turn — delegates to the same relay-backed `AICoachProvider` chain used by the text coach) or `UnavailableVoiceTransport` when relay is unconfigured. The orchestrator exposes `speak(prompt:context:)` for question/response turns and lifecycle hooks (`start`, `interrupt`, `end`) which are no-ops for the single-turn transport. A future feature will introduce a real `OpenAIRealtimeWebRTCTransport` that maintains a persistent duplex audio session against the OpenAI Realtime API; the protocol shape supports both transports without rework.

**Cloud sync** (`VolumeArcCloudConfiguration.swift`): `CloudSyncCoordinator` drives `CloudKitSyncTransport` using zone `VolumeArcSyncZone` in container `iCloud.com.mabryventures.VolumeArc`. Push uses `CKModifyRecordsOperation`; pull uses `CKFetchRecordZoneChangesOperation` with cursor persistence in `FileSyncStateStore`. `DefaultSyncPayloadApplier` writes changes into SwiftData with conflict resolution. Falls back to `UnavailableCloudSyncTransport` if unconfigured.

**Relay auth** (`VolumeArcRelaySessionProvider.swift`): Actor that manages device-ID-based session tokens for the OpenAI relay. Tokens cached in Keychain with ISO8601 expiration and 60-second refresh skew.

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

`StoreKitSubscriptionStore` drives a full `PaywallView` (plans, features, restore, terms/privacy links). Entitlement gates cloud sync, voice coaching, and live activities through the feature flag provider.

## Configuration

### Environment / Info.plist Keys

| Key | Source | Purpose |
|-----|--------|---------|
| `VOLUMEARC_OPENAI_BASE_URL` | Env var or `VolumeArcOpenAIBaseURL` in Info.plist | OpenAI relay base URL for AI/voice coaching |
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

`MARKETING_VERSION` is read from the `VERSION` file at the repo root (e.g., `1.0.0`). `CURRENT_PROJECT_VERSION` (build number) is derived from `git rev-list --count HEAD` by default, or from the `BUILD_NUMBER` environment variable when set (e.g., by CI). The `DEVELOPMENT_TEAM` can be passed as an env var for signing builds.

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/generate_xcode_project.rb` | Generates `VolumeArcApple.xcodeproj` from scratch, configuring all targets, dependencies, and build settings |
| `scripts/build_all_targets.sh` | Debug build of all targets (iOS simulator + watchOS simulator) |
| `scripts/build_release_targets.sh` | Release build of all targets |
| `scripts/test_apple_targets.sh` | Runs both `VolumeArcAppTests` (unit + integration) and `VolumeArcAppUITests` (XCUITest smoke) on iPhone 17 simulator |
| `scripts/validate_release_config.sh` | Hard-fails on `ENABLE_TESTABILITY = YES` in Release, `DEBUG_INFORMATION_FORMAT` ≠ `dwarf-with-dsym`, missing entitlements, leaked demo symbols, missing privacy manifests, or unchanged `VERSION` on tag builds |
| `scripts/archive_for_distribution.sh` | Archives and exports a signed IPA for App Store / TestFlight. Requires `DEVELOPMENT_TEAM` env var |

All build scripts call `generate_xcode_project.rb` first, so the project is always fresh.

### CI / CD

GitHub Actions CI runs on a self-hosted M4 Mac Mini runner (`runs-on: self-hosted`). The workflow (`.github/workflows/ci.yml`) triggers on pushes to `main`, pull requests, and version tags (`v*`).

**CI pipeline:** Checkout → Generate Xcode project → Build all targets → Run unit + integration tests → Run XCUITest smoke suite → SwiftLint → Validate release config → Two-bot AI review gate (CodeRabbit Pro primary + Codex Code Review secondary) required to merge.

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
