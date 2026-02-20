# Beast Mode Maximization Program - 8 Sprint Execution (2026)

This document operationalizes the program into delivery-ready sprint slices with ownership and release gates.

## Program Guardrails

- Cadence: 2-week sprints
- Team shape:
  - Engineer A (Platform): auth, sync, DB, entitlements
  - Engineer B (Product UX): logging speed, retention loops, settings UX, visuals
  - Engineer C (AI/Reliability): evals, progression/risk intelligence, telemetry, SLOs
- Primary KPI: retention and daily active usage
- Release policy: progressive rollout with feature flags and kill switches

## Sprint Schedule (Absolute Dates)

1. Sprint 1: February 23, 2026 - March 8, 2026
2. Sprint 2: March 9, 2026 - March 22, 2026
3. Sprint 3: March 23, 2026 - April 5, 2026
4. Sprint 4: April 6, 2026 - April 19, 2026
5. Sprint 5: April 20, 2026 - May 3, 2026
6. Sprint 6: May 4, 2026 - May 17, 2026
7. Sprint 7: May 18, 2026 - May 31, 2026
8. Sprint 8: June 1, 2026 - June 14, 2026

## Sprint Delivery Plan

### Sprint 1: Observability + KPI Foundation

- Owner: Engineer C with Engineer B support
- Deliverables:
  - `POST /api/telemetry/ingest`
  - `GET /api/me/features`
  - KPI dashboard route and baseline metric capture
  - release checklist + kill-switch map
- Exit gate:
  - live dashboard with 24h data
  - AI latency/fallback telemetry on all AI routes
  - feature toggles verified at route and page level

### Sprint 2: Accounts + Local-First Cloud Sync (Alpha)

- Owner: Engineer A
- Deliverables:
  - `/api/auth/[...nextauth]`
  - `POST /api/sync/push`
  - `POST /api/sync/pull`
  - Drizzle schema contracts for sync state
  - settings surface for account connect/disconnect
- Exit gate:
  - anonymous mode unchanged
  - signed-in sync roundtrip works across devices
  - conflicts journaled and non-destructive

### Sprint 3: AI Eval Harness + Safety Gates

- Owner: Engineer C
- Deliverables:
  - AI eval registry + runner
  - `npm run ai:eval`
  - CI merge gate for eval thresholds
  - prompt/schema version audit metadata
- Exit gate:
  - schema validity gate at 100%
  - deterministic fallback tests for all AI endpoints

### Sprint 4: Progression Autopilot

- Owner: Engineer C and Engineer B
- Deliverables:
  - progression engine
  - `POST /api/ai/progression-plan`
  - one-tap apply UX in workout flow
  - weekly progression preview in stats
- Exit gate:
  - auto next-session targets generated
  - <2 tap apply path

### Sprint 5: Retention Loops + Motivation Layer

- Owner: Engineer B
- Deliverables:
  - streak rescue UX
  - PR milestones + completion badges
  - next-workout-ready card
  - compare-to-last-session prompts
  - notification preferences model
- Exit gate:
  - D7 retention lift against Sprint 1 baseline
  - session completion funnel improvement

### Sprint 6: Integrations (Health Data Ingest)

- Owner: Engineer A and Engineer C
- Deliverables:
  - integration signal contracts
  - `POST /api/integrations/health/import`
  - risk enrichment using recovery/sleep/HR signals
  - settings connection panel and fallbacks
- Exit gate:
  - risk outputs adapt when external signals are present
  - logging remains fully functional without integrations

### Sprint 7: Monetization + Cost Governance

- Owner: Engineer A and Engineer C
- Deliverables:
  - `GET /api/subscription/entitlements`
  - per-user/system usage accounting
  - per-user budget caps + graceful degrade
  - settings usage/budget controls
- Exit gate:
  - usage and cost visible by actor and endpoint
  - no impact to core manual logging under budget limits

### Sprint 8: Performance, A11y, and Release Hardening

- Owner: Engineer B with Engineer C support
- Deliverables:
  - visual diff checks against baseline snapshots
  - route and interaction performance budgets
  - keyboard/screen reader/contrast hardening
  - incident runbooks + launch/rollback playbook
- Exit gate:
  - live coach p95 <= 2.0s
  - set action feedback <100ms perceived latency
  - critical flows pass visual and accessibility gates

## KPI Operating Rhythm

- Daily:
  - DAU
  - set-log latency p95
  - live coach latency p95
  - AI fallback rate
- Weekly:
  - D1 and D7 retention
  - session completion funnel
  - AI budget consumption and degrade rate

## Rollout Pattern

1. Enable flags in internal/staff mode.
2. Expand to 5% of users.
3. Expand to 25%.
4. Expand to 50%.
5. Full rollout after KPI and error budget checks pass.

## Change Control

- All new persisted fields remain optional and migration-safe.
- Core local workout tracking cannot depend on AI or cloud services.
- Any KPI regression beyond threshold triggers flag rollback first, then code rollback.
