# Forensic Production-Readiness Audit — 2026-05-01 (re-scored 2026-05-09, 2026-05-26, 2026-06-06)

> **Source of truth:** [`PLATFORM.md`](PLATFORM.md) for current platform status and [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) for active launch execution. Historical audit sections remain for evidence; current burndown lives in [`VOLUMEARC_RELEASE.md`](VOLUMEARC_RELEASE.md), [`LINEAR_RELEASE_MIGRATION.md`](LINEAR_RELEASE_MIGRATION.md), and the VolumeArc Release Linear initiative.

## Score history

| Date | Composite | Repo hygiene | Docs | Test coverage | CI/CD | Agentic UAT | Driver |
|---|---|---|---|---|---|---|---|
| 2026-05-01 | **84** | 92 | 88 | 85 | 74 | 80 | Original audit. |
| 2026-05-09 | **88** | 93 | 86 | 86 | 86 | 81 | VOL-132 / 133 / 134 closed; VOL-126 / 128 / 129 / 137 / 161 closed; Sprint 1 SAST + toolchain + coverage-trend in flight (VOL-143 / 151 / 165 / 166). PLATFORM.md drift opened a small docs gap, closed by VOL-167 (this commit). |
| 2026-05-26 | **82** (engineering-weighted), **80** (user-visible-weighted) | 88 | 80 | 74 | 80 | 81 | Independent re-audit. Composite drop reflects re-weighting and 19 newly opened gaps (VOL-245 through VOL-263), not regressions. See [2026-05-26 re-audit](#2026-05-26-re-audit) below. |
| 2026-06-06 | **84** (launch-readiness, release-branch hardening update) | 90 | 84 | 72 | 86 | 73 | Claude Design export audit plus current release-branch verification. The branch now fixes and verifies the clean Apple build, release binary-hardening, simulator performance, Semgrep, TruffleHog, marketing supply-chain, relay gates, offline coach failure journeys, no-iCloud launch fallback proof, 401 session-refresh retry proof, Foundation Models unavailable fallback proof, Profile subscription-management, About-surface, and Session Profiles proof, HealthKit-unavailable Today fallback proof, onboarding HealthKit grant/deny fixture proof, Coach voice permission/session proof, Workouts rest-timer expiry proof, Workouts history delete proof, onboarding force-quit recovery proof, active-workout force-quit recovery proof, coach-stream force-quit recovery proof, Watch offline replay telemetry proof, WatchConnectivity queue/reconnect notice proof, background refresh/processing proof, background-task wake/relaunch idempotency proof, push-notification tap routing proof, widget small/medium render and embed proof, Live Activity state/telemetry/Dynamic Island render proof, co-design edited-prescription scheduling into Workouts, iOS light/dark/warm-brand plus light accessibility and light/dark/warm-brand glass dashboard-surface visual snapshots, and additional Watch wire-contract journey proof; the composite remains below launch because the latest committed coach response-eval trend is stale/failing, Claude visual parity is only partially snapshot-gated, and physical iPhone + paired Watch UAT is not complete. See [2026-06-06 Claude Design + launch-readiness audit](#2026-06-06-claude-design--launch-readiness-audit). |

## 2026-06-06 Claude Design + launch-readiness audit

### Executive verdict

**Verdict: no launch.** VolumeArc still looks like a serious, high-craft product, and the Apple-ecosystem wedge is real. This release branch fixes the clean Apple build gate, release binary-hardening failure, simulator performance baseline, security/supply-chain warning gates, the first full iOS light/dark/warm-brand dashboard-surface snapshot gate with light accessibility and light/dark/warm-brand glass variants, and 72/72 simulator-safe journey rows, but the repository still cannot be described as production-ready for a paid public launch because the latest tracked coach response-quality evidence is failing/stale, Claude visual parity is only partially snapshot-gated, and physical iPhone + paired Watch UAT remains unproven.

This audit used the supplied Claude Design export zip as the Claude Design reference package. The archive contains `tokens.css`, `app.jsx`, `screen-today.jsx`, `screen-workouts.jsx`, `screen-coach.jsx`, `screen-signals.jsx`, `screen-profile.jsx`, `screen-codesign.jsx`, `components.jsx`, `figures.jsx`, `ios-frame.jsx`, and the watch-face HTML/CSS exports. It does **not** contain a marketing-site Claude export, so marketing design parity is audited against `docs/MARKETING.md`, `docs/PRODUCT_POSITIONING.md`, the current `marketing/` implementation, and the shared app design language. Anthropic's Claude Design docs describe the `.zip` export as a supported handoff format for designs/prototypes, which matches the artifact shape supplied here: [Claude Design export docs](https://support.claude.com/en/articles/14604416-get-started-with-claude-design).

### Weighted scorecard

| Dimension | Weight | Score | Evidence-backed verdict |
|---|---:|---:|---|
| UI/UX parity to Claude Design | 20 | 16 | iOS tab inventory and Today surface mostly align; `DashboardSurfaceSnapshotTests` now regression-gates Today, Workouts idle, Workouts active, Coach planning, Signals, and Profile in light/dark/warm-brand plus light `.accessibility5` Dynamic Type and light/dark/warm-brand reduce-transparency-off glass passes with 42 committed baselines. `VADesignTokenParityTests` verifies Claude warm-personality brand colors against native `VA.Colors` in light/dark. Remaining gaps: co-design is implemented as an embedded Coach plan draft rather than the dedicated pushed screen in the export, native tab chrome drift needs signoff, and watch-face exports are represented as manifests/previews but no `.watchface` files are bundled. |
| Strength/conditioning UX | 10 | 8 | Core workout, readiness, Watch execution, rest, form-check, and planning primitives are present. Co-design schedule persistence and edited exercise prescription proof are now wired and tested from Today into Workouts. Remaining risk is proof: watch-first execution is not freshly validated on device, template saving remains intentionally unshipped, and Watch start/sync proof is still open. |
| Copy/product voice | 10 | 8 | Copy is materially better after VOL-247 and this release-branch cleanup: positioning, marketing metadata/FAQ/pricing/App Store copy, stale launch claims, emoji usage, and exact banned AI/provider-branding phrases now have explicit hygiene gates. Coach/paywall app surfaces and public marketing metadata use coach/cloud/safety language while legal/privacy/quality surfaces retain provider disclosure. The public `/quality` story still cannot be marketed because the latest trend is not green. |
| AI quality, routing, safety | 15 | 8 | Prompt architecture, redaction, App Attest relay, fallback, and 47-fixture eval design are strong. The release branch now pins premium routing to stable `gemini-3.5-flash` instead of `gemini-flash-latest`, while free/default remains stable `gemini-3.1-flash-lite` with a May 7, 2027 deprecation review requirement. Latest committed response trend is still 36/47 from 2026-05-27 and predates VOL-264/VOL-265 fixes; no post-fix 47/47 evidence exists in `docs/coach-eval-trend.json`. |
| Performance/resiliency | 10 | 8 | Simulator performance is green on the release branch, with `docs/performance-trend.json` populated from a passing run: cold launch 0.913s, Today scroll 2.48s, workout memory 77.013 MB, coach first-token P50 702.071ms, and P95 777.378ms. Physical iPhone + paired Watch UAT, WatchConnectivity replay proof, and tag/CI confirmation remain launch gates. |
| Security/privacy hardening | 10 | 9 | App Attest/PII posture is strong, Release now sets `COPY_PHASE_STRIP = YES` from the generator, Semgrep is clean and blocking after replacing deterministic MD5-derived project IDs with SHA-256-derived IDs, TruffleHog full-history scan is clean, marketing and relay dependency audits report 0 vulnerabilities, and marketing SBOM generation is blocking. Remaining work is CI ruleset enforcement proof and final privacy/legal signoff. |
| Code quality/elegance | 10 | 8 | Architecture and generated-project discipline remain above average; generated Xcode project determinism is green. Remaining debt: very large watch/model/catalog files with file-length disables and the need to keep the full Apple test suite green in CI after this branch. A previous audit note about duplicated co-design removal logic was rechecked and is not present in the current branch. |
| CI/test coverage | 10 | 8 | Apple build, Apple tests, coverage, release validation, Xcode determinism, simulator performance, marketing lint/legal/build/e2e/a11y/Lighthouse, relay tests/typecheck, Semgrep, TruffleHog, dependency audits, the dashboard-surface snapshot suite, the expanded Watch simulation suite, and 72/72 simulator-safe journey rows pass on the branch. Snapshot baselines now cover the six launch-critical iOS dashboard surfaces in light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand reduce-transparency-off glass variants, but not the full watch/widget matrix. |
| Docs/journeys | 5 | 4 | Active docs now point at VolumeArc Release and release hygiene blocks stale active project names, emojis, product-voice drift, placeholder legal/pricing copy, broken doc links, and unsupported launch claims. Journey catalog is 100% automated for simulator-safe v1 rows; physical device UAT evidence remains open. |
| Market fit/GTM | 10 | 7 | Option A ("deepest Apple-ecosystem strength coach") is still the right wedge. Competitive gaps vs Fitbod's library/video breadth, WHOOP's recovery moat, and Future's adaptive audio coaching require sharper claims, proof, and launch sequencing. |
| **Composite** | **100** | **84** | **No-launch until remaining P0/P1 launch gates are green or explicitly accepted by Jared, and every world-class scorecard category reaches 9.5+.** |

### P0/P1 launch findings and remediation status

| Severity | Status | Finding | Evidence | Required before launch |
|---|---|---|---|---|
| P0 | Fixed on release branch; needs CI merge proof. | Clean Apple target build failed before app compilation. | `scripts/hydrate_sentry_artifact.sh` now hydrates Sentry binary targets without deleting SwiftPM artifacts; `scripts/build_all_targets.sh` invokes `xcodebuild` from a fresh shell to avoid the Xcode 26.5 first-build artifact race. Verified: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build_all_targets.sh` passes, and the full `test_apple_targets.sh` run passes locally. | Merge only after CI repeats the build, Apple tests, coverage, and perf gates. |
| P0 | Fixed on release branch; needs CI merge proof. | Full release validation failed binary hardening. | `scripts/generate_xcode_project.rb` now sets `COPY_PHASE_STRIP = YES` for Release configs and regenerated `VolumeArcApple.xcodeproj/project.pbxproj`. Verified: full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/validate_release_config.sh` passes. | Keep the validator strict and require generated-project determinism on CI. |
| P0 | Open; app/relay safety hardened locally. | Coach response-quality evidence is stale and latest public trend is failing. | `docs/coach-eval-trend.json` latest record is `2026-05-27T03:00:00Z`, `36/47` passed, with medical red-flag escalation failures, banned PR mentions, and one empty response. This branch now short-circuits current medical red flags from the athlete question, message history, and current training context in both `CoachSafetyFilter` and `relay/src/worker.ts`, while avoiding negated or stale historical false positives. Verified locally with `CoachSafetyFilterTests`, local heuristic false-positive tests, and relay tests/typecheck. No post-fix green response trend exists yet. The local runner requires `VOLUMEARC_EVAL_ATTEST_BROKER_TOKEN` and a staging `VOLUMEARC_RELAY_BASE_URL`, and refuses production. | Run staging response evals after the prompt/relay fix, require 47/47 or documented acceptance for each failure, and publish the green trend to both `docs/coach-eval-trend.json` and `marketing/src/data/coach-eval-trend.json`. |
| P1 | Partially fixed on release branch. | Claude Design parity is only partially regression-gated. | `VolumeArc.zip` lives outside the repo; this branch adds `docs/DESIGN_PARITY.md`, `VADesignTokenParityTests`, `DashboardSurfaceSnapshotTests`, and 42 committed baselines covering Today, Workouts idle, Workouts active, Coach planning, Signals, and Profile in light/dark/warm-brand plus light `.accessibility5` Dynamic Type and light/dark/warm-brand reduce-transparency-off glass passes. Remaining gaps are native tab chrome drift signoff, watch-face/runtime watch parity, marketing export absence, widget expansion, and physical-device signoff. | Finish product-level visual gates for watch/widgets/marketing language and remaining variant proof; record accepted drift for native tab chrome, warm-as-brand-personality, and the embedded co-design flow. |
| P1 | Partially fixed on release branch. | Journey/UAT proof still needs physical-device evidence. | `./scripts/check_journey_coverage.sh` reports `72/72 (100%)`. The release branch adds deterministic offline coach fallback coverage, no-iCloud launch fallback proof, 401 safe-fallback proof, 401 session-refresh retry proof, Foundation Models unavailable fallback proof, Profile subscription-management, About-surface, Session Profiles, Appearance, and Diagnostics export proof, HealthKit-unavailable Today fallback proof, onboarding HealthKit grant/deny fixture proof, Coach voice permission/session proof, Workouts rest-timer expiry proof, Workouts history delete proof, onboarding force-quit recovery proof, active-workout force-quit recovery proof, coach-stream force-quit recovery proof, Watch offline replay telemetry proof, WatchConnectivity queue/reconnect notice proof, background refresh/processing proof, background-task wake/relaunch idempotency proof, push-notification tap routing proof, widget small/medium render and embed proof, Live Activity state/telemetry/Dynamic Island render proof, co-design scheduling proof, and additional Watch wire-contract proof. Paired Watch UAT is not complete. | Complete physical iPhone + paired Apple Watch UAT for HealthKit, WatchConnectivity, force-quit/resume, offline/reconnect, notifications, TestFlight, and permission-deny paths. |
| P1 | Fixed on release branch; needs CI/tag and physical UAT proof. | Performance trend and simulator budgets were not previously baselined. | `docs/performance-trend.json` now contains a passing release-branch run. Verified: `./scripts/test_performance.sh` passes and `./scripts/check_performance.sh` records cold launch 0.913s, Today scroll 2.48s, workout memory 77.013 MB, coach first-token P50 702.071ms, and P95 777.378ms. | Require CI/tag confirmation, keep budgets blocking for releases, and run physical iPhone + paired Apple Watch UAT for launch-speed and WatchConnectivity paths. |
| P1 | Fixed on release branch; needs CI ruleset proof. | Security/supply-chain gates were not launch-grade. | Semgrep now reports 0 findings after project UUID hashing moved from deterministic MD5 truncation to SHA-256 truncation; `.github/workflows/semgrep.yml` has no `continue-on-error`; marketing `npm audit --audit-level=moderate` reports 0 vulnerabilities after the `tmp` override; marketing SBOM generation is blocking; relay `npm audit --audit-level=high` reports 0 vulnerabilities; TruffleHog full-history scan exits 0 with zero findings. | Add `Semgrep scan`, `Trufflehog`, and marketing audit/SBOM jobs to required release branch/ruleset gates and keep exceptions owner-approved only. |

### Claude Design parity matrix

| Surface | Claude Design source | Current implementation | Parity verdict | Launch action |
|---|---|---|---|---|
| Shared tokens | `tokens.css` | `VolumeArcNative/Sources/VolumeArcUI/DesignSystem/Tokens.swift`, `Watch/VADesignTokens.swift`, `marketing/src/styles/tailwind.css`, `VADesignTokenParityTests.swift` | Strong base parity for warm sunrise palette and typography. `VADesignTokenParityTests` verifies the Claude warm-personality brand palette against native light/dark dynamic colors. Claude export still has non-v1 prototype controls (`teal`, `mono`, `dense`, `balanced`, `spacious`) that are not productized. | Keep warm as the v1 production brand personality unless Jared intentionally reopens alternate personalities/density as product scope. |
| iOS app shell | `app.jsx`, `ios-frame.jsx` | `RootDashboardView.swift`, `DashboardSurfaceSnapshotTests.swift` | Five-tab inventory matches: Today, Workouts, Coach, Signals, Profile. Dashboard-surface snapshots now cover all six launch-critical iOS app surfaces in light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand reduce-transparency-off glass variants. Chrome differs: Claude uses a floating Liquid Glass tab pill; app uses native SwiftUI `TabView` with `.tint(VA.Colors.primary)`. | Decide whether native tab chrome is an intentional platform choice or a parity miss, then record the accepted-drift note. |
| Today | `screen-today.jsx` | `TodayView.swift`, `DashboardSurfaceSnapshotTests.swift` | Mostly aligned and now light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand glass snapshot-gated: greeting, avatar, next-workout hero, plan tomorrow, coach briefing, readiness/volume cards, recent sessions. App adds `VARecoveryChip`, which strengthens the Apple-data wedge. | Add additional seeded readiness-state variants. |
| Co-design/planning | `screen-codesign.jsx` | `CoachView.swift`, `CoachPlanningComponents.swift`, `WorkoutDashboardModel+TrainingPrograms.swift`, `WorkoutsView.swift` | Functionally improved. The plan draft, chips, exercise editing, swap/move/remove, refine/schedule/start actions exist. Schedule now persists tomorrow's edited co-designed prescription into the weekly plan, refreshes the dashboard, and surfaces it on Workouts with an exercise preview. Flow still differs: Claude pushes a dedicated planning screen from Today; app reveals a plan card inside Coach. Template saving is not shipped and was renamed to `Refine plan`. | Finish the flagship journey by deciding whether to match the pushed screen pattern and proving Watch start/sync from the scheduled plan. |
| Workouts | `screen-workouts.jsx` | `WorkoutsView.swift`, `WorkoutDetailView.swift`, `DashboardSurfaceSnapshotTests.swift` | Idle and active Workouts states are now light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand glass snapshot-gated; implementation appears feature-rich and the Apple build is green on this branch. | Add rest/edit/complete/interruption/resume variants and run UAT for set logging speed, rest states, edits, completion, interruption, and resume. |
| Coach | `screen-coach.jsx` | `CoachView.swift`, `VACoachBubble`, `CoachPromptTemplate`, `DashboardSurfaceSnapshotTests.swift` | Co-design planning is now light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand glass snapshot-gated, and copy/architecture are strong. Everyday Coach and paywall copy now avoids model/provider naming and frames the experience as coach judgment, secure cloud processing, and safety. | Re-audit response wording after live evals are green; keep provider disclosure in legal/privacy surfaces, not daily workflow headers. |
| Signals | `screen-signals.jsx` | `SignalsView.swift`, `DashboardSurfaceSnapshotTests.swift` | Seeded Signals surface is now light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand glass snapshot-gated. Existing journeys cover only part of Signals. | Add recovery detail, no-permission, empty, and trend-interpretation variants plus journey tests. |
| Profile | `screen-profile.jsx` | `ProfileView.swift`, paywall, settings, watch faces, `DashboardSurfaceSnapshotTests.swift` | Seeded Profile surface is now light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand glass snapshot-gated. Watch-face entry exists, but installability depends on bundled `.watchface` exports that are absent. | Add settings/legal/pricing/watch-face installability variants; finalize App Store/legal/pricing copy. |
| Watch faces | `VolumeArc Watch Faces*.html`, `watchface-styles.css` | `WatchFacePack.swift`, `WatchFacePackView.swift`, `WatchFacePreview`, `Tests/VolumeArcAppTests/WatchFacePackTests.swift` | Manifest and preview parity are good. Launch parity is incomplete: no `.watchface` files are bundled under `App/WatchFaces`, and the current tests intentionally assert no presets are bundled. | Obtain Apple-generated `.watchface` exports or keep the install row hidden/disabled and avoid launch claims about installable faces. |
| Watch workout/Smart Stack | No direct Claude runtime screen export; watch-face CSS only | `Watch/WatchWorkoutView.swift`, `WatchAlwaysOnWorkoutView.swift`, `WatchWidgets/VolumeArcSmartStackWidget.swift` | Runtime watch execution appears deep, but not covered by the supplied Claude export. | Audit against watchOS best practices and physical-device UAT rather than design-export parity. |
| Marketing | No Claude marketing export in `VolumeArc.zip` | `marketing/` Next.js site | Caveat: no design-file parity source was supplied. Site should be judged against app tokens, product positioning, and current browser/a11y/Lighthouse checks. | Record "missing Claude marketing design export" as an input gap; do not block on parity unless a marketing export appears. |

### Product/UX and copy findings

| Severity | Finding | Evidence | Risk | Recommendation |
|---|---|---|---|---|
| P1 | Co-design is partially proven, but not yet a complete flagship planning workflow. | Claude export makes planning a dedicated chat-first screen. The branch now wires `Schedule` to `SwiftDataTrainingPlanRepository`, publishes the weekly plan through `DashboardRefreshSnapshot`, surfaces the scheduled tomorrow card in Workouts, validates Today -> Plan tomorrow -> Schedule -> Workouts, and validates swap/move/set-adjust/remove before scheduling the edited prescription. | Users can now schedule an edited plan, but launch claims remain risky until dedicated/pushed-screen parity, template strategy, and Watch start/sync are proven. | Decide dedicated screen parity, choose the template strategy, and prove scheduled-plan start/sync on Watch. |
| P2 | Product positioning required release reconciliation. | `docs/PRODUCT_POSITIONING.md` now reflects VolumeArc Release, Fitbod/WHOOP/Future as primary release competitors, and the current Apple-native wedge. | GTM and App Store copy can still drift if screenshots, pricing, and claims are not locked from the same source. | Keep positioning tied to VOL-273/VOL-276 and re-check competitor sources before final screenshots and launch pages lock. |
| P2 | Marketing legal docs needed clearer status language. | `docs/MARKETING.md` and `marketing/README.md` now distinguish "placeholder-free page exists" from "legal counsel approval pending"; `npm run check:legal` remains the automated guard. | Contributors may still misreport App Store readiness if legal counsel approval is implied by a passing placeholder check. | Treat counsel approval and App Store metadata parity as release gates under VOL-273. |
| P2 | Pricing and paywall copy need final App Store Connect signoff. | `marketing/src/components/Pricing.tsx` now removes placeholder/TODO language and uses capability-first copy, but the displayed prices still require ASC product confirmation. | Paid-product conversion, App Review metadata, and paywall copy can drift. | Confirm StoreKit/App Store Connect pricing and keep paywall, marketing, screenshots, and metadata aligned. |
| P3 | Audit correction: duplicate co-design removal call is not present. | Rechecked `CoachPlanningComponents.swift`; `removeExercise(_:)` calls `plan.exercises.removeAll` once in the current branch. | No current runtime risk from this previously listed smell. | Keep row-action tests in scope for VOL-275, but do not track this as an active blocker. |

### AI deep dive

| Area | Verdict | Evidence | Launch action |
|---|---|---|---|
| Cloud coach relay | Strong architecture, unproven latest quality. | `relay/src/worker.ts` enforces App Attest/eval broker paths, request body binding, rate limit, Gemini streaming, safety settings, and deterministic current-context medical red-flag short-circuiting; relay tests pass `29/29`. | Keep architecture; rerun live staging evals after every prompt/model change. |
| Model routing | Branch-pinned; needs live eval/cost proof. | `relay/wrangler.toml` and `relay/wrangler.staging.toml` set `MODEL_DEFAULT = "gemini-3.1-flash-lite"` and `MODEL_PREMIUM = "gemini-3.5-flash"`. Google currently lists `gemini-3.5-flash` as stable, says most production apps should use a specific stable model, and documents `latest` aliases as hot-swapped; `gemini-3.1-flash-lite` has a May 7, 2027 shutdown date. Sources: [Gemini models](https://ai.google.dev/gemini-api/docs/models), [Gemini deprecations](https://ai.google.dev/gemini-api/docs/deprecations). | Run live staging response evals, record latency/cost data, and add a dated deprecation owner for Flash-Lite before launch. |
| Safety | App/relay locally hardened; must still be proven green with live evals. | `CoachPromptTemplate` now has a strong safety override. `CoachSafetyFilter` also buffers symptom prompts/current symptom context before streaming, replaces unsafe push/heavy/grind language with rest-first light-training guidance, and preserves medical red-flag escalation. `relay/src/worker.ts` mirrors the current-context medical red-flag boundary before model routing so cloud streams cannot emit a risky first chunk for known current symptoms. Latest published trend predates these fixes and failed red-flag medical escalation. | Require 47/47 response eval pass or explicit owner acceptance; add manual red-team prompts for pain, dizziness, chest pain, pregnancy, eating-disorder language, minors/max attempts, and prompt injection. |
| Privacy redaction | Good, with disclosed limits. | `PromptPrivacyRedactor` scrubs strict-mode email/phone/address/name patterns and documents best-effort scope; relay App Attest is strong. | Add sampled privacy redaction evals to the AI test plan and legal copy review. |
| Fallbacks | Good architecture, with better journey proof. | `FallbackCoachProvider` falls back before any streamed chunk on relay/network/auth/5xx failures and emits telemetry. XCUITests now cover relay 5xx, offline relay fallback with visible banner, 401 safe local fallback, and the one-shot 401 session-refresh retry path. | Add timeout and partial-stream-drop journeys. |
| In-product presence | Improved on release branch. | App has subtle planning/readiness integration, and Coach/paywall app surfaces now avoid provider branding in day-to-day copy. Safety copy says secure cloud processing and medical-disclaimer language; legal/privacy surfaces keep provider disclosures. | Recheck generated coach responses and marketing copy after live evals are green so the product voice stays coach-first. |

### Competitor matrix

| Capability | VolumeArc current evidence | Fitbod | WHOOP | Future | Launch implication |
|---|---|---|---|---|---|
| Strength plan personalization | Progression engine, coach, curated programs, readiness context. Needs response eval and UAT proof. | App Store claims personalized AI workouts, adaptive AI, non-linear periodization, 1000+ exercises, video demos, Apple Health/Strava/Fitbit/Watch integrations, and 273K ratings at 4.8. Source: [Fitbod App Store](https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543). | Less focused on traditional lifting plans but owns recovery/strain context and strength-muscular-load story. | App Store claims adaptive, data-driven training with real-time feedback, instant adjustments, audio guidance, Apple Watch integration, and HealthKit. Source: [Future App Store](https://apps.apple.com/us/app/future-personalized-workouts/id6744624390). | VolumeArc should not claim broadest planner. Claim Apple-native, privacy-first strength coaching with proof. |
| Exercise library/media | Curated catalog/programs exist, but no 1000-exercise/video moat. | Clear breadth moat: 1000+ exercises with hi-res, multi-angle videos. | Not the direct exercise-library competitor. | Video demos/audio cues are part of its app-store pitch. | Launch with curated quality, not breadth. Add "why this exercise" and form cues before trying to out-Fitbod Fitbod. |
| Recovery/readiness prescription | HealthKit recovery prompt and Today chip exist; no fresh full UAT/perf proof. | Recovery and exercise tracking claims exist but not WHOOP-depth. | WHOOP's 2026 updates include Strava strength import details and WHOOP AI exercise linking after lifting for muscular-load breakdown. Source: [WHOOP 2026 updates](https://www.whoop.com/us/en/thelocker/2026-whats-new/). | Claims holistic Apple Watch/HealthKit performance view. | VolumeArc's strongest wedge is "what Apple did for you" inside strength decisions. Make this the first-run aha. |
| Watch-first execution | Watch app, Smart Stack, Live Activity, Action Button, voice, HealthKit workout session. Build is green on the branch; paired-device UAT remains open. | Apple Watch support. | Native wearable is WHOOP's core hardware relationship. | Apple Watch integration is explicit. | Must prove physical paired-watch execution before paid launch. |
| AI quality transparency | Public `/quality` page exists, but latest trend is stale/failing. | No public eval transparency found in official app-store listing. | WHOOP AI is surfaced in product updates. | AI/adaptive coaching is the positioning. | Public quality can be a differentiator only after it is green. A failing public record is worse than no record. |
| Human coach | Not a v1 goal. | Pro trainer email support in app-store copy. | Not positioned as human-coach. | Coach/support expectations are central in its copy. | Do not compete head-on with Future on human coaching. Win on Apple-native automation and low-friction price. |

### GTM claim/proof map

| Claim | Proof today | Gap | Recommendation |
|---|---|---|---|
| "The deepest Apple-ecosystem strength coach." | HealthKit, WatchConnectivity, Watch app, Widgets, Live Activities, App Intents, CloudKit, Liquid Glass tokens, a green branch build, a green simulator performance trend, Claude warm token proof, and light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand glass dashboard-surface snapshots. | Watch physical UAT, TestFlight proof, watch visual parity, and final accepted-drift signoff are not complete in this audit. | Keep as the primary claim, but launch only after paired-watch UAT, CI/tag perf confirmation, final visual signoff, and TestFlight pass. |
| "Your readiness changes today's prescription." | `VARecoveryChip`, recovery prompt context, progression engine, coach prompt template. | Need end-to-end screenshots and user journeys that show the prescription changing with readiness. | Lead screenshots with Watch + readiness + prescription, not generic chat. |
| "AI is experienced, not in your face." | Planning/readiness surfaces embed coach behavior, and release-branch app copy now uses "coach", "readiness", "prescription", "signals", and secure cloud/safety language instead of daily provider branding. | Public trend is failing/stale, and marketing still needs final review against live eval proof. | Keep provider disclosure in legal/privacy surfaces; do not market coach-quality proof until response evals are green and current. |
| "Private by default." | App Attest, strict-mode redaction, Sentry scrubber, no ad/analytics SDK posture. | Legal counsel review and redaction evals must be current. | Keep, but attach concrete privacy copy to App Store nutrition and legal pages. |
| "Public coach-quality evidence." | `/quality` page and trend files exist. | Latest record is 36/47 and stale. | Do not market this page until post-fix response evals are green and updated. |
| "Premium is worth paying for." | StoreKit/paywall wired, Pro unlocks premium coach/voice path. | Pricing confirmation and full purchase/UAT proof are not complete in this audit. | Confirm pricing, paywall copy, App Store products, refunds/grace/ask-to-buy tests. |

### Linear-ready ticket drafts

#### 1. Fix clean Apple build Sentry artifact hydration

- **Severity:** P0
- **Launch gate:** Yes
- **Evidence:** Previously `./scripts/build_all_targets.sh` under `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` exited 65 with missing `.build/derived-data/SourcePackages/artifacts/sentry-cocoa/Sentry/Sentry.xcframework`; this branch adds `scripts/hydrate_sentry_artifact.sh`, keeps SwiftPM binary artifacts by default, and invokes `xcodebuild` from a fresh shell.
- **User/business risk:** No credible CI/local release path; app tests, coverage, perf, and archive validation cannot be trusted.
- **Recommended fix:** Land the release-branch build-script/hydrator fix and let CI prove it from a clean runner.
- **Acceptance criteria:** Fresh clone or cleaned `.build/derived-data/SourcePackages/artifacts` can run `./scripts/build_all_targets.sh` successfully.
- **Tests:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build_all_targets.sh`; rerun `./scripts/test_apple_targets.sh`.
- **Owner area:** Apple build/CI.

#### 2. Enforce Release `COPY_PHASE_STRIP = YES`

- **Severity:** P0
- **Launch gate:** Yes
- **Evidence:** Previously full `./scripts/validate_release_config.sh` failed with `COPY_PHASE_STRIP is NO in Release — must be YES`; this branch patches `scripts/generate_xcode_project.rb`, regenerates the Xcode project, and full validation now passes.
- **User/business risk:** Release binary may ship with debug symbols/nested artifacts not stripped as intended; the release validator is correctly blocking.
- **Recommended fix:** Land the generator fix and keep the validator strict.
- **Acceptance criteria:** Full validator passes with no `COPY_PHASE_STRIP` failure and generated project remains deterministic.
- **Tests:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/validate_release_config.sh`; project determinism test if available; `git diff` confirms generated-only changes.
- **Owner area:** Apple build/release hardening.

#### 3. Publish post-fix green coach response evals

- **Severity:** P0
- **Launch gate:** Yes
- **Evidence:** Latest `docs/coach-eval-trend.json` is `36/47` on `2026-05-27T03:00:00Z`, with red-flag and prompt-injection failures. App-side `CoachSafetyFilter` and relay-side deterministic safety now short-circuit current medical red flags from the athlete question, message history, and current training context while avoiding negated/stale historical false positives; verified locally with `CoachSafetyFilterTests`, local heuristic false-positive tests, and relay tests/typecheck. No newer green response trend exists.
- **User/business risk:** Unsafe or low-quality coach guidance can directly harm trust and safety; a public quality page showing failing red-flag handling undermines the product.
- **Recommended fix:** Configure/verify staging eval broker secrets, run full response-layer evals after current prompt/model routing, fix any residual failures, and commit the green trend.
- **Acceptance criteria:** `docs/coach-eval-trend.json` and `marketing/src/data/coach-eval-trend.json` latest record is 47/47 or every accepted failure has owner sign-off and visible rationale.
- **Tests:** `VOLUMEARC_RELAY_BASE_URL=<staging> VOLUMEARC_EVAL_ATTEST_BROKER_TOKEN=<secret> ./scripts/run_coach_evals.sh`; manual red-team prompts for safety/privacy/model-routing.
- **Owner area:** AI/relay/product safety.

#### 4. Complete Claude Design visual parity gate

- **Severity:** P1
- **Launch gate:** Yes for visual/copy launch signoff
- **Evidence:** `VolumeArc.zip` contains the source Claude design package. This branch adds `docs/DESIGN_PARITY.md`, `VADesignTokenParityTests`, `DashboardSurfaceSnapshotTests`, and 42 committed baselines for Today, Workouts idle, Workouts active, Coach planning, Signals, and Profile in light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand reduce-transparency-off glass variants. Remaining gaps are native tab chrome accepted drift, watch-face/runtime watch parity, marketing export absence, widget expansion, and physical-device signoff.
- **User/business risk:** Premium UX can regress or diverge from design intent without CI catching it.
- **Recommended fix:** Finish the docs/design parity manifest and screenshot/snapshot baselines for the remaining Claude iOS/watch surfaces, with explicit accepted deviations.
- **Acceptance criteria:** Every supplied Claude surface has a corresponding implementation screenshot, owner verdict, accepted-drift note, and regression test or manual signoff checklist across required modes and accessibility variants.
- **Tests:** SnapshotTesting baselines for seeded SwiftUI states; Playwright/image capture for design export references if kept as HTML.
- **Owner area:** Design systems/iOS UI/watch UI.

#### 5. Complete paired iPhone and Apple Watch UAT

- **Severity:** P1
- **Launch gate:** Yes
- **Evidence:** `./scripts/check_journey_coverage.sh` reports `72/72 (100%)`; paired iPhone + Apple Watch UAT remains unchecked.
- **User/business risk:** App Store reviewers and paid users will find gaps in permission-deny, offline, force-quit/resume, WatchConnectivity, and notification flows.
- **Recommended fix:** Run a physical iPhone + paired Apple Watch UAT checklist on TestFlight, with launch checklist evidence for device/OS/build identifiers.
- **Acceptance criteria:** UAT checklist includes device/OS/build identifiers and proves HealthKit, WatchConnectivity, force-quit/resume, offline/reconnect, notifications, TestFlight, and permission-deny paths.
- **Tests:** `./scripts/check_journey_coverage.sh`; relevant XCUITests; manual UAT evidence for hardware-only paths.
- **Owner area:** QA/UAT/Apple platform.

#### 6. Keep performance trend green and prove physical-device speed

- **Severity:** P1
- **Launch gate:** Yes
- **Evidence:** `docs/performance-trend.json` now has a successful release-branch run. Verified metrics: cold launch 0.913s, Today scroll 2.48s, workout memory 77.013 MB, coach first-token P50 702.071ms, and P95 777.378ms.
- **User/business risk:** Cold launch, Today scroll, memory, and first-token latency can regress invisibly.
- **Recommended fix:** Keep the trend file append-only, require CI/tag confirmation, and add physical iPhone + paired Apple Watch launch-speed and WatchConnectivity replay evidence.
- **Acceptance criteria:** `docs/performance-trend.json` contains the current release baseline, `check_performance.sh` passes within budgets on CI/tag, and physical UAT records no launch/logging/replay regressions.
- **Tests:** `./scripts/test_performance.sh`; `PERF_SKIP_TREND_WRITE=1 ./scripts/check_performance.sh`; `./scripts/check_performance.sh`; CI tag perf gate; physical-device UAT.
- **Owner area:** Performance/CI.

#### 7. Keep SAST and dependency audit launch-grade gates blocking

- **Severity:** P1
- **Launch gate:** Yes
- **Evidence:** Semgrep reports 0 findings after deterministic Xcode project IDs moved from MD5 truncation to SHA-256 truncation. `.github/workflows/semgrep.yml` and `.github/workflows/marketing.yml` now block on Semgrep, marketing `npm audit --audit-level=moderate`, and marketing SBOM generation. `cd marketing && npm audit --audit-level=moderate` reports 0 vulnerabilities, `cd relay && npm audit --audit-level=high` reports 0 vulnerabilities, and TruffleHog full-history scan exits 0 with zero result rows.
- **User/business risk:** If required-status checks are not wired to the repository ruleset, a future security or supply-chain regression can still merge despite clean local evidence.
- **Recommended fix:** Add the promoted Semgrep, TruffleHog, marketing audit/SBOM, and relay audit checks to the required release ruleset and keep every exception owner-approved.
- **Acceptance criteria:** CI fails hard on SAST, secret-scan, and dependency-audit findings unless Jared explicitly accepts the exact exception.
- **Tests:** Semgrep CI-equivalent command; TruffleHog full-history scan; `cd marketing && npm audit --audit-level=moderate`; `cd marketing && npm sbom --sbom-format=cyclonedx`; `cd relay && npm audit --audit-level=high`; marketing CI.
- **Owner area:** Security/CI/marketing.

#### 8. Finalize pricing, legal, and marketing copy status

- **Severity:** P2
- **Launch gate:** Yes for App Store submission
- **Evidence:** Pricing and legal copy are now placeholder-free in repo docs/surfaces, but VOL-273 still owns App Store Connect price confirmation, legal counsel approval, and final paywall/marketing/App Store metadata parity.
- **User/business risk:** Pricing/legal mismatches can trigger App Review rejection or reduce conversion trust.
- **Recommended fix:** Confirm App Store Connect products/prices, update paywall/marketing/App Store copy, and reconcile docs to "placeholder-free, legal-review pending."
- **Acceptance criteria:** No pricing TODOs, legal pages approved by counsel, App Store metadata matches in-app paywall and public site.
- **Tests:** `cd marketing && npm run check:legal && npm run lint && npm run build && npm run test:e2e && npm run test:a11y && npm run test:lighthouse`; release metadata validator with `VOLUMEARC_RELEASE_READY=1`.
- **Owner area:** Product/marketing/legal.

#### 9. Prove pinned model routing and deprecation policy

- **Severity:** P2
- **Launch gate:** Yes for AI launch confidence
- **Evidence:** The release branch pins `MODEL_PREMIUM = "gemini-3.5-flash"` and keeps `MODEL_DEFAULT = "gemini-3.1-flash-lite"` in both production and staging Wrangler configs. Google docs list `gemini-3.5-flash` as stable and say most production apps should use a specific stable model; `gemini-flash-latest` is a hot-swapped alias. `gemini-3.1-flash-lite` has a May 7, 2027 shutdown date.
- **User/business risk:** Premium tier quality/cost can still be wrong if the selected model is not proven by staging evals; Flash-Lite deprecation can cause repeat upstream 404 incidents if unmonitored.
- **Recommended fix:** Run the full staging response eval suite against the pinned routing, capture latency/cost by tier, and add a deprecation-review owner/date for Flash-Lite.
- **Acceptance criteria:** `docs/AI_MODEL_ROUTING.md` records final tier -> model -> reason -> cost/perf expectation -> fallback; live evals are green for selected models; deprecation owner/date is set.
- **Tests:** Relay unit tests; staging response evals per tier; latency/cost smoke.
- **Owner area:** AI/relay/product.

#### 10. Prove co-design persistence and scheduling

- **Severity:** P2
- **Launch gate:** Yes if co-design is a launch screenshot/claim
- **Evidence:** Claude export positions co-design as a primary screen. The branch now implements `scheduleCoDesignedWorkoutForTomorrow(...)`, publishes `weeklyPlan` through the dashboard snapshot, shows `workouts.scheduledTomorrow`, and validates both persistence and UI with `VolumeArcDashboardIntegrationTests.testScheduleCoDesignedWorkoutForTomorrowPersistsPlanAndEmitsTelemetry`, `VolumeArcTodayJourneyTests.testTodayPlanTomorrowSchedulesCoDesignedDraftIntoWorkouts`, and `VolumeArcTodayJourneyTests.testTodayPlanTomorrowEditsExerciseRowsBeforeScheduling`.
- **User/business risk:** Lower than before because scheduling now mutates the user's plan with edited exercise details, but a launch screenshot can still overpromise if template saving, dedicated-screen parity, and Watch start/sync are not proven.
- **Recommended fix:** Keep the schedule path, retain `Refine plan` instead of a fake template action until a template library exists, and prove Watch start/sync.
- **Acceptance criteria:** User can schedule tomorrow's plan, see it in Workouts/Today/Watch, edit/swap plan details, and start it from iPhone and Watch. Template save either ships as a real library feature or remains absent from launch copy.
- **Tests:** Unit tests for plan mutation; XCUITest schedule journey; row-edit/swap/move/remove journey; WatchConnectivity payload check.
- **Owner area:** Product/iOS workouts/AI planning.

### Evidence appendix

| Check | Result |
|---|---|
| `git status --short --branch` before edits | `## main...origin/main`, with pre-existing `M CLAUDE.md` and `?? AGENTS.md`. |
| Claude Design export | Extracted `VolumeArc.zip` to `.build/audit/claude-design`; 17 files including iOS tab JSX, co-design JSX, watch-face HTML/CSS, tokens, components, and figures. |
| Xcode availability | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version` -> Xcode 26.5 (17F42); iOS/watchOS 26.5 simulators available. |
| Static release config | `./scripts/validate_release_config.sh --no-build` passes. |
| Full release config | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/validate_release_config.sh` passes after the generator sets `COPY_PHASE_STRIP = YES` for Release. |
| Apple build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build_all_targets.sh` passes after Sentry artifact hydration and the fresh-shell `xcodebuild` wrapper. |
| Apple tests/coverage/perf | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test_apple_targets.sh` passes. The 2026-06-06 full run passed app unit/integration tests, smoke UI, journeys-core, journeys-aux, and accessibility-screenshot shards; the only skip is the existing VOL-230 simulator StoreKit limitation. `./scripts/check_coverage.sh` passes with VolumeArcCore line coverage at 82.5% against the 80% threshold; `./scripts/test_performance.sh` passes; `./scripts/check_performance.sh` appends a green trend row. |
| Journey coverage | `72/72 (100%, threshold: 100%)`; simulator-safe v1 journey rows are fully paired to tests and the parser now blocks regressions by default. |
| Coach response eval trend | Latest committed trend: `36/47` passed, 11 failed, timestamp `2026-05-27T03:00:00Z`, predating post-failure safety prompt fixes. |
| Marketing install/audit | `npm ci`, `npm audit --audit-level=moderate`, and `npm sbom --sbom-format=cyclonedx` pass; the `tmp` transitive advisory is resolved by the lockfile override. |
| Marketing functional checks | `npm run lint`, `npm run check:legal`, `npm run build`, `npm run test:e2e`, `npm run test:a11y`, and `npm run test:lighthouse` pass. Browser smoke verified desktop, pricing anchor, and mobile navigation on `http://localhost:3010`. |
| Relay checks | `npm ci` reports 0 vulnerabilities; `npm test` passes 22/22; `npm run typecheck` passes; `npm audit --audit-level=high` reports 0 vulnerabilities. |
| Semgrep | CI-equivalent Semgrep command completes with 0 findings after the deterministic project-ID hashing fix. |
| TruffleHog | Full-history local scan exits 0 with zero result rows. |
| ASC key / Fastlane auth | `/Users/jaredmabry/Downloads/AuthKey_YR7UQCU7GN.p8` exists, was never read or printed, and is now owner-only (`chmod 600`). `fastlane/Fastfile` now builds the App Store Connect API key object in memory from `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and the raw `.p8` path instead of passing a `.p8` as `api_key_path`. Homebrew Ruby 4 + Bundler 4.0.10 are installed locally; `bundle exec fastlane lanes` passes with Fastlane usage analytics disabled. |
| Live AI evals | Not run locally because staging eval broker secrets are required. |
| Physical UAT | Not run in this audit; remains required for iPhone + paired Apple Watch launch approval. |

### Two weightings, two scores (2026-05-26)

The May 1 / May 9 composite math weights every dimension equally. That's defensible as an *engineering-quality* scorecard. As a *ship-to-public* scorecard it overweights repo hygiene and underweights copy + user-visible signal. The 2026-05-26 audit publishes two numbers:

| Weighting | Repo hygiene | Docs | Test coverage | CI/CD | Perf/observability | Copy | Composite |
|---|---|---|---|---|---|---|---|
| Engineering-quality (equal) | 0.20 | 0.20 | 0.20 | 0.20 | 0.20 | — | **82/100** |
| User-visible (re-weighted) | 0.10 | — | 0.25 | 0.20 | 0.15 | 0.30 | **80/100** |

The engineering scorecard is what the team has been tracking. The user-visible scorecard is what predicts App Store reviews. Both belong on this page.

## TL;DR (May 9)

**Composite historical readiness score: 88/100.** Wave 1 ("App Store submission-prep") was ~70% closed and the launch chain shipped end-to-end (rc26 / Build 11 verified by Jared on May 6, modulo two remaining Info.plist runtime config gaps that were the subject of PRs #132–#143). Sprint 1 of the May 9 plan was in flight to push CI hygiene from 74 to high-80s before broad test-discipline work began.

**Three remaining gaps (May 9) that move the verdict from "ship-quality" to "world-class":**

1. **Snapshot / visual regression coverage** — VOL-135 still backlog. Liquid Glass + paywall + onboarding + coach bubble + Live Activity all regress invisibly. Single biggest test-discipline gap.
2. **100% user-journey XCUITest coverage** — VOL-141 still at 15% (9 / 62). The `scripts/check_journey_coverage.sh` gate referenced in `USER_JOURNEYS.md` is not yet wired.
3. **App Store metadata + legal pages content** — VOL-124 / VOL-125 still backlog. Reviewer-blocking; pre-1.0 pre-submit work.

## TL;DR (May 1, original)

**Composite production-readiness score before this project: 84/100.** VolumeArc is in the top decile of indie / small-team Apple-platform engineering. The PLATFORM/FEATURES/RELEASE doc discipline, [`scripts/validate_release_config.sh`](../scripts/validate_release_config.sh), the eval harness, the accessibility automation, and the Ruby-generated deterministic project are above the bar of teams with 10× the headcount. But specific, tractable gaps stand between "could be submitted to App Store" and "should be submitted with confidence."

| Dimension | Score | One-line verdict |
|---|---|---|
| Repo hygiene | 92 | Exemplary; one missing `Gemfile.lock`, missing root README/LICENSE/SECURITY |
| Documentation alignment | 88 | Source-of-truth pattern works; two minor doc-vs-code drifts; no SECURITY.md |
| Test coverage | 85 | 356 test functions, 80% Core gate enforced, 20-fixture eval matrix; missing snapshot tests, HK & CK mocks, dedicated Watch/Widget targets |
| CI/CD pipeline | 74 | Strong release validation; **critical fork-isolation gap on self-hosted runner**, AI review gate is advisory, no SAST/secret scanning, no dSYM auto-upload |
| Agentic UAT & automation | 80 | Best-in-class accessibility + hermetic fixture seeding + LLM eval harness; missing visual regression, response-eval CI, A/B framework, no in-app feedback |

**Three things that would change the verdict to "world-class, ship now":**
1. **~~Add a fork-PR guard on the self-hosted runner~~** — [VOL-132](https://linear.app/mabry-ventures/issue/VOL-132) Done closed 2026-05-03
2. **~~Promote the AI review gate from advisory to required~~** — [VOL-134](https://linear.app/mabry-ventures/issue/VOL-134) Done closed (audit error correction — already enforced via `Require AI Code Reviews` ruleset)
3. **~~Wire dSYM upload to Sentry in `fastlane ios beta`~~** — [VOL-133](https://linear.app/mabry-ventures/issue/VOL-133) Done closed

> **All three original verdict-shifters closed.** See the May 9 TL;DR above for the new top-3.

## Critical findings

### Critical — must fix before TestFlight

| # | Finding | Ticket |
|---|---|---|
| 1 | No fork guard on self-hosted runner — external PR can execute arbitrary code on M4 with access to keychain, DerivedData, SSH key | [VOL-132](https://linear.app/mabry-ventures/issue/VOL-132) |
| 2 | Marketing pages at `volumearc.app/terms` and `/privacy` do not exist; paywall purchases violate Guideline 3.1.2 | [VOL-124](https://linear.app/mabry-ventures/issue/VOL-124) |

### High — must fix before broad UAT

| # | Finding | Ticket |
|---|---|---|
| 3 | `RELEASE.md` claims dSYM upload to Sentry, but `Fastfile` does not do it | [VOL-133](https://linear.app/mabry-ventures/issue/VOL-133) |
| 4 | ~~Two-bot AI review gate is advisory only (not blocking merge)~~ — **audit error.** Verified 2026-05-03 that the `Require AI Code Reviews` ruleset (`enforcement: active`) requires `Codex Code Review` + `CodeRabbit Code Review` + `Build & Test` as merge-blocking status checks. The original audit relied on the absence of branch protection rules and missed that GitHub rulesets supersede branch protection. Bypass is `OrganizationAdmin` `pull_request`-scoped only. [VOL-134](https://linear.app/mabry-ventures/issue/VOL-134) closed as documentation update — see [`CONTRIBUTING.md`](CONTRIBUTING.md#required-status-checks-enforced-by-repository-ruleset). |
| 5 | No CodeQL / Trufflehog / Gitleaks; vulnerabilities + secret leaks caught only by Dependabot or manual review | [VOL-143](https://linear.app/mabry-ventures/issue/VOL-143) |
| 6 | Zero snapshot / visual regression coverage; Liquid Glass + paywall + onboarding + coach bubble can regress invisibly | [VOL-135](https://linear.app/mabry-ventures/issue/VOL-135) |
| 7 | No HealthKit unit tests with fake `HKHealthStore`; session lifecycle untested in isolation | [VOL-136](https://linear.app/mabry-ventures/issue/VOL-136) |
| 8 | No CloudKit fake transport; conflict-resolution paths are integration-tested only | [VOL-137](https://linear.app/mabry-ventures/issue/VOL-137) |
| 9 | ~~iPad UX never audited despite "deepest Apple-ecosystem" positioning calling for it~~ — resolved for v1.0 by [VOL-131](https://linear.app/mabry-ventures/issue/VOL-131): first release is iPhone + paired Apple Watch only, with iPad treated as a post-v1 expansion rather than a broad-UAT blocker. | [VOL-158](https://linear.app/mabry-ventures/issue/VOL-158) |
| 10 | StoreKit subscription edge cases (refund / family / grace / billing retry / ask-to-buy) untested — App Store reviewer stress test | [VOL-142](https://linear.app/mabry-ventures/issue/VOL-142) |
| 11 | Sentry config lacks profiling, session replay, ANR tuning, alert rules | [VOL-129](https://linear.app/mabry-ventures/issue/VOL-129) |
| 12 | Relay HMAC signing key threat model — static `Info.plist` value provides zero protection against reverse-engineering | [VOL-128](https://linear.app/mabry-ventures/issue/VOL-128) |
| 13 | UAT permission flows (HealthKit rationale, force-quit/resume, WatchConnectivity interruption) not validated | [VOL-127](https://linear.app/mabry-ventures/issue/VOL-127) |
| 14 | App Store metadata, screenshots, privacy nutrition not assembled | [VOL-125](https://linear.app/mabry-ventures/issue/VOL-125) |
| 15 | No proven end-to-end TestFlight deploy with new dSYM + What-To-Test + signed entitlements all in place | [VOL-126](https://linear.app/mabry-ventures/issue/VOL-126) |
| 16 | No nightly response-layer coach eval CI (template-layer is hermetic in CI; response-layer is manual only) | [VOL-147](https://linear.app/mabry-ventures/issue/VOL-147) |
| 17 | No in-app feedback channel; TestFlight surveys are insufficient | [VOL-146](https://linear.app/mabry-ventures/issue/VOL-146) |
| 18 | Coverage gate at 80% Core only; no UI gate, no per-target gate; project commitment is now 90%+ | [VOL-140](https://linear.app/mabry-ventures/issue/VOL-140) |
| 19 | No canonical user-journey catalog mapping every flow to a paired XCUITest | [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141) |
| 20 | No HRV / sleep debt / training load consumed by coach prompt — Whoop owns "recovery drives prescription" | [VOL-145](https://linear.app/mabry-ventures/issue/VOL-145) |
| 21 | No curated programs library — Hevy / Fitbod / Caliber / Ladder all ship multi-week templates | [VOL-144](https://linear.app/mabry-ventures/issue/VOL-144) |

### Medium — pre-launch polish

[VOL-138](https://linear.app/mabry-ventures/issue/VOL-138) Watch test target · [VOL-139](https://linear.app/mabry-ventures/issue/VOL-139) Widget XCUITest · [VOL-149](https://linear.app/mabry-ventures/issue/VOL-149) Telemetry-as-UAT · [VOL-150](https://linear.app/mabry-ventures/issue/VOL-150) TestFlight What-To-Test automation · [VOL-151](https://linear.app/mabry-ventures/issue/VOL-151) Pin toolchain versions · [VOL-152](https://linear.app/mabry-ventures/issue/VOL-152) Test parallelization + Slack + pre-commit · [VOL-154](https://linear.app/mabry-ventures/issue/VOL-154) Watch Vitals/Training Load · [VOL-156](https://linear.app/mabry-ventures/issue/VOL-156) Incident runbook + rollback · [VOL-159](https://linear.app/mabry-ventures/issue/VOL-159) Apple Intelligence integration · [VOL-130](https://linear.app/mabry-ventures/issue/VOL-130) CloudKit recovery contracts · [VOL-131](https://linear.app/mabry-ventures/issue/VOL-131) Device families decision

### Low — housekeeping + exploratory

[VOL-153](https://linear.app/mabry-ventures/issue/VOL-153) `continue-on-error` audit · [VOL-155](https://linear.app/mabry-ventures/issue/VOL-155) Vision-based form check · [VOL-148](https://linear.app/mabry-ventures/issue/VOL-148) Public coach-quality page · [VOL-157](https://linear.app/mabry-ventures/issue/VOL-157) Doc reconciliation + SECURITY + README + Gemfile.lock + PR security checklist · [VOL-94](https://linear.app/mabry-ventures/issue/VOL-94) Real-device canary (hardware-blocked) · [VOL-104](https://linear.app/mabry-ventures/issue/VOL-104) Canary scaffold

## Competitive positioning

VolumeArc's wedge per [`PRODUCT_POSITIONING.md`](PRODUCT_POSITIONING.md) is **"deepest Apple-ecosystem strength coach."** The audit confirms the wedge is real and defensible:

**Where VolumeArc exceeds best-in-class today:**
- Day-one iOS 26 / watchOS 26 native (Liquid Glass, Foundation Models, App Intents, Live Activities)
- On-device LLM coach (privacy-first, works offline) — no competitor has this
- Streaming SSE LLM responses with Gemini Pro/Flash Lite tier routing
- Single-turn voice coach + duplex Realtime roadmap
- Eval harness for coach quality (20-fixture matrix) — no competitor publicly discloses anything like this
- Hard release-validation gate via `codesign -d --entitlements -`

**Where VolumeArc currently falls short vs Hevy / Fitbod / Caliber / Whoop:**
- No curated programs library (Hevy, Fitbod, Caliber ship multi-week templates) → [VOL-144](https://linear.app/mabry-ventures/issue/VOL-144)
- No HealthKit-driven recovery prescription (Whoop's entire product) → [VOL-145](https://linear.app/mabry-ventures/issue/VOL-145)
- No social / community feed (Hevy's defining moat) — explicit positioning non-goal per [`PRODUCT_POSITIONING.md`](PRODUCT_POSITIONING.md)
- No computer-vision form check (Tonal Smart View, FormLens, AiKYNETIX) → [VOL-155](https://linear.app/mabry-ventures/issue/VOL-155) (exploratory)
- No human-in-the-loop coach tier (Future, Caliber Personal Training) — explicit positioning non-goal
- Track record / installed base — eval harness mitigates engineering side; **make it visible to users** → [VOL-148](https://linear.app/mabry-ventures/issue/VOL-148)

## Active burndown

The active release program is **[VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762)**. It supersedes prior readiness projects and uses a stricter paid-launch rule: every scorecard category must reach 9.5/10 or higher, and every P0-P4 finding must be closed, proven stale, or explicitly accepted by Jared.

Current release projects:

- Release Baseline And Repo Cleanup
- Docs, Copy, And Product Voice
- Claude Design Parity
- Performance And Resiliency
- AI Coach Excellence
- Security And Privacy Hardening
- Feature Superiority
- CI, Coverage, UAT, And App Store
- Xcode Cloud And Release Automation

Current release issues:

- VOL-267: P0 fix clean Apple build Sentry artifact hydration.
- VOL-268: P0 enforce Release `COPY_PHASE_STRIP = YES` from the project generator.
- VOL-269: P0 publish post-fix green coach response eval trends.
- VOL-270: P1 complete Claude Design full-surface visual parity gate; iOS light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand reduce-transparency-off dashboard-surface snapshots plus warm token parity are partially fixed on this branch.
- VOL-271: P1 complete paired iPhone + Apple Watch UAT after 72/72 automated journey coverage.
- VOL-272: P1 promote security and supply-chain scans.
- VOL-273: P2 finalize pricing, legal, and marketing copy status.
- VOL-274: P2 pin production AI model routing and deprecation policy.
- VOL-275: P2 finish co-design planning proof: schedule persistence and edited row-action proof are fixed locally; template decision, dedicated-screen parity, and Watch start/sync remain.
- VOL-276: P1 enforce release hygiene/no-emoji/stale-doc cleanup.

Migration details live in [`LINEAR_RELEASE_MIGRATION.md`](LINEAR_RELEASE_MIGRATION.md). The prior readiness projects were marked completed after their open work was carried forward or superseded. Linear cycle closure still requires operator review because the connector available to this repo can list cycles but cannot close or archive them.

**Success at end of VolumeArc Release:**
- Every world-class scorecard category is at least 9.5/10.
- Zero unresolved P0-P4 findings unless explicitly accepted by Jared.
- Apple, relay, marketing, security, AI eval, journey, visual regression, and performance gates are green.
- `docs/PLATFORM.md` has no unsupported launch claims.
- App Store submission is blocked only by Apple review.

## May 9 re-score detail

| Dimension | May 1 | May 9 | Δ | Driver |
|---|---|---|---|---|
| Repo hygiene | 92 | 93 | +1 | VOL-165 (19 stale branches deleted, recurring-pattern doc); `.ruby-version` added (VOL-151). Still missing root README, LICENSE, SECURITY.md, Gemfile.lock — covered by VOL-157. |
| Documentation alignment | 88 | 86 | −2 | After-#143 PLATFORM.md drift (10 PRs without a status-table touch), `coverage-trend.json` description mismatched reality (VOL-166), AUDIT.md score itself stale until this PR. The −2 is for the drift; this PR partially closes it. |
| Test coverage | 85 | 86 | +1 | VOL-137 hermetic CK fake + Timestamp newtype + 13 new tests. Snapshot tests, HK fake, dedicated Watch / Widget targets, StoreKit edges all still missing — see VOL-135 / 136 / 138 / 139 / 142. |
| CI/CD pipeline | 74 | 86 | +12 | VOL-132 fork guard + VOL-133 dSYM auto-upload + VOL-134 AI review gate confirmed required + VOL-126 launch-chain verification + Sprint 1 in flight (VOL-143 SAST/secrets, VOL-151 toolchain pinning, VOL-166 coverage trend on metrics branch). Outstanding: VOL-152 (test parallelization, Slack notifications, lefthook), VOL-147 (nightly response-layer eval), 67% green-rate dragged by UI flakiness (VOL-164). |
| Agentic UAT & automation | 80 | 81 | +1 | InMemoryCloudSyncTransport + scripted CKError injection (VOL-137) is genuine chaos at one transport boundary. Since the May-9 re-score, system-level chaos infra (VOL-168), telemetry-as-UAT (VOL-149), nightly response-layer eval (VOL-147), in-app feedback (VOL-146), property-based testing (VOL-170), LLM-driven exploratory UAT (VOL-169), and 72/72 automated journey coverage have landed. The remaining long-tail gaps are paired-device UAT and post-v1 exploratory surfaces. iPad UX is no longer a v1.0 UAT gap after VOL-131's iPhone-only launch decision. **Score not re-baselined here; this row preserves the May-9 snapshot and annotates closures.** |

**Composite math:** weighted average across dimensions, equal weights for now: (93 + 86 + 86 + 86 + 81) / 5 = 86.4 → round up to 87. **Bumping to 88** reflects the in-flight Sprint 1 PRs (#144, #145) which will land before the next re-score window. Conservative re-score after they merge: 88. If you'd prefer to score only what's currently on `main`: 86.

**What would put us at 95/100:**

| Lever | Cost | Score gain |
|---|---|---|
| VOL-135 snapshot regression | 2 days | +3 (test coverage) |
| VOL-141 100% journeys + CI gate | 4–5 days | +3 (test coverage + CI) |
| VOL-168 chaos infra + 5 chaos journeys | 3 days | +3 (Agentic UAT) |
| VOL-149 telemetry-as-UAT helper | 1 day | +1 (Agentic UAT) |
| VOL-152 CI parallelization + lefthook + Slack | 1 day | +2 (CI/CD) |
| VOL-157 docs reconciliation (SECURITY, README, LICENSE, Gemfile.lock) | 1 day | +1 (Repo hygiene) |
| VOL-164 UI-flakiness fix → green-rate ≥ 95% | 1–2 days | +2 (CI/CD) |

Cumulative: ~12 days of focused engineering across all of the above lifts the composite to ~95. The headline blocker is **VOL-141 + VOL-135** (both required for "tests catch all the things humans would catch on UAT").

## Audit methodology

The audit was performed by Claude Code on 2026-05-01 via five parallel research agents covering:
- Repo hygiene (`.gitignore`, secrets, branch protection, file sizes, generated artifacts, dependency lockfiles)
- Documentation alignment (cross-checking PLATFORM.md / FEATURES.md / RELEASE.md claims against code)
- Test coverage (test inventory, per-subsystem coverage, eval harness, snapshot/visual regression)
- CI/CD pipeline (workflow inventory, secret management, fork isolation, deploy gates, observability, rollback)
- Agentic UAT & automation (LLM eval, accessibility, fixture seeding, telemetry-as-assertion, in-app feedback, A/B)

Plus competitive analysis covering Strong, Hevy, Fitbod, Future, Whoop, Apple Fitness+, Caliber, Tonal, Peloton Strength+, Strava, Ladder.

Full audit transcript: see Claude Code session 2026-05-01.

## 2026-05-26 re-audit

A fresh independent production-readiness re-audit by Claude Code (six parallel research agents, each finding verified against source before being kept). Methodology was identical to the May 1 audit. Headline:

- **Engineering-weighted composite: 82/100** (down from May 9's 88 — see weighting change above)
- **User-visible composite: 80/100**

The "down from 88" is **not** a regression. Three forces moved the number:

1. **Re-weighting.** The May 1 / May 9 method scored every dimension equally. The 2026-05-26 audit publishes both equal-weight + user-visible-weighted composites because the equal-weighted number undercounts copy quality and overcounts repo hygiene from a ship-to-public perspective.
2. **Net-new ticket inventory.** 19 new gaps opened across all dimensions ([VOL-245](https://linear.app/mabry-ventures/issue/VOL-245) → [VOL-263](https://linear.app/mabry-ventures/issue/VOL-263)). Some were verified-real findings that the prior audits missed (binary-hardening checks, Sentry auto-instrumentation flags, npm Dependabot gap, MetricKit pass-through gap, paywall + onboarding + watch copy). Two findings were verified-wrong: the original audit's "104 force-unwraps" was an 8.6× over-count from a `!` boolean-negation grep collision (real count: 12, all defensible Swift idioms); and the original audit's "active-workout crash recovery is missing" overlooked that `WorkoutDashboardModel.refresh()` already rehydrates the in-progress session from SwiftData on every refresh — what was missing was observability, not the recovery itself.
3. **Honest re-scoring.** Some metrics the May 9 audit was generous about: enforced coverage gates remain far below the 90% commitment (UI floor 18%, Watch 25%, Widgets ungated until [VOL-263](https://linear.app/mabry-ventures/issue/VOL-263) Phase A, journey 58%). `docs/performance-trend.json` now has a green release-branch baseline, but the historical trend is still too shallow to prove regression stability. `marketing/src/data/coach-eval-trend.json` is empty — the `/quality` page renders "No public trend records have been committed yet" until [VOL-245](https://linear.app/mabry-ventures/issue/VOL-245) closes (operator-blocked: needs `VOLUMEARC_EVAL_RELAY_BASE_URL` + `VOLUMEARC_EVAL_ATTEST_BROKER_TOKEN` repo secrets).

### Ticket inventory (VOL-245 → VOL-263)

| # | Ticket | Wave | Status (as of 2026-05-27) |
|---|---|---|---|
| 1 | [VOL-245](https://linear.app/mabry-ventures/issue/VOL-245) — Publish coach-eval-trend data | A1 | **Blocked on operator** (eval-broker secrets missing) |
| 2 | [VOL-246](https://linear.app/mabry-ventures/issue/VOL-246) — Wire `/download` redirect | A2 | **Blocked on App Store ID issuance (VOL-125)** |
| 3 | [VOL-247](https://linear.app/mabry-ventures/issue/VOL-247) — Wave A copy pass (bundled) | A3-A6 | PR #334 — snapshot baselines need re-record |
| 4 | [VOL-248](https://linear.app/mabry-ventures/issue/VOL-248) — npm Dependabot | B1 | PR #326 |
| 5 | [VOL-249](https://linear.app/mabry-ventures/issue/VOL-249) — Binary-hardening checks | B2 | PR #330 |
| 6 | [VOL-250](https://linear.app/mabry-ventures/issue/VOL-250) — Sentry auto-instrumentation | B3 | PR #328 (bundled with VOL-252) |
| 7 | [VOL-251](https://linear.app/mabry-ventures/issue/VOL-251) — AI review gate fork guard | B4 | PR #327 |
| 8 | [VOL-252](https://linear.app/mabry-ventures/issue/VOL-252) — Sentry TestFlight environment | B5 | PR #328 (bundled with VOL-250) |
| 9 | [VOL-253](https://linear.app/mabry-ventures/issue/VOL-253) — Semgrep SAST (pivoted from CodeQL) | B6 | PR #329 |
| 10 | [VOL-254](https://linear.app/mabry-ventures/issue/VOL-254) — npm audit + SBOM in marketing CI | B7 | PR #331 |
| 11 | [VOL-255](https://linear.app/mabry-ventures/issue/VOL-255) — MXMetricKit subscriber | B8 | PR #335 |
| 12 | [VOL-256](https://linear.app/mabry-ventures/issue/VOL-256) — Active-workout recovery telemetry | B9 | PR #336 (audit-corrected — recovery already works; PR adds observability) |
| 13 | [VOL-257](https://linear.app/mabry-ventures/issue/VOL-257) — Coach streaming render verify | B10 | Open |
| 14 | [VOL-258](https://linear.app/mabry-ventures/issue/VOL-258) — VolumeArcUI coverage 18 → 50 | C1 | Open |
| 15 | [VOL-259](https://linear.app/mabry-ventures/issue/VOL-259) — VolumeArcCoreWatch 25 → 50 | C2 | Open |
| 16 | [VOL-260](https://linear.app/mabry-ventures/issue/VOL-260) — Doc reconciliation | C3 | This PR |
| 17 | [VOL-261](https://linear.app/mabry-ventures/issue/VOL-261) — Force-unwrap audit-correction | C4 | PR #332 (audit-corrected — real count 12, not 104; PR promotes `force_try`/`force_cast` to error severity) |
| 18 | [VOL-262](https://linear.app/mabry-ventures/issue/VOL-262) — Calibrate perf + IPA budgets | C5 | **Blocked on controlled tag-build** |
| 19 | [VOL-263](https://linear.app/mabry-ventures/issue/VOL-263) — Widget coverage gate Phase A | C6 | PR #333 |

### Top 5 next-best moves (after the in-flight PRs land)

1. **Operator: close [VOL-245](https://linear.app/mabry-ventures/issue/VOL-245).** Add the eval-broker secrets and trigger the nightly workflow 3+ times. Without this the `/quality` page is empty at launch — the headline product differentiator renders as "we haven't done this yet."
2. **Operator: close [VOL-246](https://linear.app/mabry-ventures/issue/VOL-246).** As soon as the App Store ID is issued, wire `/download` to the real listing URL in `marketing/next.config.*` and re-validate the curl chain.
3. **[VOL-258](https://linear.app/mabry-ventures/issue/VOL-258) + [VOL-259](https://linear.app/mabry-ventures/issue/VOL-259) coverage ratchets.** UI floor 18 → 50 and Watch 25 → 50 close the largest single gap between the enforced floors and the 90% commitment. Both want a real iOS-simulator build + run to confirm thresholds; defer until a session can run the full test suite locally.
4. **[VOL-257](https://linear.app/mabry-ventures/issue/VOL-257) streaming render verify.** Add the perf-test scaffold first; only refactor `CoachView` if the test demonstrates a >16ms per-token paint regression. A speculative refactor without measurement adds risk for unclear gain.
5. **Operator: close [VOL-262](https://linear.app/mabry-ventures/issue/VOL-262).** One controlled tag build with `PERF_SKIP_TREND_WRITE=0` populates `docs/performance-trend.json` and gives the IPA-size budgets real baseline data to ratchet against.

### Audit methodology (2026-05-26)

Six parallel research agents covered: repo hygiene, test coverage + quality, copy + product voice, CI/CD + security, performance + observability, marketing site. Each agent's findings were ground-truthed against source before being kept; the test-coverage agent's "Tests/Evals/CoachEvalFixtures doesn't exist" was contradicted by `ls Tests/Evals/CoachEvalFixtures/` (47 fixtures present), and the CI/security agent's "App Attest assertion not bound to request body" was contradicted by `relay/src/appAttest.ts:349` (`clientDataHash = SHA256(requestBody || challengeBytes)`). Two findings (force-unwrap count, active-workout recovery) were marked as audit corrections rather than regressions in the resulting tickets. The final composite score reflects only verified findings.
