# VolumeArc Apple Platform

[![CI](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml/badge.svg)](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml)

AI-powered strength training coach for iOS and watchOS. Tracks workouts, provides real-time coaching via voice and text, syncs across devices with CloudKit, and surfaces training signals through widgets and Live Activities.

**Owner:** Mabry Ventures (`com.mabryventures.VolumeArc`)

## Architecture

This repo contains the Apple-platform host app. Core business logic and UI components live in a sibling package at `../VolumeArcNative` (frameworks `VolumeArcCore` and `VolumeArcUI`), compiled as static libraries and linked into each target by `scripts/generate_xcode_project.rb`.

### Targets

| Target | Type | Platform | Bundle ID |
|--------|------|----------|-----------|
| VolumeArcApp | iOS Application | iOS 26.0 | `com.mabryventures.VolumeArc` |
| VolumeArcWatch | watchOS Application | watchOS 26.4 | `com.mabryventures.VolumeArc.watchkitapp` |
| VolumeArcWidgets | Widget Extension | iOS 26.0 | `com.mabryventures.VolumeArc.widgets` |
| VolumeArcAppTests | Unit Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.tests` |
| VolumeArcCore | Static Library | iOS 26.0 | -- (from `../VolumeArcNative`) |
| VolumeArcUI | Static Library | iOS 26.0 | -- (from `../VolumeArcNative`) |

**Dependency graph:** `VolumeArcUI -> VolumeArcCore`. All app targets depend on `VolumeArcCore`. The iOS app and tests also depend on `VolumeArcUI`. The watch and widget targets depend only on `VolumeArcCore`.

### Key Components

**App entry point** (`VolumeArcApp.swift`): Wires all dependencies into `WorkoutDashboardModel` and installs `RootDashboardView`. Handles deep links, Watch Connectivity payloads, HealthKit background updates, widget snapshot changes, and Live Activity lifecycle.

**Persistence** (`VolumeArcPersistenceController.swift`): SwiftData with cascading fallback -- CloudSynced -> LocalFallback -> InMemoryFallback -> Unavailable. Seeds default `UserProfileRecord` and `TrainingPlanRecord` on first launch.

**AI coaching** (`VolumeArcAIRuntimeFactory.swift`): Three-tier provider chain:
1. `FoundationModelCoachProvider` (on-device, iOS 26.0+ only)
2. `OpenAIRelayCoachProvider` (cloud relay)
3. `LocalHeuristicAICoachProvider` (offline fallback)

**Voice coaching** (`VolumeArcAIRuntimeFactory.swift`): `LiveVoiceCoachOrchestrator` backed by `OpenAIRealtimeVoiceTransport` or `UnavailableRealtimeVoiceTransport` when relay is unconfigured.

**Cloud sync** (`VolumeArcCloudConfiguration.swift`): `CloudSyncCoordinator` with `CloudKitSyncTransport` using zone `VolumeArcSyncZone` in container `iCloud.com.mabryventures.VolumeArc`. Falls back to `UnavailableCloudSyncTransport` if unconfigured.

**Relay auth** (`VolumeArcRelaySessionProvider.swift`): Actor that manages device-ID-based session tokens for the OpenAI relay. Tokens cached in Keychain with ISO8601 expiration and 60-second refresh skew.

**Secure storage** (`VolumeArcSecureStore.swift`): Keychain wrapper with `UserDefaults` fallback in Debug/Simulator builds.

**Watch app** (`WatchWorkoutView.swift`): `WatchWorkoutModel` manages workout sessions, rest timers (90s default), coach cue requests, and set decisions (increase/hold/decrease). Communicates with iPhone via `WatchConnectivityCoordinator` with offline payload queuing.

**Widgets** (`VolumeArcWidgets.swift`): `NextWorkoutWidget` (systemSmall, systemMedium) shows readiness, next session, and lift forecast. `ActiveWorkoutLiveActivity` shows exercise, target, and rest timer on lock screen and Dynamic Island.

**App Intents** (`VolumeArcIntents.swift`): Six Siri Shortcuts -- StartNextWorkout, AskCoach, OpenSignals, StartWorkoutSession, LogRecommendedSet, SyncVolumeArc. All open the app via `VolumeArcDeepLink`.

### Data Models (SwiftData)

Schema: `VolumeArcSchemaV1` with `VolumeArcSchemaMigrationPlan`

- `UserProfileRecord` -- coaching style, privacy mode, advancement level, equipment, rep ranges, time budget, training days
- `WorkoutRecord` -- via `SwiftDataWorkoutRepository`
- `TrainingPlanRecord` -- weekly schedule, via `SwiftDataTrainingPlanRepository`
- `CoachMemoryRecord` -- AI coach context, via `SwiftDataCoachMemoryRepository`

### Telemetry

Fanout sink: `InMemoryTelemetrySink` (bootstrap) + `UserDefaultsTelemetrySink` (persistent) + `OSLogTelemetrySink`. Startup signals surface degraded persistence, missing AI relay, or missing CloudKit config.

### Subscriptions

StoreKit with two products:
- `com.mabryventures.VolumeArc.premium.monthly`
- `com.mabryventures.VolumeArc.premium.yearly`

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

**iOS App:** HealthKit, CloudKit, iCloud Containers (`iCloud.com.mabryventures.VolumeArc`), App Groups (`group.com.mabryventures.volumearc`)

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
- **No Package.swift in this repo:** The Xcode project is Ruby-generated, not SPM-based. The sibling `VolumeArcNative` package provides the Swift package structure.
