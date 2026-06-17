# Release UAT Evidence

This file is the launch evidence manifest for physical-device and TestFlight-only journeys. It is intentionally separate from [`USER_JOURNEYS.md`](USER_JOURNEYS.md): the journey catalog proves simulator-safe coverage, while this file proves the hardware, OS, App Store Connect, APNs, HealthKit, WatchConnectivity, Live Activity, widget, and purchase paths that cannot be trusted from simulator automation alone.

`scripts/check_release_uat_evidence.sh` is blocking when `VOLUMEARC_RELEASE_READY=1`. Do not mark VolumeArc GA-ready until every required row below is `Pass` with concrete evidence for the exact TestFlight build under review.

## Build Evidence

| Field | Value |
|---|---|
| TestFlight build | Not run |
| App version | Not run |
| Commit SHA | Not run |
| TestFlight processing timestamp | Not run |
| Tester | Not run |
| iPhone model | Not run |
| iOS version | Not run |
| Apple Watch model | Not run |
| watchOS version | Not run |
| Pairing state | Not run |
| Apple ID / tester group | Not run |
| Sentry release | Not run |
| UAT date | Not run |

## Required Physical UAT

| Journey ID | Status | Evidence |
|---|---|---|
| `testflight.install-update` | Not run | Install or update from TestFlight; confirm version/build matches this manifest. |
| `onboard.healthkit-grant` | Not run | Fresh install, explicit Health rationale, system sheet grant, Today readiness populated, Diagnostics granted. |
| `onboard.healthkit-deny` | Not run | Fresh install, explicit Health rationale, system sheet deny, no re-prompt loop, fallback readiness and Diagnostics denied. |
| `onboard.healthkit-skip` | Not run | Fresh install, skip Health, onboarding continues, fallback readiness, explicit retry path only. |
| `onboard.voice-mic` | Not run | Premium account, real microphone and Speech Recognition sheets, voice session start and completion. |
| `permissions.notifications-explicit` | Not run | Notification prompt appears only after explicit rationale and tap, never immediately on first launch. |
| `profile.sign-in-with-apple` | Not run | Sign in with Apple succeeds, profile identity persists across reinstall or second device where available. |
| `profile.appearance-toggle` | Not run | System, light, and dark modes render correctly; warm brand personality remains visually consistent where productized. |
| `settings.diagnostics` | Not run | Diagnostics opens, warnings are understandable/actionable, export path works without leaking secrets. |
| `premium.purchase-restore` | Not run | Purchase, cancel, restore, and already-subscribed states behave correctly against StoreKit/App Store sandbox. |
| `workouts.builder-manual` | Not run | Build a workout manually, edit exercises/sets/load, assign or schedule it, start it. |
| `workouts.builder-coach` | Not run | Coach-recommended workout can be reviewed and started or scheduled without manual re-entry. |
| `workouts.active-edit` | Not run | During a session, edit weight, reps, sets, exercise order, and notes without leaving the workout. |
| `workouts.equipment-busy` | Not run | Equipment Busy suggests a safe substitute or resequence and preserves session state. |
| `workouts.skip-replace` | Not run | Skip and replace an exercise, including user-picked and coach-suggested replacement paths. |
| `workouts.exercise-diagram` | Not run | Exercise diagrams or cues open from the active session and match the selected exercise. |
| `resilience.force-quit-onboarding` | Not run | Force-quit mid-onboarding, relaunch resumes at the correct step with input preserved. |
| `resilience.force-quit-active-workout` | Not run | Force-quit during active workout, relaunch restores active session and logged set. |
| `resilience.force-quit-coach-turn` | Not run | Force-quit during stream, relaunch drops partial response and leaves Coach usable. |
| `watch.install-launch` | Not run | Watch app installs from TestFlight companion flow and launches on paired Apple Watch. |
| `watch.start-workout` | Not run | Start workout on Watch; HealthKit workout session starts and iPhone sees live state. |
| `watch.log-set` | Not run | Log sets on Watch with fast controls; iPhone receives persisted set state. |
| `watch.coach-cue` | Not run | Watch renders cue/haptic at the correct moment without crowding the workout controls. |
| `watch.action-decision` | Not run | Increase/Hold/Decrease updates local Watch state and next prescription. |
| `resilience.wc-interrupt-midpayload` | Not run | Disconnect iPhone during Watch payload; payload queues, UI explains saved-on-watch state. |
| `resilience.wc-reconnect-replay` | Not run | Reconnect iPhone; queued Watch payloads replay once, in order, without duplicates. |
| `notifications.delivery-tap` | Not run | APNs/TestFlight notification is delivered, tapped, and routes to the correct destination. |
| `widget.add-small` | Not run | Add small widget from SpringBoard gallery; renders current VolumeArc state. |
| `widget.add-medium` | Not run | Add medium widget from SpringBoard gallery; renders current VolumeArc state. |
| `liveactivity.start` | Not run | Start workout; Live Activity appears on lock screen with correct state. |
| `liveactivity.dynamic-island` | Not run | Dynamic Island expanded state renders correctly on supported iPhone hardware. |
| `liveactivity.end` | Not run | Complete workout; Live Activity ends and does not linger stale state. |
| `coach.safety-redflag-live` | Not run | Live coach path gives conservative stop/escalate guidance for current medical red-flag context. |
| `coach.recovery-live` | Not run | Live coach path recommends rest or light conservative work for sick/sore/tight prompts without guilt language. |
| `signals.readiness-prescription` | Not run | Signals explains readiness and the recommended workout visibly changes with readiness context. |

## Signoff

| Area | Status | Owner | Evidence |
|---|---|---|---|
| Product | Not run | Jared | Required journeys pass on the target TestFlight build. |
| Design | Not run | Design owner | Light, dark, warm brand personality, watch, widgets, and critical empty/error states reviewed. |
| Engineering | Not run | Apple platform owner | No crash, data-loss, sync, entitlement, release-config, or performance blockers remain. |
| AI safety | Not run | AI owner | Live eval trend and manual red-team prompts pass for the target relay/model routing. |
| Security/privacy | Not run | Security owner | Sentry, App Attest, privacy, dependency, and secret-scanning gates are green. |
