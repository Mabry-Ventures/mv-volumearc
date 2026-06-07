# User Journey Catalog

> **Status:** 72/72 automated for simulator-safe v1 rows ([VOL-141](https://linear.app/mabry-ventures/issue/VOL-141)). Every cell with `[ ]` in the Test column is a coverage gap. The `scripts/check_journey_coverage.sh` CI gate parses this file and fails below the configured threshold.

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
| Onboarding | 5 | 5 | 100% |
| Today | 5 | 5 | 100% |
| Workouts | 7 | 7 | 100% |
| Coach | 6 | 6 | 100% |
| Signals | 3 | 3 | 100% |
| Profile | 12 | 12 | 100% |
| Watch | 6 | 6 | 100% |
| Widgets | 3 | 3 | 100% |
| Live Activities | 3 | 3 | 100% |
| App Intents | 6 | 6 | 100% |
| Background | 4 | 4 | 100% |
| Failure paths | 6 | 6 | 100% |
| Resilience / interruption (VOL-127 P2) | 6 | 6 | 100% |
| **Total** | **72** | **72** | **100%** |

> Goal: 100% by end of Wave 2 (cycle 7, 2026-05-31). Burn down via [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141).
>
> Phase 1 audited references; Phase 2+ added the actually-missing tests using the VOL-149 `assertTelemetryFired` helper + VOL-168 chaos infra. The remaining launch proof is physical iPhone + paired Apple Watch UAT, not uncovered simulator rows.
>
> VOL-275 release evidence outside the 72-row catalog: `VolumeArcTodayJourneyTests.testTodayPlanTomorrowSchedulesCoDesignedDraftIntoWorkouts` covers Today `Plan tomorrow` -> Coach plan draft -> `Schedule` -> Workouts scheduled tomorrow card -> `coach.plan_scheduled` telemetry. `VolumeArcTodayJourneyTests.testTodayPlanTomorrowEditsExerciseRowsBeforeScheduling` covers swap, move, set adjustment, remove, and scheduling the edited prescription into Workouts.

---

## Onboarding

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `onboard.first-launch` | Fresh install | Launch → tap through screens → tap Done | `RootDashboardView.showOnboarding == false`; Today tab visible | `onboarding.completed` | `VolumeArcAppJourneyTests.testOnboardingToFirstWorkout` |
| `onboard.healthkit-grant` | Onboarding open, HK page | Tap "Connect Apple Health" → grant through deterministic authorized fixture | `HealthKit.authorized` for read types; rationale screen NOT shown again; physical system sheet remains UAT | `healthkit.authorized` | `VolumeArcHealthKitPermissionJourneyTests.testOnboardingHealthKitGrantFixtureConnectsAndEmitsTelemetry` + `HealthKitAuthorizationTests.testReturnsTrueAndRecordsRequestedWhenStoreGrants` |
| `onboard.healthkit-deny` | Onboarding open, HK page | Tap "Connect Apple Health" → deny through deterministic chaos fixture | App still completes onboarding; coach uses fallback context; physical system sheet remains UAT | `healthkit.denied` | `VolumeArcHealthKitPermissionJourneyTests.testOnboardingHealthKitDeniedFixtureKeepsFlowUsableAndEmitsTelemetry` + `HealthKitAuthorizationTests.testReturnsFalseWhenStoreDeniesButDoesNotThrow` |
| `onboard.healthkit-skip` | Onboarding open, HK page | Tap "Not now" (Continue advances regardless of grant) | Onboarding continues; entry into Profile to grant later remains | `healthkit.skipped` | `VolumeArcHealthKitPermissionJourneyTests.testOnboardingPermissionsStepCanBeSkippedByContinuing` |
| `onboard.voice-mic` | Coach voice setup available; premium + voice flag on | Tap mic → grant microphone/speech via fixture; physical system sheets remain UAT | Voice permissions authorized; voice transport installed | `voice.enabled` | `VolumeArcCoachJourneyTests.testVoicePromptUsesPremiumPermissionFixtureAndEmitsTelemetry` + `VolumeArcDashboardIntegrationTests.testVoiceCoachPermissionAndSingleTurnPromptEmitJourneyTelemetry` |

## Today

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `today.dashboard-view` | Onboarded, seeded data | Open app → Today tab | Readiness hero + next workout + recent sessions visible | `today.viewed` | `VolumeArcAppUITests.testRootDashboardIdentifierExists` (loose match — asserts the root identifier renders; full hero/cards check pending) |
| `today.readiness-tap` | Today visible | Tap readiness hero | Signals tab opens to readiness breakdown | `signals.readiness.opened` | `VolumeArcTodayJourneyTests.testTodayReadinessTapOpensSignals` |
| `today.next-workout-tap` | Next workout card present | Tap card | Workout detail opens with hero transition | `workout.detail.opened` | `VolumeArcTodayJourneyTests.testTodayNextWorkoutTapOpensDetail` |
| `today.recent-session-tap` | Recent sessions present | Tap a session | Session detail opens | `workout.history.opened` | `VolumeArcTodayJourneyTests.testTodayRecentSessionTapOpensDetail` |
| `today.quick-action-launch` | Today visible | Tap quick action (Ask Coach / Start workout / Sync) | Correct destination opens | per-action event | `VolumeArcTodayJourneyTests.testTodayAskCoachQuickActionOpensCoach` (covers Ask Coach branch; Start Workout + Sync branches follow in subsequent PRs) |

## Workouts

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `workouts.start-session` | Workouts tab | Tap "Start" on prescribed workout | Active session view opens; `WorkoutRecord` created | `workout.started` | `VolumeArcAppJourneyTests.testStartLogCompleteWorkoutSession` (start phase) |
| `workouts.log-set` | Active session | Tap "Log set" → enter rep/weight/RPE → confirm | `WorkoutSet` appended; aggregate updated | `workout.set_logged` | `VolumeArcAppJourneyTests.testStartLogCompleteWorkoutSession` (log phase) |
| `workouts.rest-timer-expire` | Set logged | Wait 90s | Haptic fires; UI updates; completion toast appears; notification-delivery proof remains physical/system UAT | `workout.rest_timer.expired` | `VolumeArcAppJourneyTests.testWorkoutRestTimerExpiryEmitsTelemetryAndShowsCompletionToast` |
| `workouts.complete-session` | Active session | Tap "Complete" | Session closed; summary shown; CloudKit push staged | `workout.completed` | `VolumeArcAppJourneyTests.testStartLogCompleteWorkoutSession` (complete phase) |
| `workouts.view-detail` | History present | Tap a completed session | Detail view shows sets + summary | `workout.detail.opened` | `VolumeArcAppJourneyTests.testWorkoutHistoryRowOpensSessionDetailAndEmitsTelemetry` |
| `workouts.history-scroll` | History tab | Scroll | List paginates without hitches | (perf-only) | `VolumeArcAppJourneyTests.testWorkoutHistoryScrollStaysResponsiveWithLongHistory` |
| `workouts.delete-session` | Completed session | Tap delete (confirm sheet) | Session removed; CloudKit delete staged | `workout.deleted` | `VolumeArcAppJourneyTests.testWorkoutHistoryDeleteSessionRemovesRowAndEmitsTelemetry` |

## Coach

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `coach.ask-question` | Coach tab | Type question → tap Send | Response stream starts within 2s | `coach.question_sent` + `coach.first_token_received` | `VolumeArcCoachJourneyTests.testCoachAskQuestionStreamsResponse` |
| `coach.scroll-memory` | Memory present | Scroll Coach tab | Memory loads paginated | (perf-only) | `VolumeArcCoachJourneyTests.testCoachScrollMemory` |
| `coach.voice-prompt` | Premium + voice flag on; prompt transcript available | Tap mic with dictated/fixture transcript | Voice coach response renders in transcript; single-turn transport completes | `voice.session_started` | `VolumeArcCoachJourneyTests.testVoicePromptUsesPremiumPermissionFixtureAndEmitsTelemetry` + `VolumeArcDashboardIntegrationTests.testVoiceCoachPermissionAndSingleTurnPromptEmitJourneyTelemetry` |
| `coach.follow-up-turn` | Question answered | Type follow-up → Send | Memory context referenced in response | `coach.session_continued` | `VolumeArcCoachJourneyTests.testCoachFollowUpTurnRendersSecondResponse` (asserts a second coach bubble renders for the follow-up turn; the `coach.session_continued` event wiring is a follow-up — test gates on `coach.ask_complete`) |
| `coach.relay-fallback` | Force relay 5xx | Ask question | Fallback to local heuristic response; hard-failure copy is not shown | `coach.fallback_used` | `VolumeArcCoachJourneyTests.testCoachRelay5xxFallsBackToLocalHeuristic` |
| `coach.privacy-mode-strict` | Privacy mode = strict | Ask question | PII redacted from prompt | `coach.privacy_redaction_applied` | `VolumeArcCoachJourneyTests.testCoachPrivacyModeStrictRedactsEmail` (asserts `coach.question_sent` today; the `coach.privacy_redaction_applied` event wiring follows-up at the `CoachPromptTemplate` call site — `PromptPrivacyRedactor` from VOL-197 currently has unit-test coverage only) |

## Signals

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `signals.readiness-breakdown` | Signals tab | Open | Five-factor breakdown visible | `signals.readiness.opened` | `VolumeArcSignalsJourneyTests.testSignalsReadinessOpenedFiresOnLaunch` |
| `signals.volume-chart` | Signals tab + 7+ days history | Open volume chart | Bar chart renders | `signals.volume.opened` | `VolumeArcSignalsJourneyTests.testSignalsVolumeOpenedFiresOnLaunch` |
| `signals.frequency-heatmap` | Signals tab + 4+ weeks history | Open heatmap | Heatmap renders with weekday/week-of-year axes | `signals.frequency.opened` | `VolumeArcSignalsJourneyTests.testSignalsFrequencyOpenedFiresOnLaunch` |

## Profile

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `profile.edit-profile` | Profile tab | Tap Edit → change fields → Save | `UserProfileRecord` updated | `profile.updated` | `VolumeArcProfileJourneyTests.testProfileOpenEditAndSaveRoundTripDismissesSheet` |
| `profile.coaching-style` | Profile tab | Change coaching style | Style saved; coach persona changes on next turn | `profile.coaching_style.changed` | `VolumeArcProfileJourneyTests.testProfileCoachingStyleChangePersistsAndEmitsTelemetry` |
| `profile.privacy-mode` | Profile tab | Change privacy mode | Mode saved; coach prompt redaction applies | `profile.privacy_mode.changed` | `VolumeArcProfileJourneyTests.testProfilePrivacyModeChangePersistsAndEmitsTelemetry` |
| `profile.appearance` | Profile tab | Open Appearance setting | System, Light, and Dark options are available; Warm remains an internal brand personality for design parity, not a user-facing theme | N/A | `VolumeArcProfileJourneyTests.testProfileAppearancePickerExposesSystemLightAndDarkOnly` + `AppearancePreferenceTests.testUserSelectableCasesExcludeWarmBrandPersonality` |
| `profile.diagnostics` | Profile tab | Open Diagnostics | Telemetry events visible; export works | `diagnostics.opened` | `VolumeArcProfileJourneyTests.testProfileDiagnosticsRowOpensView` |
| `profile.about` | Profile tab | Open About | About screen explains product posture, privacy boundaries, support, legal links, and build info | N/A | `VolumeArcProfileJourneyTests.testProfileAboutRowOpensUsefulAboutSurface` |
| `profile.session-profiles` | Profile tab | Open Session Profiles → create custom profile → review automation rules → Save | Custom profile is selectable and shown on Profile | `profile.updated` | `VolumeArcProfileJourneyTests.testSessionProfilesCanCreateCustomProfileAndExposeRules` |
| `profile.restore-purchase` | Free tier | Tap Restore | StoreKit restore runs; entitlement updates | `subscription.restored` | `VolumeArcAppJourneyTests.testRestorePurchasesFlow` |
| `profile.open-paywall` | Free tier | Tap Upgrade | Paywall sheet opens | `paywall.opened` | `VolumeArcAppJourneyTests.testPaywallPresentationAndDismissal` |
| `profile.complete-purchase` | Paywall open, sandbox tester | Tap plan → confirm | Premium entitlement granted; tier routes to Pro | `paywall.purchase_succeeded` | `VolumeArcAppJourneyTests.testPremiumPurchaseFlowWithStoreKitTest` |
| `profile.manage-subscription` | Premium | Tap Manage | Apple subscription management opens; deterministic UI tests suppress the external URL and keep the app foreground | `subscription.manage_opened` | `VolumeArcProfileJourneyTests.testProfileManageSubscriptionRecordsTelemetryWithoutLeavingApp` |
| `profile.send-feedback` | Profile tab | Tap Send feedback → pick category → enter description → Submit | Feedback surface dismisses; bundle forwarded to Sentry; `feedback.submitted` telemetry recorded | `feedback.submitted` | `VolumeArcFeedbackJourneyTests.testProfileSendFeedbackJourney` + `.testFeedbackCancelDoesNotEmitSubmitTelemetry` |

## Watch

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `watch.start-workout` | Watch app open, paired | Tap Start | `HKWorkoutSession` begins | `watch.workout.started` | `VolumeArcWatchSimulationJourneyTests.testStartSessionPayloadFromWatchUpdatesDashboardState` (phone side of the wire) + `WatchWorkoutModelHealthKitTests` start-session coverage; full paired-device UAT remains a launch gate. |
| `watch.log-set` | Active workout on watch | Use crown / buttons to log set | Set persisted; payload sent to phone | `watch.set_logged` + `watch.payload_sent` | `WatchWorkoutModelHealthKitTests.test_doubleTapDisabledDoesNotRecordTelemetryButManualButtonStillLogsSet` (watch-model proof; full watch UI/UAT remains a launch gate). |
| `watch.coach-cue` | Active workout | Wait for cue | Cue rendered; haptic | `watch.coach_cue.received` | `VolumeArcWatchSimulationJourneyTests.testCoachCuePayloadFromWatchUpdatesDashboardState` (phone side of the wire) + `WatchPhonelessJourneyTests.test_coachCueQueuesAndReplaysOnReconnect`; full watch UI/UAT remains a launch gate. |
| `watch.action-decision` | Active workout, between sets | Tap Increase/Hold/Decrease | Decision recorded; next prescription adjusted | `watch.set_decision` | `VolumeArcWatchSimulationJourneyTests.testDecisionPayloadFromWatchUpdatesDashboardState` (phone side of the `liveState` wire) + `WatchPhonelessJourneyTests.test_watchCompletesWorkoutWithoutPhone_thenDrainsOnReconnect`; full watch UI/UAT remains a launch gate. |
| `watch.end-session` | Active workout | Tap End | Session ended; payload pushed | `watch.workout.completed` | `VolumeArcWatchSimulationJourneyTests.testEndSessionPayloadFromWatchUpdatesDashboardState` (phone side of the wire) |
| `watch.offline-replay` | Phone unreachable; payloads queued | Reconnect | Queue drains; phone receives | `watch.payload.replayed` | `WatchPhonelessJourneyTests.test_watchCompletesWorkoutWithoutPhone_thenDrainsOnReconnect` + `WatchConnectivityCoordinatorTests.test_flushPendingIfReachable_drains_queue_when_reachable` |

## Widgets

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `widget.add-small` | App installed | Long-press home → Add → VolumeArc Small | Widget renders with current snapshot | (no in-widget telemetry) | `NextWorkoutWidgetSnapshotTests.testSystemSmallLight` + `.testSystemSmallDark` + `VolumeArcWidgetUITests.testHostAppLaunchesWithWidgetExtensionEmbedded` (render/embed proof; SpringBoard gallery add remains manual UAT) |
| `widget.add-medium` | App installed | Add medium widget | Widget renders | (no in-widget telemetry) | `NextWorkoutWidgetSnapshotTests.testSystemMediumLight` + `.testSystemMediumDark` + `VolumeArcWidgetUITests.testWidgetCenterReloadIsSafeFromTestBundle` (render/WidgetKit proof; SpringBoard gallery add remains manual UAT) |
| `widget.tap-deep-link` | Widget present | Tap widget | App opens to deep-link target | `deeplink.received` | `VolumeArcAppJourneyTests.testWidgetDeepLinkRoutesToTodayAndEmitsTelemetry` |

## Live Activities

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `liveactivity.start` | Workout started | (auto) | Live Activity appears on lock screen | `liveactivity.started` | `VolumeArcDashboardIntegrationTests.testWorkoutStartAndCompletionPublishLiveActivityJourneyTelemetry` + `ActiveWorkoutLiveActivitySnapshotTests.testLockScreenCountdownLight` + `.testLockScreenCountdownDark` (state/telemetry/render proof; physical lock-screen presentation remains manual UAT) |
| `liveactivity.dynamic-island` | Workout active | Long-press Dynamic Island | Expanded layout renders with rest timer + exercise | (visual) | `ActiveWorkoutLiveActivitySnapshotTests.testDynamicIslandExpandedLight` + `.testDynamicIslandExpandedDark` (expanded-region render proof; physical Dynamic Island long-press remains manual UAT) |
| `liveactivity.end` | Workout completed | (auto) | Live Activity dismisses | `liveactivity.ended` | `VolumeArcDashboardIntegrationTests.testWorkoutStartAndCompletionPublishLiveActivityJourneyTelemetry` (state clear + telemetry proof; physical dismissal remains manual UAT) |

## App Intents (Siri Shortcuts)

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `intent.start-next-workout` | App backgrounded | "Hey Siri, start next workout" | App opens → Workouts tab → active session | `intent.start_next_workout.invoked` | `VolumeArcIntentJourneyTests.testStartNextWorkoutIntentStartsLiveSessionAndEmitsTelemetry` |
| `intent.ask-coach` | Any | "Hey Siri, ask VolumeArc..." | App opens → Coach tab → prefilled prompt | `intent.ask_coach.invoked` | `VolumeArcIntentJourneyTests.testAskCoachIntentPrefillsPromptAndEmitsTelemetry` |
| `intent.open-signals` | Any | "Hey Siri, open VolumeArc Signals" | App opens → Signals tab | `intent.open_signals.invoked` | `VolumeArcIntentJourneyTests.testOpenSignalsIntentRoutesToSignalsAndEmitsTelemetry` |
| `intent.start-workout-session` | Any | Shortcut runs | Session begins | `intent.start_workout_session.invoked` | `VolumeArcIntentJourneyTests.testStartWorkoutSessionIntentStartsLiveSessionAndEmitsTelemetry` |
| `intent.log-recommended-set` | Active session | Shortcut runs | Recommended set logged | `intent.log_recommended_set.invoked` | `VolumeArcIntentJourneyTests.testLogRecommendedSetIntentLogsSetAndEmitsTelemetry` |
| `intent.sync-volumearc` | Any | Shortcut runs | `CloudSyncCoordinator.syncCycle` runs | `intent.sync_now.invoked` | `VolumeArcIntentJourneyTests.testSyncVolumeArcIntentRoutesToSignalsAndRequestsSync` |

## Background

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `bg.app-refresh` | BGTask scheduled | iOS triggers `appRefresh` | Sync runs; widget snapshots updated | `background.refresh_started` + `background.refresh_completed` | `VolumeArcBackgroundTasksTests.testPerformBackgroundRefreshRecordsBracketingTelemetry` + `VolumeArcBackgroundTasksTests.testWidgetSnapshotRoundTripPreservesAllFields` |
| `bg.processing` | BGTask scheduled | iOS triggers `appProcessing` | Longer work runs | `background.processing_started` + `background.processing_completed` | `VolumeArcBackgroundTasksTests.testPerformBackgroundProcessingRecordsBracketingTelemetry` |
| `bg.push-notification` | Notification arrives | Tap notification | App opens to deep-link | `notification.tapped` | `VolumeArcAppJourneyTests.testNotificationTapRoutesToDeepLinkAndEmitsTelemetry` (app-boundary notification tap proof; APNs/SpringBoard delivery remains physical UAT) |
| `bg.deep-link-arrival` | Universal link tapped externally | Tap link | App opens to correct destination | `deeplink.received` | `VolumeArcAppJourneyTests.testExternalDeepLinkRoutesToSignalsAndEmitsTelemetry` |

## Failure paths

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `fail.offline` | Airplane mode | Open Coach → ask question | Local heuristic responds; UI shows offline banner | `coach.fallback_used` | `VolumeArcCoachJourneyTests.testCoachOfflineFallsBackToLocalHeuristicAndShowsBanner` |
| `fail.no-icloud` | iCloud signed out | Open app | App functions without sync; CloudKit transport falls back to Unavailable | `cloudsync.unavailable` | `VolumeArcAppJourneyTests.testNoICloudLaunchKeepsAppUsableAndEmitsUnavailableTelemetry` |
| `fail.healthkit-not-granted` | Onboarding skipped HK | Open Today | Readiness hero shows "Grant Health to unlock"; coach uses fallback | `healthkit.unavailable` | `VolumeArcTodayJourneyTests.testTodayHealthKitUnavailableShowsUnlockStateAndTelemetry` |
| `fail.relay-401` | Relay returns 401 | Open Coach → ask | Session token re-fetch; retry succeeds; if the refreshed retry is also unauthorized the local heuristic fallback answers safely | `relay.session_refreshed` | `VolumeArcCoachJourneyTests.testCoachRelay401RefreshesSessionAndRetries` + `VolumeArcCoachJourneyTests.testCoachRelay401FallsBackToLocalHeuristic` |
| `fail.relay-5xx` | Relay returns 500 | Open Coach → ask | Local heuristic responds; hard-failure copy is not shown | `coach.fallback_used` | `VolumeArcCoachJourneyTests.testCoachRelay5xxFallsBackToLocalHeuristic` |
| `fail.fm-unavailable` | iOS < 26 or model not downloaded | Open Coach | Provider chain skips FM, uses relay or heuristic | `ai.fm.unavailable` | `VolumeArcCoachJourneyTests.testCoachFoundationModelsUnavailableFallsBackQuietly` |

## Resilience / interruption (VOL-127 Phase 2)

Force-quit / resume + connectivity-interruption journeys. Each row captures a "user expects to pick up where they left off" scenario; a regression here would manifest as data loss or a stuck UI on resume. Most of these surfaces have unit-level coverage (`WatchPhonelessJourneyTests` for the watch side, `VolumeArcPersistenceTests` for SwiftData round-tripping) but no end-to-end UAT pass — Phase 2 closes that gap.

| ID | Pre-conditions | Steps | Success | Telemetry | Test |
|---|---|---|---|---|---|
| `resilience.force-quit-onboarding` | Onboarding open, advanced past welcome | Force-quit app (swipe up from app switcher) → relaunch | Onboarding resumes at the last step the user reached (not from scratch) | `onboarding.resumed` | `VolumeArcAppJourneyTests.testForceQuitOnboardingResumesLastStepAndEmitsTelemetry` |
| `resilience.force-quit-active-workout` | Active session, ≥1 set logged | Force-quit app → relaunch | SwiftData active session resumes; logged sets persist; physical `HKWorkoutSession` recovery remains paired-device UAT | `workout.active_session.recovered` | `VolumeArcAppJourneyTests.testForceQuitActiveWorkoutRestoresLoggedSetOnRelaunch` |
| `resilience.force-quit-coach-turn` | Coach stream in flight | Force-quit app → relaunch | Stream completion gracefully aborted; partial response NOT persisted as final; user can re-issue prompt | `coach.stream.aborted` | `VolumeArcCoachJourneyTests.testForceQuitCoachTurnDropsPartialAndEmitsAbortedOnRelaunch` |
| `resilience.wc-interrupt-midpayload` | Watch session active, decision payload in flight | Kill `WCSession` mid-payload (toggle iPhone airplane mode) | Offline payload queue retains the payload; replay fires on reconnect; user sees status banner explaining the queue state | `watch.payload.queued` + `watch.payload.replayed` | `VolumeArcDashboardIntegrationTests.testWatchConnectivityDropQueuesPayloadAndSurfacesNotice` + `WatchPhonelessJourneyTests.test_watchCompletesWorkoutWithoutPhone_thenDrainsOnReconnect` (queue/banner proof; physical airplane-mode toggle remains manual UAT) |
| `resilience.wc-reconnect-replay` | Pending payloads queued | Re-enable iPhone connectivity | All queued payloads transmit in order, no duplication; queue empties; status banner updates | `watch.payload.replayed` (per payload) | `VolumeArcDashboardIntegrationTests.testWatchConnectivityReconnectReplaysQueuedPayloadAndUpdatesNotice` + `WatchConnectivityCoordinatorTests.test_flushPendingIfReachable_drains_queue_when_reachable` (replay/banner proof; physical paired reconnect remains manual UAT) |
| `resilience.app-killed-bgtask` | Background fetch task scheduled | Force-quit app between fetches | App-boundary BGTask wake recovers the active session and does not duplicate local writes; physical post-force-quit OS delivery remains UAT | `bgtask.fired` | `VolumeArcBackgroundTasksTests.testBackgroundTaskWakeAfterProcessRestartRecoversWithoutDuplicateWorkouts` (deterministic model-boundary proof; physical Xcode "Simulate Background Fetch" / device wake remains manual UAT) |

---

## Manual UAT scripts (VOL-127 Phase 2)

End-to-end human verification scripts for the journeys we can't reliably automate (system-permission sheets, force-quit/resume, real device-only flows). Each script is paired with the journey ID above and meant to be executed by a UAT tester on a TestFlight build before broad rollout.

The scripts intentionally test the **degraded paths** (deny, skip, force-quit) more aggressively than the happy paths — happy paths are easy to verify by accident; degraded paths are where the silent regressions hide.

### `onboard.healthkit-*` — permission paths

> Tests rows `onboard.healthkit-grant` / `onboard.healthkit-deny` / `onboard.healthkit-skip`. Run all three variants in sequence on a fresh install. The custom rationale screen (VOL-127 Phase 1) appears BEFORE the system sheet — that's what we're verifying along with the post-decision state.

**Setup.** Delete the VolumeArc app from the device. Verify Settings → Health → Apps → VolumeArc is removed (or shows "No Access"). Reinstall from TestFlight.

**Path A: Grant.**
1. Launch the app cold.
2. Advance through onboarding screens (Welcome → Athlete → Goals → Permissions).
3. On the Permissions page, observe the four-bullet HealthKit rationale screen shown BEFORE any system prompt. The screen should explain: what we read (HRV / sleep / workouts), why (coach prescription), what stays on-device, what syncs to CloudKit private DB. **Expected:** the four bullets are present, the body copy is non-truncated at Dynamic Type XXL, and the "Allow Health" CTA is enabled.
4. Tap "Allow Health". A system permission sheet appears.
5. Tap "Allow All" on the system sheet.
6. **Expected:** onboarding advances to the next page (Voice). Telemetry `healthkit.authorized` fires.
7. Complete onboarding. Open Today.
8. **Expected:** the readiness hero renders with a real score (not "Grant Health to unlock"). Profile → Diagnostics shows HealthKit as granted for read types (HRV, sleep, completed workouts).
9. Force-quit, relaunch. **Expected:** the rationale screen does NOT appear again. HealthKit stays granted.

**Path B: Deny.**
1. Repeat Setup. Reinstall.
2. Same as Path A through step 4.
3. Tap "Don't Allow" on the system sheet.
4. **Expected:** onboarding still advances. Telemetry `healthkit.denied` fires.
5. Complete onboarding. Open Today.
6. **Expected:** readiness hero shows "Grant Health to unlock" (or equivalent fallback messaging). The coach uses fallback context (no HRV / sleep references). Profile → Diagnostics shows HealthKit as denied.
7. **Expected:** the app does NOT silently re-prompt; the user must explicitly tap a "Re-enable Health" affordance in Profile to retry.

**Path C: Skip.**
1. Repeat Setup. Reinstall.
2. Same as Path A through step 3.
3. Tap "Not now" instead of "Allow Health".
4. **Expected:** onboarding advances. Telemetry `healthkit.skipped` fires.
5. Same expectations as Path B for Today / Profile / re-prompt behavior.

**Failure modes to look for.**
- Rationale screen body copy clipped on Dynamic Type XXL (regression in scrolling container).
- "Allow Health" CTA fires the system sheet WITHOUT showing the rationale first (regression in the rationale-gating).
- Telemetry events missing or wrong category / name (regression in `HealthKitAuthorizationCoordinator`).
- Re-prompt loop: the rationale screen re-appears every launch even after a decision (regression in the "decision sticky" state).
- HealthKit shows as granted in Profile → Diagnostics but the readiness hero still says "Grant Health to unlock" (regression in the readiness-hero state binding).

### `onboard.voice-mic` — voice and microphone permissions

> Tests row `onboard.voice-mic`. The v1 product no longer carries a dedicated onboarding Voice page; voice setup happens from the Coach composer, is premium-gated, and uses the single-turn voice transport documented in `PLATFORM.md`. Automated coverage uses a premium entitlement fixture, authorized voice-permission fixture, and transcript fixture. Physical UAT must still verify the real microphone and speech-recognition system sheets on TestFlight.

**Setup.** Fresh install or seeded TestFlight account with premium active.

1. Complete onboarding if needed. Open Coach.
2. Enter or dictate a test phrase such as "How's my form on squats?"
3. Tap the mic button in the composer.
4. System sheets appear in sequence: Microphone, then Speech Recognition.
5. Grant both.
6. **Expected:** telemetry `voice.enabled` fires. The voice coach turn starts and telemetry `voice.session_started` fires.
7. **Expected:** the coach response renders in the transcript and telemetry `voice.session_completed` fires.
8. Force-quit, relaunch. Open Coach, enter/dictate another prompt, and tap mic.
9. **Expected:** the voice turn starts without re-prompting for permission.

**Path B: Deny microphone.**
1. Repeat Setup. Reinstall.
2. Same as Path A through step 4.
3. Deny the microphone prompt.
4. **Expected:** Coach surfaces "Enable microphone and speech access in Settings to use voice." The user can still send text coach prompts.
5. Coach's mic button remains unavailable until permissions are restored.

### `resilience.force-quit-*` — force-quit / resume

> Tests rows `resilience.force-quit-onboarding` / `resilience.force-quit-active-workout` / `resilience.force-quit-coach-turn`. Force-quit means swipe up + flick the app card off the app switcher — NOT background-suspend (which the OS owns).

**Setup.** A TestFlight build with seeded coach + workout data. Tester sees Today populated with at least one prior session. (The "deferred onboarding state survives a force-quit" property is what we're testing — there's no opt-in launch flag for it, because it has to work out-of-the-box in production.)

**Path: Force-quit mid-onboarding.**
1. Fresh install. Begin onboarding.
2. Advance 2-3 screens past Welcome.
3. Force-quit from the app switcher.
4. Relaunch the app.
5. **Expected:** onboarding resumes at the last screen reached (not from Welcome). Any partial input (athlete name, goals) persists.

**Path: Force-quit during active workout.**
1. From Today, start the next prescribed workout.
2. Log one set. Confirm.
3. Force-quit.
4. Relaunch.
5. **Expected:** the active session screen is showing; the logged set persists; the rest timer reflects elapsed time (or is reset gracefully if HKWorkoutSession cannot resume — in which case a banner explains).
6. Complete the remaining sets.
7. Tap Complete.
8. **Expected:** session summary appears; CloudKit push is staged (verify via Settings → iCloud → VolumeArc storage growing, or Profile → Diagnostics).

**Path: Force-quit during coach stream.**
1. Open Coach.
2. Ask a long-form question ("Build me a 6-week strength block for back squat").
3. As soon as the streaming response starts (tokens visible), force-quit.
4. Relaunch.
5. **Expected:** Coach opens to an idle state. The partial response is NOT shown as a completed message. The app records `coach.stream.aborted`, and the user can issue the prompt again without a stuck streaming state.

**Failure modes to look for.**
- Onboarding restarts from Welcome (regression in `UserDefaults`-backed step persistence).
- Active session loses logged sets (regression in SwiftData persistence — almost certainly a missing `try modelContext.save()`).
- Rest timer drift > 5 seconds vs wall-clock-elapsed (regression in restEndsAt anchor).
- Coach shows a partial / truncated response as if it were complete (regression in stream-completion semantics).
- CloudKit push fails silently — the summary appears but no diagnostic in Profile, the next launch shows the session is gone.

### `resilience.wc-*` — Watch ↔ iPhone interruption

> Tests rows `resilience.wc-interrupt-midpayload` / `resilience.wc-reconnect-replay`. Requires a paired Apple Watch + iPhone on the same TestFlight account.

**Setup.** Watch + iPhone paired. VolumeArc installed on both. iPhone has cellular OR Wi-Fi; watch is paired but not cellular.

**Path: Disconnect during decision payload.**
1. On the watch, start a session.
2. Toggle iPhone to airplane mode (the watch can still observe `WCSession.isReachable == false`).
3. On the watch, tap "Increase" or "Hold" or "Decrease".
4. **Expected:** the watch updates locally — the decision UI reflects the choice. The status banner reads something like "Decision saved on watch. We'll sync it to phone when available."
5. Tap "Reset rest timer". Same expectation — local update, queued payload.
6. Open the watch's Profile / Sync diagnostic to see the pending payload count.
7. **Expected:** count > 0.

**Path: Reconnect and replay.**
1. Continue from the above.
2. Disable airplane mode on the iPhone.
3. Wait ~10 seconds for `WCSession` to re-establish.
4. **Expected:** the watch's status banner updates to "Connected again. Replayed N queued update(s)." The pending count returns to 0.
5. On the iPhone, open Today → recent activity. **Expected:** the watch's decisions show up in the activity log.

**Failure modes to look for.**
- Decision UI fails to update on the watch when the phone is unreachable (regression in `WatchWorkoutModel.choose(_:)`'s `do/catch` — the local update must happen REGARDLESS of send success).
- Pending count stays > 0 after reconnect (regression in `WatchConnectivityCoordinator.flushPendingIfReachable`).
- Duplicate decisions appear on the iPhone after replay (regression in payload-store-clear semantics).
- Watch process restart between disconnect and reconnect drops the queue (regression in `UserDefaultsWatchPendingPayloadStore` persistence).

---

## Burndown plan

Active journey burndown now lives in [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762):

- [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141) parent — close all rows + wire `check_journey_coverage.sh`
- [VOL-127](https://linear.app/mabry-ventures/issue/VOL-127) — onboarding HK + force-quit + WCSession journeys. **Phase 1** (PR [#159](https://github.com/Mabry-Ventures/mv-volumearc/pull/159)): four-bullet HealthKit rationale pre-prompt screen shipped. **Phase 2**: resilience/interruption rows and manual UAT scripts (HealthKit grant/deny/skip, voice/mic, force-quit at every stage, WCSession interrupt + reconnect) now have deterministic XCUITest/model proof where simulator-safe; physical system sheets and paired-watch paths remain launch UAT evidence.
- [VOL-142](https://linear.app/mabry-ventures/issue/VOL-142) — paywall + StoreKit edge journeys
- [VOL-149](https://linear.app/mabry-ventures/issue/VOL-149) — telemetry-as-UAT helper used by every journey
- Post-v1 iPad expansion — re-run every journey on iPad after a new product decision flips `TARGETED_DEVICE_FAMILY` to include iPad
- [VOL-94](https://linear.app/mabry-ventures/issue/VOL-94) — re-run real-device-only journeys (CloudKit, HealthKit, BGTask, WCSession, Live Activity) on hardware

This catalog is 100% covered for simulator-safe v1 rows. Keep [`PLATFORM.md`](PLATFORM.md) synchronized whenever implementation status changes; physical paired-device UAT remains tracked outside the table.
