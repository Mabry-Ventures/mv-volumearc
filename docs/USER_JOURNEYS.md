# User Journey Catalog

> **Status:** Scaffold ([VOL-141](https://linear.app/mabry-ventures/issue/VOL-141)). Every cell with `[ ]` in the Test column is a coverage gap. The `scripts/check_journey_coverage.sh` CI gate (to be wired) parses this file and fails any PR that introduces a `[ ]` row.

## How this doc works

Every distinct user-facing flow in VolumeArc is documented here. Each row maps:
- **Journey ID** — kebab-case, stable
- **Pre-conditions** — app state required to start
- **Steps** — ordered user actions
- **Success criteria** — what proves the journey worked
- **Telemetry** — events that should fire (assert via `VolumeArcAppUITestSupport.assertTelemetryFired(in:category:name:within:test:)` — [VOL-149](https://linear.app/mabry-ventures/issue/VOL-149) Phase 1 landed the helper; Phase 2 wires every row below)
- **XCUITest** — paired test method, or `[ ]` if uncovered

When you add or change a journey: update this table, then update the paired XCUITest. CI should not let an uncovered journey ship.

## Coverage summary

VOL-141 Phase 1 (2026-05-13): audited the actual `Tests/VolumeArcAppUITests/` method names against the journey table. The pre-audit summary listed test methods that don't exist (e.g. `testFirstLaunchCompletesOnboarding`, `testTodayTabRenders`, `testCoachQuestionStreams`). The corrected counts below reflect the real wiring, plus the journeys covered by `VolumeArcHealthKitPermissionJourneyTests` (added in VOL-109) and `VolumeArcWatchSimulationJourneyTests` (added in VOL-112) that were missing from the original table.

| Surface | Total | Covered | Coverage |
|---|---|---|---|
| Onboarding | 5 | 2 | 40% |
| Today | 5 | 1 | 20% |
| Workouts | 7 | 3 | 43% |
| Coach | 6 | 3 | 50% |
| Signals | 3 | 0 | 0% |
| Profile | 8 | 3 | 38% |
| Watch | 6 | 2 | 33% |
| Widgets | 3 | 0 | 0% |
| Live Activities | 3 | 0 | 0% |
| App Intents | 6 | 0 | 0% |
| Background | 4 | 0 | 0% |
| Failure paths | 6 | 0 | 0% |
| **Total** | **62** | **11** | **18%** |

> Goal: 100% by end of Wave 2 (cycle 7, 2026-05-31). Burn down via [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141).
>
> Phase 1 audited references; Phase 2+ adds the actually-missing tests using the VOL-149 `assertTelemetryFired` helper + VOL-168 chaos infra. Each `[ ]` row below is an item to close.

---

## Onboarding

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `onboard.first-launch` | Fresh install | Launch → tap through screens → tap Done | `RootDashboardView.showOnboarding == false`; Today tab visible | `onboarding.completed` | `VolumeArcAppJourneyTests.testOnboardingToFirstWorkout` |
| `onboard.healthkit-grant` | Onboarding open, HK page | Tap "Allow Health" → grant in system sheet | `HealthKit.authorized` for read types; rationale screen NOT shown again | `healthkit.authorized` | `[ ]` (system-sheet automation; needs `addUIInterruptionMonitor` work, tracked in VOL-127 P2) |
| `onboard.healthkit-deny` | Onboarding open, HK page | Tap "Allow Health" → deny in system sheet | App still completes onboarding; coach uses fallback context | `healthkit.denied` | `[ ]` (VOL-168 chaos covers the model path via `-CHAOS_HEALTH_AUTH_DENIED`; full UI journey in VOL-127 P2) |
| `onboard.healthkit-skip` | Onboarding open, HK page | Tap "Not now" (Continue advances regardless of grant) | Onboarding continues; entry into Profile to grant later remains | `healthkit.skipped` | `VolumeArcHealthKitPermissionJourneyTests.testOnboardingPermissionsStepCanBeSkippedByContinuing` |
| `onboard.voice-mic` | Onboarding open, Voice page (premium gate may apply) | Tap "Enable voice" → grant mic | Voice transport installed | `voice.enabled` | `[ ]` |

## Today

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `today.dashboard-view` | Onboarded, seeded data | Open app → Today tab | Readiness hero + next workout + recent sessions visible | `today.viewed` | `VolumeArcAppUITests.testRootDashboardIdentifierExists` (loose match — asserts the root identifier renders; full hero/cards check pending) |
| `today.readiness-tap` | Today visible | Tap readiness hero | Signals tab opens to readiness breakdown | `signals.readiness.opened` | `[ ]` |
| `today.next-workout-tap` | Next workout card present | Tap card | Workout detail opens with hero transition | `workout.detail.opened` | `[ ]` |
| `today.recent-session-tap` | Recent sessions present | Tap a session | Session detail opens | `workout.history.opened` | `[ ]` |
| `today.quick-action-launch` | Today visible | Tap quick action (Ask Coach / Start workout / Sync) | Correct destination opens | per-action event | `[ ]` |

## Workouts

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `workouts.start-session` | Workouts tab | Tap "Start" on prescribed workout | Active session view opens; `WorkoutRecord` created | `workout.started` | `VolumeArcAppJourneyTests.testStartLogCompleteWorkoutSession` (start phase) |
| `workouts.log-set` | Active session | Tap "Log set" → enter rep/weight/RPE → confirm | `WorkoutSet` appended; aggregate updated | `workout.set_logged` | `VolumeArcAppJourneyTests.testStartLogCompleteWorkoutSession` (log phase) |
| `workouts.rest-timer-expire` | Set logged | Wait 90s | Notification fires; haptic; UI updates | `workout.rest_timer.expired` | `[ ]` |
| `workouts.complete-session` | Active session | Tap "Complete" | Session closed; summary shown; CloudKit push staged | `workout.completed` | `VolumeArcAppJourneyTests.testStartLogCompleteWorkoutSession` (complete phase) |
| `workouts.view-detail` | History present | Tap a completed session | Detail view shows sets + summary | `workout.detail.opened` | `[ ]` |
| `workouts.history-scroll` | History tab | Scroll | List paginates without hitches | (perf-only) | `[ ]` |
| `workouts.delete-session` | Completed session | Tap delete (confirm sheet) | Session removed; CloudKit delete staged | `workout.deleted` | `[ ]` |

## Coach

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `coach.ask-question` | Coach tab | Type question → tap Send | Response stream starts within 2s | `coach.question_sent` + `coach.first_token_received` | `VolumeArcCoachJourneyTests.testCoachAskQuestionStreamsResponse` |
| `coach.scroll-memory` | Memory present | Scroll Coach tab | Memory loads paginated | (perf-only) | `VolumeArcCoachJourneyTests.testCoachScrollMemory` |
| `coach.voice-prompt` | Premium + voice flag on | Tap mic → speak → release | Question transcribed → response spoken | `voice.session_started` | `[ ]` |
| `coach.follow-up-turn` | Question answered | Type follow-up → Send | Memory context referenced in response | `coach.session_continued` | `[ ]` |
| `coach.relay-fallback` | Force relay 5xx | Ask question | Fallback to local heuristic; UI shows degraded notice | `coach.fallback_used` | `[ ]` |
| `coach.privacy-mode-strict` | Privacy mode = strict | Ask question | PII redacted from prompt | `coach.privacy_redaction_applied` | `VolumeArcCoachJourneyTests.testCoachPrivacyModeStrictRedactsEmail` (asserts `coach.question_sent` today; the `coach.privacy_redaction_applied` event wiring follows-up at the `CoachPromptTemplate` call site — `PromptPrivacyRedactor` from VOL-197 currently has unit-test coverage only) |

## Signals

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `signals.readiness-breakdown` | Signals tab | Open | Five-factor breakdown visible | `signals.readiness.opened` | `[ ]` |
| `signals.volume-chart` | Signals tab + 7+ days history | Open volume chart | Bar chart renders | `signals.volume.opened` | `[ ]` |
| `signals.frequency-heatmap` | Signals tab + 4+ weeks history | Open heatmap | Heatmap renders with weekday/week-of-year axes | `signals.frequency.opened` | `[ ]` |

## Profile

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `profile.edit-profile` | Profile tab | Tap Edit → change fields → Save | `UserProfileRecord` updated | `profile.updated` | `[ ]` |
| `profile.coaching-style` | Profile tab | Change coaching style | Style saved; coach persona changes on next turn | `profile.coaching_style.changed` | `[ ]` |
| `profile.privacy-mode` | Profile tab | Change privacy mode | Mode saved; coach prompt redaction applies | `profile.privacy_mode.changed` | `[ ]` |
| `profile.diagnostics` | Profile tab | Open Diagnostics | Telemetry events visible; export works | `diagnostics.opened` | `[ ]` |
| `profile.restore-purchase` | Free tier | Tap Restore | StoreKit restore runs; entitlement updates | `subscription.restored` | `VolumeArcAppJourneyTests.testRestorePurchasesFlow` |
| `profile.open-paywall` | Free tier | Tap Upgrade | Paywall sheet opens | `paywall.opened` | `VolumeArcAppJourneyTests.testPaywallPresentationAndDismissal` |
| `profile.complete-purchase` | Paywall open, sandbox tester | Tap plan → confirm | Premium entitlement granted; tier routes to Pro | `paywall.purchase_succeeded` | `VolumeArcAppJourneyTests.testPremiumPurchaseFlowWithStoreKitTest` |
| `profile.manage-subscription` | Premium | Tap Manage | iOS Settings opens (no crash) | `subscription.manage_opened` | `[ ]` (deferred to VOL-142 Phase 2 deep-link smoke test) |
| `profile.send-feedback` | Profile tab | Tap Send feedback → pick category → enter description → Submit | Sheet dismisses; bundle forwarded to Sentry; `feedback.submitted` telemetry recorded | `feedback.submitted` | `VolumeArcFeedbackJourneyTests.testProfileSendFeedbackJourney` + `.testFeedbackCancelDoesNotEmitSubmitTelemetry` |

## Watch

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `watch.start-workout` | Watch app open, paired | Tap Start | `HKWorkoutSession` begins | `watch.workout.started` | `VolumeArcWatchSimulationJourneyTests.testRestTimerPayloadFromWatchUpdatesDashboardState` (phone side of the wire; full watch-side journey requires the watch unit-test target — VOL-138) |
| `watch.log-set` | Active workout on watch | Use crown / buttons to log set | Set persisted; payload sent to phone | `watch.set_logged` + `watch.payload_sent` | `[ ]` |
| `watch.coach-cue` | Active workout | Wait for cue | Cue rendered; haptic | `watch.coach_cue.received` | `[ ]` |
| `watch.action-decision` | Active workout, between sets | Tap Increase/Hold/Decrease | Decision recorded; next prescription adjusted | `watch.set_decision` | `[ ]` |
| `watch.end-session` | Active workout | Tap End | Session ended; payload pushed | `watch.workout.completed` | `VolumeArcWatchSimulationJourneyTests.testEndSessionPayloadFromWatchUpdatesDashboardState` (phone side of the wire) |
| `watch.offline-replay` | Phone unreachable; payloads queued | Reconnect | Queue drains; phone receives | `watch.payload_replayed` | `[ ]` |

## Widgets

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `widget.add-small` | App installed | Long-press home → Add → VolumeArc Small | Widget renders with current snapshot | (no in-widget telemetry) | `[ ]` |
| `widget.add-medium` | App installed | Add medium widget | Widget renders | (no in-widget telemetry) | `[ ]` |
| `widget.tap-deep-link` | Widget present | Tap widget | App opens to deep-link target | `deeplink.received` | `[ ]` |

## Live Activities

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `liveactivity.start` | Workout started | (auto) | Live Activity appears on lock screen | `liveactivity.started` | `[ ]` |
| `liveactivity.dynamic-island` | Workout active | Long-press Dynamic Island | Expanded layout renders with rest timer + exercise | (visual) | `[ ]` |
| `liveactivity.end` | Workout completed | (auto) | Live Activity dismisses | `liveactivity.ended` | `[ ]` |

## App Intents (Siri Shortcuts)

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `intent.start-next-workout` | App backgrounded | "Hey Siri, start next workout" | App opens → Workouts tab → active session | `intent.start_next_workout.invoked` | `[ ]` |
| `intent.ask-coach` | Any | "Hey Siri, ask VolumeArc..." | App opens → Coach tab → prefilled prompt | `intent.ask_coach.invoked` | `[ ]` |
| `intent.open-signals` | Any | "Hey Siri, open VolumeArc Signals" | App opens → Signals tab | `intent.open_signals.invoked` | `[ ]` |
| `intent.start-workout-session` | Any | Shortcut runs | Session begins | `intent.start_session.invoked` | `[ ]` |
| `intent.log-recommended-set` | Active session | Shortcut runs | Recommended set logged | `intent.log_set.invoked` | `[ ]` |
| `intent.sync-volumearc` | Any | Shortcut runs | `CloudSyncCoordinator.syncCycle` runs | `intent.sync.invoked` | `[ ]` |

## Background

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `bg.app-refresh` | BGTask scheduled | iOS triggers `appRefresh` | Sync runs; widget snapshots updated | `bg.app_refresh.fired` | `[ ]` |
| `bg.processing` | BGTask scheduled | iOS triggers `appProcessing` | Longer work runs | `bg.processing.fired` | `[ ]` |
| `bg.push-notification` | Notification arrives | Tap notification | App opens to deep-link | `notification.tapped` | `[ ]` |
| `bg.deep-link-arrival` | Universal link tapped externally | Tap link | App opens to correct destination | `deeplink.received` | `[ ]` |

## Failure paths

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `fail.offline` | Airplane mode | Open Coach → ask question | Local heuristic responds; UI shows offline banner | `coach.fallback_used` | `[ ]` |
| `fail.no-icloud` | iCloud signed out | Open app | App functions without sync; CloudKit transport falls back to Unavailable | `cloudsync.unavailable` | `[ ]` |
| `fail.healthkit-not-granted` | Onboarding skipped HK | Open Today | Readiness hero shows "Grant Health to unlock"; coach uses fallback | `healthkit.unavailable` | `[ ]` |
| `fail.relay-401` | Relay returns 401 | Open Coach → ask | Session token re-fetch; retry succeeds | `relay.session_refreshed` | `[ ]` |
| `fail.relay-5xx` | Relay returns 500 | Open Coach → ask | Local heuristic responds; UI shows degraded notice | `coach.fallback_used` | `[ ]` |
| `fail.fm-unavailable` | iOS < 26 or model not downloaded | Open Coach | Provider chain skips FM, uses relay or heuristic | `ai.fm.unavailable` | `[ ]` |

---

## Burndown plan

Each `[ ]` row above is an item to close. Sibling tickets in [VolumeArc Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d):

- [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141) parent — close all rows + wire `check_journey_coverage.sh`
- [VOL-127](https://linear.app/mabry-ventures/issue/VOL-127) — onboarding HK + force-quit + WCSession journeys
- [VOL-142](https://linear.app/mabry-ventures/issue/VOL-142) — paywall + StoreKit edge journeys
- [VOL-149](https://linear.app/mabry-ventures/issue/VOL-149) — telemetry-as-UAT helper used by every journey
- [VOL-158](https://linear.app/mabry-ventures/issue/VOL-158) — re-run every journey on iPad
- [VOL-94](https://linear.app/mabry-ventures/issue/VOL-94) — re-run real-device-only journeys (CloudKit, HealthKit, BGTask, WCSession, Live Activity) on hardware

When this catalog hits 100% covered, update [`PLATFORM.md`](PLATFORM.md) Implementation Status row for Testing.
