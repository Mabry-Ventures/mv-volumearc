# VolumeArc Architecture

## Overview

VolumeArc is a multi-target Apple platform app composed of:

- **iOS host app** (`App/`) — thin layer that bootstraps dependencies, wires notifications, and installs the SwiftUI root.
- **watchOS companion** (`Watch/`) — workout tracking on the wrist, offline queue, coach cue requests.
- **Widget extension** (`Widgets/`) — home screen and Lock Screen widgets, Live Activity for active workouts.
- **Shared Swift package** (`VolumeArcNative/`) — `VolumeArcCore` and `VolumeArcUI` libraries containing all business logic and design system components.

## Dependency graph

```
App/         ──┐
               ├── VolumeArcUI   ──┐
Watch/       ──┤                   ├── VolumeArcCore
Widgets/     ──┘                   │
                                   │
Tests/       ─────────────────────┘
```

All targets depend on `VolumeArcCore`. Only the iOS app and test target depend on `VolumeArcUI` (Watch and Widgets have their own lightweight views).

## VolumeArcCore modules

```
VolumeArcCore/
├── AI/                      # AICoachProvider, voice transport, OpenAI relay
├── CloudSync/               # CloudKitSyncTransport, CloudSyncCoordinator, FileSyncStateStore
├── FeatureFlags/            # FeatureFlagProvider protocol, LocalFeatureFlagProvider
├── Health/                  # HealthStore protocol, NetworkReachabilityMonitor
├── Navigation/              # DashboardNavigationModel, WorkoutDashboardModel, VolumeArcDeepLink
├── Notifications/           # NotificationStore, AccountSessionStore
├── Persistence/             # SwiftData @Models, repositories, VolumeArcSchemaV1
├── PlatformSurface/         # Widget/Live Activity shared state types
├── Subscriptions/           # StoreKitSubscriptionStore
├── Telemetry/               # TelemetrySink fanout, TelemetryEvent, OperationalSignal
├── Voice/                   # VoicePermissionStore, VoicePermissionStatus
├── Watch/                   # WatchConnectivityCoordinator, payload types
└── Workout/                 # ProgressionEngine, ReadinessModel, ExerciseCatalog
```

## VolumeArcUI modules

```
VolumeArcUI/
├── DesignSystem/            # Tokens (colors, typography, spacing), Components (VACard, VAButton, etc.)
├── Haptics/                 # VAHaptics — centralized tactile feedback
├── Motion/                  # VAAnimation — motion tokens and transitions
├── Screens/                 # TodayView, WorkoutsView, CoachView, SignalsView, ProfileView, OnboardingView
└── RootDashboardView        # Top-level tab container
```

## Data flow

### Launch
1. `VolumeArcApp.init()` bootstraps Sentry, relay config, telemetry sink, persistence.
2. Repositories are created from `ModelContainer`.
3. `WorkoutDashboardModel` is constructed with all dependencies.
4. `.task { await model.refresh() }` loads user profile, readiness, autopilot state.

### User action → state change → UI update
1. User taps **Log Set** → `VAHaptics.setLogged()` fires.
2. `WorkoutDashboardModel.logRecommendedSet()` calls `SwiftDataWorkoutRepository.appendSet()`.
3. Repository writes to SwiftData, updates aggregates (volume load, RPE, set count).
4. Model calls `refresh()` which re-reads everything and updates `@Published` state.
5. SwiftUI views observing the model re-render automatically.

### Watch → Phone payload
1. Watch calls `coordinator.send(payload)` over WCSession.
2. iOS app receives via `WatchConnectivityNotifications.payloadDidArrive`.
3. `VolumeArcApp` forwards to `WorkoutDashboardModel.handleWatchPayload()`.
4. Dashboard refreshes from repositories.

### Sync
1. `CloudSyncCoordinator` runs push/pull against `CloudKitSyncTransport`.
2. Remote changes flow through `DefaultSyncPayloadApplier` into local repositories.
3. Cursor persisted to `FileSyncStateStore` so next sync resumes where it left off.

## Key design principles

### Protocol-oriented dependencies
Every integration point (AI provider, health store, sync transport, telemetry sink) is a protocol with at least two implementations: a real one and an `Unavailable*` stub. The app always launches, even if every integration is degraded.

### Factory pattern for platform-specific runtime
`VolumeArcApp.makeHealthStore()`, `makeVoicePermissionStore()`, `makeSyncTransport()` etc. choose between real and stub implementations based on `#if canImport()` checks and runtime configuration.

### Actor isolation for mutable shared state
Network-bound types (`VolumeArcRelaySessionProvider`, `VolumeArcVoicePermissionStore`) use Swift actors. The `WorkoutDashboardModel` is `@MainActor` because all SwiftUI observation happens on the main thread.

### Cascading persistence fallback
`VolumeArcPersistenceController` tries: CloudKit → local file → in-memory → unavailable. Each tier records its failure metadata for telemetry.

### Design tokens, not hardcoded styling
All colors, typography, spacing, and radii come from `VA.Colors`, `VA.Typography`, `VA.Space`, `VA.Radius`. No view should use literal values for visual properties.
