# Feature Status

This is the source of truth for what works, what's partially working, and what's still scaffolding. Update it with every PR that changes a feature's completeness.

## Legend
- ✅ **Shipped** — feature is complete, tested, and production-ready
- 🚧 **In progress** — feature exists and partially works, but has known gaps
- 🏗️ **Scaffold** — types and wiring exist but concrete implementation is stub
- 📋 **Planned** — not yet started

## Platform surfaces

| Feature | Status | Notes |
|---------|--------|-------|
| iOS navigation shell (5 tabs) | 🚧 | Tab bar, screens, transitions wired. Consumes `DashboardNavigationModel`. |
| Today dashboard | 🚧 | Readiness hero, next workout, quick actions, recent sessions. |
| Workouts tab | 🚧 | Active session screen, rest timer (isolated subview), log set, complete. |
| Coach chat | 🚧 | Chat bubbles, typing indicator, quick prompts. Real streaming pending. |
| Signals / readiness | 🚧 | Readiness breakdown, volume chart, frequency heatmap. |
| Profile / settings | 🚧 | Profile header, training rows, diagnostics link. |
| Onboarding flow | ✅ | 5-step flow with progress bar, profile capture, coaching style selection. |
| watchOS workout UI | 🏗️ | UI with rest timer, decisions, coach cue. Driven by hardcoded defaults. |
| Widgets (systemSmall/Medium) | 🏗️ | Views exist. Widget snapshot reader returns nil. |
| Live Activities | 🏗️ | Attributes + controller. No state updates from workout sessions. |

## AI & coaching

| Feature | Status | Notes |
|---------|--------|-------|
| AI provider chain (FoundationModels → Relay → Local) | 🏗️ | Factory selects correctly. Providers return canned/naive responses. |
| `OpenAIRelayCoachProvider` | 🚧 | Real HTTP POST to relay. No streaming, no prompt templates. |
| `LocalHeuristicAICoachProvider` | 🏗️ | Returns one hardcoded sentence. |
| `FoundationModelCoachProvider` | 🏗️ | Creates `LanguageModelSession`. No structured prompts. |
| Voice transport | 🏗️ | `OpenAIRealtimeVoiceTransport` methods are empty stubs. |
| Coach memory | 🚧 | `CoachMemoryRecord` persists memories. Not yet used for prompt grounding. |
| Streaming response UX | 📋 | Token-by-token rendering planned. |
| Evaluation harness | 📋 | Prompt quality regression tests planned. |
| Privacy mode enforcement | 📋 | Mode stored but not enforced in prompts. |

## Data & progression

| Feature | Status | Notes |
|---------|--------|-------|
| SwiftData schema V1 | ✅ | `UserProfileRecord`, `WorkoutRecord`, `TrainingPlanRecord`, `CoachMemoryRecord`. |
| Persistence fallback chain | ✅ | Cloud → local → in-memory → unavailable with metadata. |
| `SwiftDataWorkoutRepository` | ✅ | Create, read, append set, complete, delete, history projection. |
| `SwiftDataUserProfileRepository` | ✅ | Upsert, load, onboarding flag, athlete profile projection. |
| `SwiftDataTrainingPlanRepository` | ✅ | Upsert weekly plan, query next workout. |
| `SwiftDataCoachMemoryRepository` | ✅ | Append, recent, pruning. |
| `ProgressionEngine` | ✅ | Linear/intermediate/advanced progression, exercise substitution, action suggestion. |
| `ReadinessModel` | ✅ | 5-factor readiness score (frequency, rest, volume trend, RPE, duration). |
| Exercise catalog | 🚧 | 11 exercises across 7 movement patterns. Needs expansion. |

## Sync & connectivity

| Feature | Status | Notes |
|---------|--------|-------|
| `CloudSyncCoordinator` | 🏗️ | Stores transport + state store. No push/pull loop. |
| `CloudKitSyncTransport` | 🏗️ | Holds container + zone name. No CKRecord operations. |
| `FileSyncStateStore` | 🚧 | Real disk read/write for cursor persistence. |
| `DefaultSyncPayloadApplier` | 🏗️ | Holds repository references. No apply logic. |
| `WatchConnectivityCoordinator` | 🏗️ | Stores transport + payload store. `send()` is no-op. |
| `NetworkReachabilityMonitor` | ✅ | Real `NWPathMonitor` wrapper. Not yet instantiated in app. |
| Background sync (BGAppRefreshTask) | 📋 | Planned. |

## Observability

| Feature | Status | Notes |
|---------|--------|-------|
| Telemetry fanout | ✅ | `FanoutTelemetrySink` combines in-memory + UserDefaults + OSLog + Sentry. |
| `OSLogTelemetrySink` | ✅ | Logs to unified logging. |
| `UserDefaultsTelemetrySink` | ✅ | Persists rolling buffer of 100 events. |
| `InMemoryTelemetrySink` | ✅ | Bounded buffer of 200 events. |
| `SentryTelemetrySink` | ✅ | Forwards events as breadcrumbs, captures errors as messages. |
| Startup signals | ✅ | Persistence, AI relay, CloudKit, Sentry warnings surfaced. |

## Infrastructure

| Feature | Status | Notes |
|---------|--------|-------|
| Generated Xcode project | ✅ | Ruby script, `generate_xcode_project.rb`. |
| CI pipeline (self-hosted M4) | ✅ | Build, test, lint, validate. |
| Fastlane (test/beta/release) | ✅ | TestFlight automation on tag push. |
| Archive script | ✅ | `archive_for_distribution.sh` with ExportOptions.plist. |
| Privacy manifests | ✅ | All three targets. |
| SwiftLint | 🚧 | Config exists, not installed on runner. |
| Versioning from git | ✅ | `VERSION` file + `git rev-list --count HEAD`. |
| Localization (String Catalog) | 🚧 | `String(localized:)` calls present. No catalog file yet. |
| Accessibility labels | 🚧 | Watch + Widget done. iOS tab views done. Needs audit. |

## Design

| Feature | Status | Notes |
|---------|--------|-------|
| Design tokens | ✅ | Colors, typography, spacing, radius, shadow in `VA` namespace. |
| Core components | ✅ | VACard, VAButton, VAMetricDisplay, VAProgressRing, VASectionHeader, VAEmptyState, VALoadingState, VAErrorState, VACoachBubble. |
| Liquid Glass materials | ✅ | `.regularMaterial` on iOS 26. |
| Haptics system | ✅ | Session, set, rest, decision, error, warning, coach, tap patterns. |
| Motion system | ✅ | Standard spring tokens, `vaAppear()`, number ticker. |
| Dark mode | ✅ | All tokens adapt via `Color(light:dark:)`. |
| Dynamic Type | 🚧 | Typography scales automatically. Layout not yet audited. |
| Reduced Motion | ✅ | `vaAppear()` respects `@Environment(\.accessibilityReduceMotion)`. |
