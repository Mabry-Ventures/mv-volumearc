# AI Model Routing Decision Record

Last updated: 2026-06-06

This record tracks production model routing decisions for the VolumeArc coach relay. It is owned by the `AI Coach Excellence` project under `VolumeArc Release`.

## Current Launch Decision

Status: branch-selected, not approved for launch.

The release branch pins both cloud tiers to specific stable Gemini model IDs. Google Gemini documentation states that stable model strings point to specific stable models and that most production apps should use a specific stable model. The `latest` alias can be hot-swapped with advance notice, so `gemini-flash-latest` is no longer acceptable for the premium paid path.

As of the 2026-06-06 source check, Gemini's model page lists `gemini-3.5-flash` as stable, with stable model code `gemini-3.5-flash`, and the deprecations page lists no shutdown date for it. The same deprecations page lists `gemini-3.1-flash-lite` with an earliest shutdown date of May 7, 2027. That makes Flash-Lite acceptable for the free/default path only if the deprecation review is monitored.

References: [Gemini models](https://ai.google.dev/gemini-api/docs/models), [Gemini deprecations](https://ai.google.dev/gemini-api/docs/deprecations).

## Required Routing Matrix

| Tier/path | Branch model | Launch requirement | Evidence required |
|---|---|---|---|
| Free cloud coach | `gemini-3.1-flash-lite` | Pinned stable low-latency/cost model with deprecation monitor before May 7, 2027. | 47/47 response evals, latency budget, cost estimate, deprecation-date owner. |
| Premium cloud coach | `gemini-3.5-flash` | Pinned stable model selected for best user experience first, cost second. | 47/47 response evals, latency budget, cost estimate, no announced shutdown date confirmed at release. |
| Foundation Models | Apple Foundation Models on supported iOS 26+ devices. | Same prompt contract and safety envelope as relay; invisible fallback when unavailable. | Hermetic evals, fallback tests, unavailable-device behavior. |
| Local heuristic fallback | `LocalHeuristicAICoachProvider` | Deterministic, safe, useful when offline or relay fails. | Unit tests, journey tests, safety red-team fixtures. |
| Voice path | `AIRelayVoiceTransport` through selected coach-provider chain | No provider branding in normal UX; coaching language remains direct and useful. | Latency tests, interruption tests, fallback tests. |

## Branch Changes

- `relay/wrangler.toml`: `MODEL_PREMIUM` changed from `gemini-flash-latest` to `gemini-3.5-flash`.
- `relay/wrangler.staging.toml`: staging mirrors production so live evals exercise the same model choices.
- `MODEL_DEFAULT` remains `gemini-3.1-flash-lite` because it is stable, fast, and cost-efficient, but it carries the May 7, 2027 shutdown review requirement.

## Approval Criteria

Before launch, update this file with:

1. Live staging eval run IDs for the selected models.
2. Cost and latency targets from staging telemetry.
3. Replacement policy for `gemini-3.1-flash-lite` before May 7, 2027.
4. Safety/privacy exceptions, if any.
5. Jared approval if any non-green eval result is accepted.
