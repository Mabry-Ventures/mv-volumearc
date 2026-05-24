# AI Coach Eval Harness (VOL-100)

Regression protection for the AI coach's prompt quality. Two layers:

| Layer | Where | When it runs | What it catches |
|-------|-------|--------------|-----------------|
| Template-layer (hermetic) | `Tests/VolumeArcAppTests/Evals/CoachEvalTests.swift` | Every PR via `scripts/test_apple_targets.sh` | Any regression that bypasses `CoachPromptTemplate.render`, drops the template marker, changes intent envelopes, strips the system prompt persona, or mutates the renderer's determinism. No network, no model call, no Gemini budget burned. |
| Response-layer (manual / nightly) | `scripts/run_coach_evals.sh` | On-demand + nightly workflow (follow-up) | Drift in the actual model output — sentence budget, numeric grounding, banned phrases, pain-signal flagging, next-exercise anchoring. Requires `VOLUMEARC_RELAY_SIGNING_KEY`. |

Fixtures are the single source of truth for both layers. They live at `Tests/Evals/CoachEvalFixtures/*.json`, get bundled into the iOS test target as a folder reference, and are read directly off disk by the shell script.

## Methodology

The coach prompt has four axes that matter for quality:

- **Readiness** — the numeric recovery signal the model leans on. Fixtures cover 45, 60, 72, 82, 88 to exercise the low / moderate / borderline / ready / peak branches.
- **Intent** — the `CoachIntent` classification that selects the per-intent envelope. Fixtures cover all six: `progression`, `deload`, `form`, `recovery`, `substitution`, `free`.
- **Session history depth** — whether the athlete has 0 (cold start), 1 (single data point), or 5+ (established pattern) recent sessions. Three tiers because the product UI surfaces them differently.
- **Coaching style** — `motivational`, `analytical`, `minimal`. These map to the `CoachingStyle` enum in `VolumeArcCore`; the task-spec names ("motivational / precise / playful") correspond in spirit but the implementation uses the enum values. A rename is out of scope for this ticket.

Not every cell of the 5 × 6 × 3 × 3 = 270 matrix is covered. The current 31 fixtures were hand-picked so (a) every value on every axis appears at least twice, (b) the pain-signal, cold-start, sparse-history, program-awareness, recovery-context, and numeric-grounding edge cases all have coverage, and (c) fixture IDs remain stable across runs so diffs are tractable.

### Template-layer assertions (always on)

Each fixture gets fed through `CoachPromptTemplate.render(intent:contextBlock:question:style:)` and checked for:

1. Template marker (`[VAC:tmpl]`) present — any provider that bypasses the template drops this.
2. Intent + style declared in the `intent=... style=...` header.
3. System prompt preamble present ("VolumeArc's strength coach").
4. Persona fragment matches the style (`High-energy` for motivational, `Data-driven` for analytical, `Short and direct` for minimal).
5. Context block preserved verbatim.
6. Question embedded verbatim.
7. Per-intent envelope fragment present (e.g. `"pushing load or volume"` for progression).
8. Renderer determinism — same inputs produce byte-identical output.

A coverage sweep also asserts that every `CoachIntent`, every `CoachingStyle`, every readiness bucket from `{45, 60, 72, 82, 88}`, and every session-history tier from `{0, 1, 5+}` still has at least one fixture. If a future edit trims the suite below the coverage floor, the test fails loudly.

### Response-layer assertions (manual / nightly)

`scripts/run_coach_evals.sh` POSTs each fixture to the live relay at `https://relay.volumearc.app/v1/coach` using the same HMAC signing scheme the iOS app uses (`VolumeArcRelaySessionProvider.authorizationHeaderValue`). Responses arrive as `text/event-stream` frames, get joined, and then checked against the fixture's `expectedAssertions`:

- `maxSentences` — hard upper bound on sentence count (with a +1 tokenizer grace).
- `mustContainNumericContext` — the response cites at least one number.
- `mustMentionReadinessOrRPE` — cites the grounded signal.
- `mustNotMention` — list of banned phrases (pain platitudes, max-out language, 1RM references).
- `toneHint` — informational; not asserted today but surfaced in the run log for human review.
- `mustAnchorOnNextExercise` — the response references the next-up exercise's primary movement pattern. The script extracts the last word from the `Next up:` line in the fixture context (e.g. `"Back Squat"` → `"squat"`) and does a case-insensitive substring match.
- `mustFlagPainSignal` — the response acknowledges pain or injury hedging language for fixtures where the question carries an injury signal.

Assertions are intentionally SHAPE checks, not string-equality checks. Models are non-deterministic; we assert that the response is in the right shape, not that it matches a pinned golden string.

## Running the harness

### Template layer (hermetic)

Included in the default iOS test run:

```bash
./scripts/test_apple_targets.sh
```

The `CoachEvalTests` class runs as part of `VolumeArcAppTests`. Failure surfaces the fixture ID and the specific invariant that broke.

### Response layer (manual)

```bash
export VOLUMEARC_RELAY_SIGNING_KEY="<same key the iOS app uses>"
# Optional:
#   export VOLUMEARC_EVAL_DEVICE_ID="coach-eval-harness"  # default
#   export VOLUMEARC_RELAY_BASE_URL="https://relay.volumearc.app"  # default
#   export VOLUMEARC_EVAL_OUTPUT_DIR=".build/coach-evals/manual-run"

./scripts/run_coach_evals.sh
```

The script writes per-fixture response bodies + a `summary.json` under `$VOLUMEARC_EVAL_OUTPUT_DIR` and exits non-zero on any failure. The nightly CI workflow uploads that machine-readable summary and the raw per-fixture responses as its `coach-eval-results-<run_id>` artifact.

## Fixture inventory

| # | ID | Readiness | Intent | Sessions | Style | What it exercises | Last template-run | Last response-run |
|---|----|-----------|--------|----------|-------|-------------------|-------------------|-------------------|
| 1 | `progression-ready-5-sessions-motivational` | 82 | progression | 5 | motivational | Clean green-light branch with rich history and motivational tone. | pending | pending |
| 2 | `progression-peak-5-sessions-analytical` | 88 | progression | 5 | analytical | Peak readiness + advanced athlete; model must cite bar speed / RPE trend. | pending | pending |
| 3 | `progression-moderate-1-session-motivational` | 72 | progression | 1 | motivational | Borderline push decision with thin history — the nuanced branch. | pending | pending |
| 4 | `deload-low-5-sessions-analytical` | 45 | deload | 5 | analytical | Clear deload case; analytical tone must cite the RPE trend explicitly. | pending | pending |
| 5 | `deload-moderate-5-sessions-minimal` | 60 | deload | 5 | minimal | Borderline deload + tightest sentence budget (minimal style). | pending | pending |
| 6 | `deload-borderline-1-session-motivational` | 72 | deload | 1 | motivational | Sparse-history deload question; model must not over-recommend. | pending | pending |
| 7 | `form-ready-5-sessions-analytical` | 82 | form | 5 | analytical | Form question with rich history — cue specificity matters. | pending | pending |
| 8 | `form-moderate-empty-minimal` | 60 | form | 0 | minimal | Cold-start form question; must not pretend to have session data. | pending | pending |
| 9 | `form-low-1-session-motivational` | 45 | form | 1 | motivational | Pain-signal guardrail — must not recommend pushing through pain. | pending | pending |
| 10 | `recovery-low-5-sessions-motivational` | 45 | recovery | 5 | motivational | Low readiness + accumulated fatigue; motivational tone must not override safety. | pending | pending |
| 11 | `recovery-moderate-1-session-analytical` | 60 | recovery | 1 | analytical | Moderate readiness with thin data; conservative read expected. | pending | pending |
| 12 | `recovery-peak-5-sessions-minimal` | 88 | recovery | 5 | minimal | Clean green-light readiness in tightest form. | pending | pending |
| 13 | `recovery-moderate-empty-motivational` | 72 | recovery | 0 | motivational | New user cold start — readiness exists but no history to cite. | pending | pending |
| 14 | `substitution-ready-1-session-motivational` | 82 | substitution | 1 | motivational | Substitution anchored on next-up exercise (bench press). | pending | pending |
| 15 | `substitution-moderate-5-sessions-minimal` | 60 | substitution | 5 | minimal | Minimal-style substitution — terse alternate without padding. | pending | pending |
| 16 | `substitution-low-empty-analytical` | 45 | substitution | 0 | analytical | Hardest substitution case: pain signal + cold start + low readiness. | pending | pending |
| 17 | `free-peak-empty-motivational` | 88 | free | 0 | motivational | Cold-start free-form question on a new user's first day. | pending | pending |
| 18 | `free-moderate-1-session-analytical` | 72 | free | 1 | analytical | Open-ended strategic question with partial history; must avoid generic advice. | pending | pending |
| 19 | `free-ready-5-sessions-minimal` | 82 | free | 5 | minimal | Dense context + minimal style — model must not dump context back. | pending | pending |
| 20 | `free-low-empty-analytical` | 45 | free | 0 | analytical | Worst-case cold start: low readiness, no history, free question. | pending | pending |
| 21 | `recovery-high-hrv-up-sleep-ahead` | 82 | recovery | 3 | motivational | Recovery context supports pushing: HRV up and sleep ahead. | pending | pending |
| 22 | `recovery-low-hrv-down-sleep-debt` | 58 | recovery | 4 | analytical | Recovery context argues for backing off: HRV down, sleep debt, and high load. | pending | pending |
| 23 | `progression-with-high-recovery` | 80 | progression | 3 | motivational | Progression ask where recovery signals support a small concrete jump. | pending | pending |
| 24 | `progression-with-low-recovery` | 62 | progression | 4 | analytical | Progression ask where recovery signals override clean prior training data. | pending | pending |
| 25 | `deload-with-high-recovery` | 81 | deload | 3 | analytical | Deload ask where strong recovery should avoid over-deloading. | pending | pending |
| 26 | `deload-with-low-recovery` | 55 | deload | 5 | motivational | Deload ask where HRV, sleep debt, and load confirm the deload call. | pending | pending |
| 27 | `program-progression-531-bbb` | 82 | progression | 4 | analytical | Program-aware progression must respect the 5/3/1 wave. | pending | pending |
| 28 | `program-deload-starting-strength` | 60 | deload | 3 | minimal | Program-aware deload for a novice linear progression. | pending | pending |
| 29 | `program-substitution-ppl` | 72 | substitution | 5 | motivational | Program-aware substitution should preserve the Pull B vertical-pull slot. | pending | pending |
| 30 | `program-recovery-upper-lower` | 45 | recovery | 4 | analytical | Program-aware recovery should preserve the weekly plan while modifying today. | pending | pending |
| 31 | `program-free-hst` | 88 | free | 5 | motivational | Free-form coaching should still anchor to the active HST block. | pending | pending |

The `Last template-run` and `Last response-run` columns are hand-updated when you run the harness. The template-layer column flips to `PASS` on every green CI run against the branch. The response-layer column is only updated after a manual or nightly `scripts/run_coach_evals.sh` invocation — the summary JSON under `$VOLUMEARC_EVAL_OUTPUT_DIR/summary.json` is the machine-readable source of truth for that column.

## Adding a new fixture

1. Copy an existing fixture as a template and change the `id`. The ID must be kebab-case, lowercase, no spaces — the ID-stability test enforces this.
2. Fill in `intent`, `question`, `contextBlock`, `style`, and a meaningful `expectedAssertions` block. Every field under `expectedAssertions` is optional — omit what you don't care about, but keep `mustNotMention` populated with at least the banned phrases the system prompt bans (`max out`, `1RM`, `push through`).
3. Add a row to the inventory table above with the scenario matrix values and a one-line "what it exercises" note.
4. Run `./scripts/test_apple_targets.sh` — the axis-coverage test will tell you if the new fixture violates a matrix invariant (e.g., adding a fixture with a brand-new readiness score that no other fixture covers is fine; removing the last fixture at readiness 45 is not).

## Why fixtures live at `Tests/Evals/` not `Tests/VolumeArcAppTests/Evals/`

One directory feeds two consumers. The XCTest bundle reads them as a bundled folder reference (`Bundle(for:).url(forResource: "CoachEvalFixtures")`), and `scripts/run_coach_evals.sh` reads them directly from the repo. A top-level `Tests/Evals/` location keeps them out of the platform-specific test bundle path without orphaning them from the rest of the Tests tree. The Xcode project generator wires the folder in as a test-target resource so changes to the fixtures are always part of the build graph.

## Nightly CI (VOL-147)

The response-layer eval harness runs on a cron at **07:00 UTC daily** via [`.github/workflows/coach-evals-nightly.yml`](../.github/workflows/coach-evals-nightly.yml). The job:

1. Pre-flights `curl` + `jq` + `openssl` on the self-hosted runner.
2. Runs `scripts/run_coach_evals.sh` against the production relay with a run-scoped `coach-eval-<run_id>-<attempt>` device prefix (using the `VOLUMEARC_RELAY_SIGNING_KEY` repo secret). The script shards that prefix across deterministic suffixes so the suite can exceed one normal per-device rate-limit window without producing a self-inflicted 429.
3. Parses the resulting `summary.json` and appends a `{timestamp, sha, run_id, total, passed, failed, axes, fixtures}` record to [`docs/coach-eval-trend.json`](coach-eval-trend.json) — the trend file is committed back to `main` only on cron runs (mirrors VOL-166's `docs/coverage-trend.json` pattern). The same file is mirrored into `marketing/src/data/coach-eval-trend.json` so Vercel's `marketing/` project root can statically render `/quality`.
4. Uploads the full per-fixture response bodies + `summary.json` as a workflow artifact (`coach-eval-results-<run_id>`), retained 30 days.
5. Fails the job on any fixture-level regression so the cron-failure email surfaces it.

Manual operator runs use `workflow_dispatch` with an optional `relay_url` input to point at staging. Manual dispatch runs **do not** commit to the trend file.

### Future work

- **Linear regression ticket on fixture failure** — currently the cron-failure email is the only signal. Once Slack notifications land (VOL-177 Phase 2B), wire a Slack webhook for the same regression channel, and open a `coach-eval-regression`-labeled Linear ticket on first failure of a given fixture so drift is owned.
- **Response-quality golden replay** — record a reference response per fixture once the prompt is locked, run a semantic-similarity check against it on each nightly run, and flag drift above a threshold. Needs a cheap embedding pipeline that doesn't round-trip to Gemini.
- **Multi-tier evals** — the current suite hits only the `flash-lite` tier. Add a flag to the shell script to run the same fixtures against `pro` so pricing-model-budget trade-offs are visible.
