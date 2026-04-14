# Feature Status

> **⚠ Pre-production after post-95/95 audit (2026-04-14).** Several rows below were marked ✅ before an independent audit found broken end-to-end wiring. Affected rows are now downgraded to 🚧 with a link to the active VOL ticket. See [`PLATFORM.md`](PLATFORM.md#implementation-status) for the launch-blocker list.

This is the granular per-feature checklist. For high-level system status, see [`PLATFORM.md`](PLATFORM.md). Update this file with every PR that changes feature completeness.

## Legend
- ✅ **Shipped** — feature is complete, tested, and production-ready
- 🚧 **In progress** — feature exists and partially works, but has known gaps
- 🏗️ **Scaffold** — types and wiring exist but concrete implementation is stub
- 📋 **Planned** — not yet started

## Platform surfaces

| Feature | Status | Notes |
|---------|--------|-------|
| iOS navigation shell (5 tabs) | ✅ | Full tab bar with Today, Workouts, Coach, Signals, and Profile, routed by `DashboardNavigationModel`. |
| Today dashboard | ✅ | Readiness hero, next workout hero card, quick actions, recent sessions, and zoom hero transitions. |
| Workouts tab | ✅ | Active session flow, rest timer, log set, session summary, and workout detail surfaces are live. |
| Coach chat | ✅ | Real text coach, streaming response UX, memory-backed prompts, and relay/local/on-device fallback chain. |
| Signals / readiness | ✅ | Readiness breakdown, volume chart, and frequency heatmap ship in the Signals surface. |
| Profile / settings | ✅ | Profile header, training settings, edit profile flow, diagnostics entry point, and subscription gating surfaces are live. |
| Onboarding flow | 🚧 [VOL-57](https://linear.app/mabry-ventures/issue/VOL-57) | View is fully built but `RootDashboardView` never presents it. First-launch users skip onboarding entirely. |
| watchOS workout UI | ✅ | Real HealthKit workout session, rest timer, coach cues, action decisions, accessibility labels, and offline replay. |
| Widgets (systemSmall/systemMedium/watchOS) | ✅ | `NextWorkoutWidget` and watch widgets read real shared snapshots via `PlatformSurfaceDefaultsReader`. |
| Live Activities | ✅ | `ActiveWorkoutLiveActivity` publishes real session state with lock screen and Dynamic Island layouts. |

## AI & coaching

| Feature | Status | Notes |
|---------|--------|-------|
| AI provider chain (Foundation Models → Relay → Local) | ✅ | Runtime factory selects the three-provider chain with graceful fallback. |
| `OpenAIRelayCoachProvider` | ✅ | Real HTTP relay-backed coach provider in production use. |
| `LocalHeuristicAICoachProvider` | ✅ | Real rule-based offline fallback grounded in readiness and recent-session context. |
| `FoundationModelCoachProvider` | ✅ | On-device provider is wired and falls back cleanly when unavailable or failing. |
| Voice transport | ✅ | `OpenAIRelayVoiceTransport` is live for single-turn voice → text → spoken response. Live duplex/WebRTC audio remains future work. |
| Coach memory | ✅ | `CoachMemoryRepository` persists recent context and is appended during coaching turns. |
| Streaming response UX | 🚧 [VOL-66](https://linear.app/mabry-ventures/issue/VOL-66) | `AsyncThrowingStream` plumbing exists, but the default implementation is synthetic word-chunking (call non-streaming endpoint, sleep 30ms between words). No real progressive streaming from the relay. |
| Evaluation harness | 📋 | Prompt-quality regression tooling is still planned. |
| Privacy mode enforcement | 📋 | Privacy mode is modeled and surfaced in UI, but strict-mode prompt enforcement is not yet consistently applied in the dashboard coach path. |

## Data & progression

| Feature | Status | Notes |
|---------|--------|-------|
| SwiftData schema V1 | ✅ | `UserProfileRecord`, `WorkoutRecord`, `TrainingPlanRecord`, and `CoachMemoryRecord` ship with migration coverage. |
| Persistence fallback chain | ✅ | Cloud-synced → local fallback → in-memory fallback → unavailable, with telemetry and bootstrap metadata. |
| `SwiftDataWorkoutRepository` | ✅ | Create, append set, complete, delete, recent/history projection, and aggregate updates are real. |
| `SwiftDataUserProfileRepository` | ✅ | Upsert, load, onboarding completion, and athlete profile projection are live. |
| `SwiftDataTrainingPlanRepository` | ✅ | Upsert weekly plan and query next workout are live. |
| `SwiftDataCoachMemoryRepository` | ✅ | Append, fetch recent, and pruning behavior ship. |
| `ProgressionEngine` | ✅ | Progression, substitution, and recommendation logic are exercised by production code and tests. |
| `ReadinessModel` | ✅ | Five-factor readiness scoring is live in the dashboard and coach context. |
| Exercise catalog | ✅ | Shipping catalog supports the current training flows; future expansion is additive, not a blocker. |

## Sync & connectivity

| Feature | Status | Notes |
|---------|--------|-------|
| `CloudSyncCoordinator` | 🚧 [VOL-55](https://linear.app/mabry-ventures/issue/VOL-55), [VOL-67](https://linear.app/mabry-ventures/issue/VOL-67) | Push/pull cycle, cursor persistence, and apply path exist in code. CloudKit container ID is missing from the built `Info.plist`, so the coordinator falls back to unconfigured at runtime. |
| `CloudKitSyncTransport` | 🚧 [VOL-55](https://linear.app/mabry-ventures/issue/VOL-55) | `CKModifyRecordsOperation` and `CKFetchRecordZoneChangesOperation` calls exist; runtime container is unconfigured (see above). |
| `FileSyncStateStore` | ✅ | Real disk-backed sync cursor persistence across launches. |
| `DefaultSyncPayloadApplier` | 🚧 [VOL-67](https://linear.app/mabry-ventures/issue/VOL-67) | Applies a partial subset of workout state on the inbound side. Sets, RPE, and aggregates are not fully round-tripped. |
| Outbound sync record generation | 🚧 [VOL-67](https://linear.app/mabry-ventures/issue/VOL-67) | Local writes through the SwiftData repositories do not produce outbound `CloudSyncRecord`s — sync is one-way (pull only). |
| `WatchConnectivityCoordinator` | ✅ | Real `WCSession` transport plus offline pending-payload queue and replay behavior. |
| `NetworkReachabilityMonitor` | ✅ | Real `NWPathMonitor` wrapper and app startup wiring for sync/connectivity decisions. |
| Background sync (`BGAppRefreshTask` + `BGProcessingTask`) | 🚧 [VOL-56](https://linear.app/mabry-ventures/issue/VOL-56) | Task registration code exists. The built `Info.plist` is missing `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes`, so iOS rejects the registrations at runtime. |

## Observability

| Feature | Status | Notes |
|---------|--------|-------|
| Telemetry fanout | ✅ | Fanout sink combines in-memory, UserDefaults, OSLog, and Sentry sinks. |
| `OSLogTelemetrySink` | ✅ | Unified logging integration is live. |
| `UserDefaultsTelemetrySink` | ✅ | Rolling persistent event buffer ships for diagnostics. |
| `InMemoryTelemetrySink` | ✅ | Bootstrap/runtime in-memory sink ships. |
| `SentryTelemetrySink` | ✅ | Breadcrumb forwarding and error message capture are live. |
| Startup signals | ✅ | Missing/degraded persistence, relay, CloudKit, and Sentry conditions surface operational signals. |

## Infrastructure

| Feature | Status | Notes |
|---------|--------|-------|
| Generated Xcode project | ✅ | `scripts/generate_xcode_project.rb` remains the only source of truth for the Xcode project. |
| CI pipeline (self-hosted M4) | ✅ | Build, unit/integration tests, UI smoke tests, lint, and validation run on PRs and main pushes. |
| Fastlane (test/beta/release) | ✅ | TestFlight automation and App Store submission lanes ship. |
| Archive script | ✅ | `archive_for_distribution.sh` produces signed distribution archives. |
| Privacy manifests | ✅ | Required manifests ship for all relevant targets and are validated. |
| SwiftLint | ✅ | Installed on the runner and enforced in CI. |
| Versioning from git | ✅ | `VERSION` + git-derived build number flow ships. |
| Localization (`String(localized:)`) | ✅ | Every user-facing string is localized with translator comments. No `.xcstrings` catalog file is generated yet, but the codebase is fully extractable. |
| Accessibility labels | ✅ | Data displays, interactive controls, widgets, watch surfaces, and toast announcements have shipped accessibility coverage. |
| Hard-failing release validation | 🚧 [VOL-60](https://linear.app/mabry-ventures/issue/VOL-60) | Release config validation runs but checks `xcodebuild -showBuildSettings`, not the built `.app/Info.plist`. Masks the Info.plist failures (VOL-55, VOL-56). |
| Checked-in `Info.plist` (vs `INFOPLIST_KEY_*`) | 🚧 [VOL-59](https://linear.app/mabry-ventures/issue/VOL-59) | Currently uses `INFOPLIST_KEY_*` build settings, which silently drop custom keys and stringify array values. Umbrella fix for VOL-55, VOL-56. |
| AI review gate (Gemini + Codex) on PRs | ✅ | Two-bot review gate is part of the protected-branch merge contract. |

## Design

| Feature | Status | Notes |
|---------|--------|-------|
| Design tokens | ✅ | `VA.Colors`, `VA.Typography`, `VA.Space`, `VA.Radius`, and `VA.Shadow` define the visual system. |
| Core components | ✅ | Shared cards, buttons, metric displays, progress rings, states, and coach bubbles ship in `VolumeArcUI`. |
| Liquid Glass materials | ✅ | Material-backed UI is live on supported iOS surfaces. |
| Haptics system | ✅ | Centralized `VAHaptics` patterns ship across training interactions. |
| Motion system | ✅ | Shared spring tokens and motion helpers ship. |
| Dark mode | ✅ | Tokens adapt correctly in light and dark appearance. |
| Dynamic Type | ✅ | Typography tokens scale and screens were updated for Dynamic Type support. |
| Reduced Motion | ✅ | Motion-sensitive surfaces respect `@Environment(\.accessibilityReduceMotion)`. |
| `VAToast` notification system | ✅ | `VAToast`, `VAToastPresenter`, and overlay presentation ship with accessibility announcements. |
| Hero transitions (`.navigationTransition(.zoom)`) | ✅ | Today next-workout and recent-session navigation use iOS 18+ zoom hero transitions with reduce-motion fallback. |
| Pluralization (Apple inflection syntax) | ✅ | Count-bearing strings use `^[\(count) thing](inflect: true)` for CLDR-aware plural agreement. |
| Shared `LocalizedLabels` extensions | ✅ | Enum display strings for `AdvancementLevel`, `CoachingStyle`, `Equipment`, and `PrivacyMode` live in one translator-friendly file. |
