# VolumeArc Apple Platform

[![CI](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml/badge.svg)](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml)

AI-powered strength training coach for iOS and watchOS. Tracks workouts, provides real-time coaching via voice and text, syncs across devices with CloudKit, and surfaces training signals through widgets and Live Activities.

**Owner:** Mabry Ventures (`com.mabryventures.VolumeArc`)

## Implementation Status

> **Status: Pre-production.** The infrastructure layer (build pipeline, CI, secure storage, persistence bootstrap, relay auth, privacy manifests, accessibility, localization) is solid. The product layer (iPhone UI, AI coaching flows, sync, watch connectivity, widgets, Live Activities) is scaffolding -- protocols and types compile and wire correctly, but concrete implementations are stubs returning canned data or no-ops. See the status table below.

| System | Status | What exists | What's missing |
|--------|--------|-------------|----------------|
| iPhone UI | Scaffold | `RootDashboardView` placeholder, deep link routing, intent wiring | Real dashboard, navigation, onboarding, workout, coach, signals, settings screens |
| AI coaching | Scaffold | Provider protocol chain, relay session auth, factory selection | Real prompt templates, structured outputs, streaming, evaluation, recovery UX |
| Voice coaching | Scaffold | Transport protocol, orchestrator, permission store | Actual voice session implementation, duplex audio, UX flow |
| Cloud sync | Scaffold | Coordinator, transport protocol, state store, payload codec | Real CloudKit record operations, conflict resolution, shared-state writes |
| Watch app | Partial | UI with rest timer, decisions, coach cue, accessibility, localized strings | HealthKit workout sessions, real progression inputs, real phone/watch sync |
| Widgets | Scaffold | Widget views, timeline provider, accessibility labels | Shared-state writes from app (`PlatformSurfaceDefaultsReader` returns nil) |
| Live Activities | Scaffold | Activity attributes, controller lifecycle | Real state updates from workout sessions |
| Notifications | Scaffold | Scheduler with categories and actions | Wiring into rest timer and training plan |
| Persistence | Implemented | Four-tier fallback chain, seed data, schema, migration plan | -- |
| Secure storage | Implemented | Keychain with fallback, device ID stability | -- |
| Relay auth | Implemented | Actor-based session provider, token caching, expiration skew | -- |
| Telemetry | Partial | Fanout architecture, sink protocol, startup signals | Sentry sink wired but sinks themselves are no-op (don't persist/send) |
| Feature flags | Scaffold | Protocol, UserDefaults provider, flag definitions | Not wired into any feature gates |
| Subscriptions | Scaffold | Product IDs, StoreKit store type | No paywall UI, no purchase flow, no entitlement checks |
| Build pipeline | Implemented | Generated Xcode project, CI on self-hosted M4, Fastlane, archive script | SwiftLint not installed on runner |
| Testing | Partial | 30 tests, mocks, fixtures, persistence/relay/migration tests | Tests validate stubs not real logic; no UI tests, no journey tests, 0% end-to-end coverage |

## Architecture

This repo contains the full VolumeArc Apple platform. Core business logic and UI components live in `VolumeArcNative/` (frameworks `VolumeArcCore` and `VolumeArcUI`), compiled as static libraries and linked into each target by `scripts/generate_xcode_project.rb`.

### Targets

| Target | Type | Platform | Bundle ID |
|--------|------|----------|-----------|
| VolumeArcApp | iOS Application | iOS 26.0 | `com.mabryventures.VolumeArc` |
| VolumeArcWatch | watchOS Application | watchOS 26.4 | `com.mabryventures.VolumeArc.watchkitapp` |
| VolumeArcWidgets | Widget Extension | iOS 26.0 | `com.mabryventures.VolumeArc.widgets` |
| VolumeArcAppTests | Unit Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.tests` |
| VolumeArcCore | Static Library | iOS 26.0 | -- (from `VolumeArcNative/`) |
| VolumeArcUI | Static Library | iOS 26.0 | -- (from `VolumeArcNative/`) |

**Dependency graph:** `VolumeArcUI -> VolumeArcCore`. All app targets depend on `VolumeArcCore`. The iOS app and tests also depend on `VolumeArcUI`. The watch and widget targets depend only on `VolumeArcCore`.

### Key Components

**App entry point** (`VolumeArcApp.swift`): Wires all dependencies into `WorkoutDashboardModel` and installs `RootDashboardView`. Handles deep links, Watch Connectivity payloads, HealthKit background updates, widget snapshot changes, and Live Activity lifecycle.

**Persistence** (`VolumeArcPersistenceController.swift`): SwiftData with cascading fallback -- CloudSynced -> LocalFallback -> InMemoryFallback -> Unavailable. Seeds default `UserProfileRecord` and `TrainingPlanRecord` on first launch.

**AI coaching** (`VolumeArcAIRuntimeFactory.swift`): Three-tier provider chain:
1. `FoundationModelCoachProvider` (on-device, iOS 26.0+ only)
2. `OpenAIRelayCoachProvider` (cloud relay)
3. `LocalHeuristicAICoachProvider` (offline fallback)

> **Note:** All three providers exist as types but return canned/naive responses. Real prompt engineering, structured outputs, streaming, and evaluation are not yet implemented.

**Voice coaching** (`VolumeArcAIRuntimeFactory.swift`): `LiveVoiceCoachOrchestrator` backed by `OpenAIRealtimeVoiceTransport` or `UnavailableRealtimeVoiceTransport` when relay is unconfigured.

> **Note:** `OpenAIRealtimeVoiceTransport` methods are empty stubs. No actual voice session implementation exists.

**Cloud sync** (`VolumeArcCloudConfiguration.swift`): `CloudSyncCoordinator` with `CloudKitSyncTransport` using zone `VolumeArcSyncZone` in container `iCloud.com.mabryventures.VolumeArc`. Falls back to `UnavailableCloudSyncTransport` if unconfigured.

> **Note:** `CloudSyncCoordinator` init stores parameters but all operations are no-ops. No actual CloudKit record operations are implemented.

**Relay auth** (`VolumeArcRelaySessionProvider.swift`): Actor that manages device-ID-based session tokens for the OpenAI relay. Tokens cached in Keychain with ISO8601 expiration and 60-second refresh skew.

**Secure storage** (`VolumeArcSecureStore.swift`): Keychain wrapper with `UserDefaults` fallback in Debug/Simulator builds.

**Watch app** (`WatchWorkoutView.swift`): `WatchWorkoutModel` manages workout sessions, rest timers (90s default), coach cue requests, and set decisions (increase/hold/decrease). Communicates with iPhone via `WatchConnectivityCoordinator` with offline payload queuing.

> **Note:** Watch UI is the most developed surface but is driven by hardcoded defaults from `ProgressionEngine` (always returns Back Squat 225lb 5-8 reps). `WatchConnectivityCoordinator.send()` is a no-op. HealthKit workout sessions are not integrated.

**Widgets** (`VolumeArcWidgets.swift`): `NextWorkoutWidget` (systemSmall, systemMedium) shows readiness, next session, and lift forecast. `ActiveWorkoutLiveActivity` shows exercise, target, and rest timer on lock screen and Dynamic Island.

> **Note:** `PlatformSurfaceDefaultsReader.loadWidgetSnapshot()` always returns nil. Widgets fall back to canned empty snapshots. No shared-state writes from the app exist.

**App Intents** (`VolumeArcIntents.swift`): Six Siri Shortcuts -- StartNextWorkout, AskCoach, OpenSignals, StartWorkoutSession, LogRecommendedSet, SyncVolumeArc. All open the app via `VolumeArcDeepLink`.

> **Note:** Deep links route correctly but destinations in `RootDashboardView` are not rendered. `DashboardNavigationModel.selectedTab` is updated but never consumed by the UI. Dashboard action methods (`startWorkoutSession`, `logRecommendedSet`, `syncNow`) are empty.

### Data Models (SwiftData)

Schema: `VolumeArcSchemaV1` with `VolumeArcSchemaMigrationPlan`

- `UserProfileRecord` -- coaching style, privacy mode, advancement level, equipment, rep ranges, time budget, training days
- `WorkoutRecord` -- via `SwiftDataWorkoutRepository`
- `TrainingPlanRecord` -- weekly schedule, via `SwiftDataTrainingPlanRepository`
- `CoachMemoryRecord` -- AI coach context, via `SwiftDataCoachMemoryRepository`

> **Note:** SwiftData models and schema are defined. Repositories exist as types wrapping `ModelContainer` but have no query/write methods beyond what `VolumeArcPersistenceController.seedIfNeeded()` uses.

### Telemetry

Fanout sink: `InMemoryTelemetrySink` (bootstrap) + `UserDefaultsTelemetrySink` (persistent) + `OSLogTelemetrySink` + `SentryTelemetrySink` (when configured). Startup signals surface degraded persistence, missing AI relay, missing CloudKit config, or missing Sentry DSN.

> **Note:** `UserDefaultsTelemetrySink` and `InMemoryTelemetrySink` accept events but don't persist or surface them. `OSLogTelemetrySink` is the only sink that actually logs. Sentry is wired at the app level but the SDK dependency requires resolution at build time.

### Notifications

**Notification scheduler** (`VolumeArcNotificationScheduler.swift`): Schedules local notifications for rest timer expiration and workout reminders from the training plan. Registers actionable notification categories (`REST_TIMER` with Dismiss, `WORKOUT_REMINDER` with Start Workout / Dismiss).

> **Note:** Scheduler is implemented but not called from anywhere in the app. No code invokes `scheduleRestTimerNotification` or `scheduleWorkoutReminder`.

### Feature Flags

`FeatureFlagProvider` protocol in `VolumeArcCore` with `LocalFeatureFlagProvider` (UserDefaults-backed). Flags: `voiceCoaching`, `cloudSync`, `liveActivities`, `foundationModelCoach`. Overridable per-flag for development.

> **Note:** Flag definitions exist but no code checks them. Features are not gated behind flags.

### Network Reachability

`NetworkReachabilityMonitor` in `VolumeArcCore` wraps `NWPathMonitor` for connectivity detection. Exposes `isReachable`, `isCellular`, and `isConstrained` properties with a `start(onChange:)` callback for path updates.

> **Note:** Monitor exists but is not instantiated or used anywhere in the app.

### Subscriptions

StoreKit with two products:
- `com.mabryventures.VolumeArc.premium.monthly`
- `com.mabryventures.VolumeArc.premium.yearly`

> **Note:** Product IDs are defined and `StoreKitSubscriptionStore` is initialized in `VolumeArcApp`. No paywall UI, purchase flow, or entitlement checks exist.

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
| `scripts/test_apple_targets.sh` | Runs `VolumeArcAppTests` on iPhone 17 simulator |
| `scripts/validate_release_config.sh` | Validates entitlements exist, no demo symbols leak, privacy manifests present, and all required build settings are present |
| `scripts/archive_for_distribution.sh` | Archives and exports a signed IPA for App Store / TestFlight. Requires `DEVELOPMENT_TEAM` env var |

All build scripts call `generate_xcode_project.rb` first, so the project is always fresh.

### CI / CD

GitHub Actions CI runs on a self-hosted M4 Mac Mini runner (`runs-on: self-hosted`). The workflow (`.github/workflows/ci.yml`) triggers on pushes to `main`, pull requests, and version tags (`v*`).

**CI pipeline:** Checkout → Generate Xcode project → Build all targets → Run tests → SwiftLint → Validate release config.

**TestFlight deploy:** On version tags (`v*`), a second job runs `fastlane ios beta` to archive, sign, and upload to TestFlight. Requires `DEVELOPMENT_TEAM` and `APP_STORE_CONNECT_API_KEY_PATH` secrets.

**Fastlane:** `Gemfile` + `fastlane/Fastfile` with three lanes: `test` (run tests with coverage), `beta` (build + upload to TestFlight), `release` (submit to App Store review).

### Privacy Manifests

Each target includes a `PrivacyInfo.xcprivacy` declaring required reason API usage (UserDefaults, FileTimestamp). These are added to targets by `generate_xcode_project.rb` and validated by `validate_release_config.sh`.

### Localization

User-facing strings use `String(localized:comment:)` for localization readiness. Currently English-only, but all strings are extractable to a String Catalog for future translation without code changes.

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
