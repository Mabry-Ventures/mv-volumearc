# VolumeArc Apple Platform

[![CI](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml/badge.svg)](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml)

AI-powered strength training coach for iOS and watchOS. Tracks workouts, provides real-time coaching via voice and text, syncs across devices with CloudKit, and surfaces training signals through widgets and Live Activities.

**Owner:** Mabry Ventures (`com.mabryventures.VolumeArc`)

## Implementation Status

> **Status: Production-ready with one feature scoped to a future release.** All major product surfaces are wired to real implementations. iPhone UI runs a full dashboard with fully-localized, accessible, Dynamic-Type-aware screens and hero transitions. AI coaching streams responses through a three-provider chain with on-device memory. CloudKit sync performs real record CRUD with cursor persistence. Watch app runs HealthKit workout sessions and bi-directional connectivity with offline queue replay. Widgets and Live Activities read real shared state. Subscriptions have a paywall and entitlement checks. 53 unit + integration tests pass and the XCUITest smoke suite runs in CI on every PR. The one explicitly-scoped-out feature is **live duplex audio** for voice coaching — the orchestrator and transport are functional for single-turn voice → text → speech queries via the same relay used by the text coach, but a persistent WebRTC-style streaming session against the OpenAI Realtime API is tracked as a future feature.

| System | Status | Notes |
|--------|--------|-------|
| iPhone UI | Implemented | Full tab bar (Today, Workouts, Coach, Signals, Profile), real screens, Liquid Glass design system, fully localized via `String(localized:comment:)`, VoiceOver labels on data displays, Dynamic Type, hero transitions, toast presenter, session summary, session detail, paywall, onboarding |
| AI coaching | Implemented | Three-provider chain with `AsyncThrowingStream` streaming, memory append via `CoachMemoryRepository`, structured output parsing, graceful fallback to `LocalHeuristicAICoachProvider` |
| Voice coaching | Implemented (single-turn) | `OpenAIRelayVoiceTransport` delegates to the same relay-backed `AICoachProvider` chain; `LiveVoiceCoachOrchestrator` exposes `speak(prompt:context:)` and lifecycle hooks. Live duplex audio (persistent WebRTC session against OpenAI Realtime) is **explicit future work** — single-turn coverage is sufficient for the in-gym "ask a question, hear a reply" loop |
| Cloud sync | Implemented | `CKModifyRecordsOperation` + `CKFetchRecordZoneChangesOperation` with cursor persistence, payload applier writes to SwiftData, conflict resolution, shared-state writes |
| Watch app | Implemented | HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder`, rest timer, decisions, accessibility, offline payload queue, real phone/watch sync via WCSession |
| Widgets | Implemented | `NextWorkoutWidget` + `WatchWidgets` extension read real shared state via `PlatformSurfaceDefaultsReader`, design-system-tokened, accessibility-labelled |
| Live Activities | Implemented | `ActiveWorkoutLiveActivity` with real updates from workout session state, Dynamic Island layouts |
| Notifications | Implemented | Scheduler wired into rest timer completion and training plan reminders, actionable categories (REST_TIMER, WORKOUT_REMINDER) |
| Persistence | Implemented | Four-tier fallback chain, seed data, schema, migration plan, migration tests, real repository CRUD |
| Secure storage | Implemented | Keychain with fallback, device ID stability |
| Relay auth | Implemented | Actor-based session provider, token caching, expiration skew, real test coverage against production types |
| Telemetry | Implemented | Fanout sink architecture. `SentryTelemetrySink` forwards events as breadcrumbs and captures `.error` severity as Sentry messages. `UserDefaultsTelemetrySink` and `OSLogTelemetrySink` persist/log for diagnostics |
| Feature flags | Implemented | `LocalFeatureFlagProvider` with UserDefaults, flags gate voiceCoaching, cloudSync, liveActivities, foundationModelCoach |
| Subscriptions | Implemented | StoreKit 2 with `@Published` entitlement state, full paywall UI, purchase + restore flow, entitlement checks |
| Build pipeline | Implemented | Ruby-generated Xcode project, CI on self-hosted M4, Fastlane, archive script, SwiftLint, hard-failing release validation |
| Testing | Implemented | 53 unit + integration tests against real production types (persistence, relay, migration, progression, readiness, dashboard integration, configuration). XCUITest smoke suite runs in CI on every PR. Dashboard integration tests cover the create → log → complete chain against in-memory SwiftData. Test coverage gate (VOL-52) is the one open item from the push-to-95 sprint |

## Architecture

This repo contains the full VolumeArc Apple platform. Core business logic and UI components live in `VolumeArcNative/` (frameworks `VolumeArcCore` and `VolumeArcUI`), compiled as static libraries and linked into each target by `scripts/generate_xcode_project.rb`.

### Targets

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

**Dependency graph:** `VolumeArcUI -> VolumeArcCore`. All app targets depend on `VolumeArcCore`. The iOS app and tests also depend on `VolumeArcUI`. The watch and widget targets depend only on `VolumeArcCore`.

### Key Components

**App entry point** (`VolumeArcApp.swift`): Wires all dependencies into `WorkoutDashboardModel` and installs `RootDashboardView`. Handles deep links, Watch Connectivity payloads, HealthKit background updates, widget snapshot changes, and Live Activity lifecycle.

**Persistence** (`VolumeArcPersistenceController.swift`): SwiftData with cascading fallback -- CloudSynced -> LocalFallback -> InMemoryFallback -> Unavailable. Seeds default `UserProfileRecord` and `TrainingPlanRecord` on first launch.

**AI coaching** (`VolumeArcAIRuntimeFactory.swift`): Three-tier provider chain with `AsyncThrowingStream` streaming, memory append via `CoachMemoryRepository`, and structured output parsing:
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

### Data Models (SwiftData)

Schema: `VolumeArcSchemaV1` with `VolumeArcSchemaMigrationPlan` (migration-tested).

- `UserProfileRecord` -- coaching style, privacy mode, advancement level, equipment, rep ranges, time budget, training days, via `SwiftDataUserProfileRepository`
- `WorkoutRecord` -- via `SwiftDataWorkoutRepository` (create, append set with aggregate update, complete, fetch recent, history projection)
- `TrainingPlanRecord` -- weekly schedule, via `SwiftDataTrainingPlanRepository` (upsert, fetch)
- `CoachMemoryRecord` -- AI coach context, via `SwiftDataCoachMemoryRepository` (append, fetch recent)

### Telemetry

Fanout sink: `InMemoryTelemetrySink` (bootstrap) + `UserDefaultsTelemetrySink` (persistent, NSLock-guarded) + `OSLogTelemetrySink` + `SentryTelemetrySink` (when configured). Startup signals surface degraded persistence, missing AI relay, missing CloudKit config, or missing Sentry DSN. `SentryTelemetrySink` forwards events as breadcrumbs and captures `.error` severity as Sentry messages.

### Notifications

**Notification scheduler** (`VolumeArcNotificationScheduler.swift`): Schedules local notifications for rest timer expiration and workout reminders from the training plan. Registers actionable notification categories (`REST_TIMER` with Dismiss, `WORKOUT_REMINDER` with Start Workout / Dismiss). Called from rest timer completion handlers and the training plan scheduler.

### Feature Flags

`FeatureFlagProvider` protocol in `VolumeArcCore` with `LocalFeatureFlagProvider` (UserDefaults-backed). Flags: `voiceCoaching`, `cloudSync`, `liveActivities`, `foundationModelCoach`. Overridable per-flag for development. Wired into feature gates on the paywall, runtime factory, and live activity controller.

### Network Reachability

`NetworkReachabilityMonitor` in `VolumeArcCore` wraps `NWPathMonitor` for connectivity detection. Exposes `isReachable`, `isCellular`, and `isConstrained` properties with a `start(onChange:)` callback. Used by `WatchConnectivityCoordinator` offline queue replay and `CloudSyncCoordinator` back-off logic.

### Subscriptions

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

**CI pipeline:** Checkout → Generate Xcode project → Build all targets → Run unit + integration tests → Run XCUITest smoke suite → SwiftLint → Validate release config → Two-bot AI review gate (Gemini + Codex) required to merge.

**TestFlight deploy:** On version tags (`v*`), a second job runs `fastlane ios beta` to archive, sign, and upload to TestFlight. Requires `DEVELOPMENT_TEAM` and `APP_STORE_CONNECT_API_KEY_PATH` secrets.

**Fastlane:** `Gemfile` + `fastlane/Fastfile` with three lanes: `test` (run tests with coverage), `beta` (build + upload to TestFlight), `release` (submit to App Store review).

### Privacy Manifests

Each target includes a `PrivacyInfo.xcprivacy` declaring required reason API usage (UserDefaults, FileTimestamp). These are added to targets by `generate_xcode_project.rb` and validated by `validate_release_config.sh`.

### Localization

Every user-facing string in `VolumeArcUI/Screens/` and `Watch/` goes through `String(localized:comment:)` with a translator comment. Currently English-only, but the full catalog is extractable to a String Catalog (`.xcstrings`) without code changes. Price strings are composed via localized format patterns to support CLDR plural forms.

### Accessibility

- `VA.Typography` tokens use `Font.system(TextStyle, design:, weight:)` so every text style scales with Dynamic Type from `.xSmall` through `.accessibility5`.
- `VAButton`, `VACoardBubble`, `VACard`, and metric displays expose combined accessibility elements with VoiceOver labels, hints, and the `.isButton` trait where interactive.
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
- **Unavailable stubs:** Each integration has an `Unavailable*` fallback (e.g., `UnavailableHealthStore`, `UnavailableCloudSyncTransport`, `UnavailableRealtimeVoiceTransport`) so the app always launches.
- **Actor isolation:** Network-bound providers (`VolumeArcRelaySessionProvider`, `VolumeArcVoicePermissionStore`) use Swift actors for thread safety.
- **No Package.swift at root:** The Xcode project is Ruby-generated, not SPM-based. `VolumeArcNative/` contains the Swift package structure for shared frameworks.
- **Localized strings:** All user-facing strings use `String(localized:comment:)` for future translation support.
- **Accessibility:** All interactive and data-display elements in Watch and Widget views have VoiceOver labels, hints, and values.
- **Codable payloads:** Watch-to-phone payloads use `Codable` structs encoded via `SyncPayloadCodec` rather than ad-hoc string formatting.
