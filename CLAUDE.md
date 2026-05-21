# VolumeArc — Claude Code Guide

[![CI](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml/badge.svg)](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml)

AI-powered strength training coach for iOS and watchOS. **Owner:** Mabry Ventures (`com.mabryventures.VolumeArc`).

## Canonical documentation

The single source of truth for this platform lives in [`docs/PLATFORM.md`](docs/PLATFORM.md). Read it before answering questions about implementation status, architecture, configuration, build system, or code conventions. The status table there is authoritative — anything you'd otherwise put inline in this file should go there instead.

Topic-specific deep dives:
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — module structure, dependency graph, data flow, design principles
- [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) — tokens, components, haptics, motion
- [`docs/FEATURES.md`](docs/FEATURES.md) — granular per-feature checklist (subordinate to the status table in `PLATFORM.md`)
- [`docs/TESTING.md`](docs/TESTING.md) — test architecture, writing tests, coverage targets
- [`docs/USER_JOURNEYS.md`](docs/USER_JOURNEYS.md) — canonical user-journey catalog with paired XCUITest references (VOL-141)
- [`docs/RELEASE.md`](docs/RELEASE.md) — release process, versioning, TestFlight, hotfixes
- [`docs/INCIDENTS.md`](docs/INCIDENTS.md) — incident response runbook: severity ladder, Sentry alert routing, postmortem template, per-subsystem failure-shape runbooks (VOL-156)
- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — dev setup, branch strategy, PR process
- [`docs/MARKETING.md`](docs/MARKETING.md) — marketing site (`marketing/` → `volumearc.app`) architecture + deploy flow
- [`docs/AUDIT.md`](docs/AUDIT.md) — 2026-05-01 forensic production-readiness audit + the [Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d) project that tracks burndown

The repo also contains:
- [`marketing/`](marketing/) — Next.js 16 marketing site deployed to Vercel at `volumearc.app`. Adapted from Tailwind Plus Pocket. See `docs/MARKETING.md` before changing it.
- [`relay/`](relay/) — Cloudflare Worker proxying coach prompts to Gemini.

## When to update which doc

When you change the **implementation status** of a system (a stub becomes real, a feature ships, or scope changes), update **the status row in `docs/PLATFORM.md`** in the same PR — it's the source of truth. Update `docs/FEATURES.md` for granular per-feature changes. Update `docs/ARCHITECTURE.md` only when adding or removing modules or changing the dependency graph. Don't add system-level facts directly into this file — push them down into the appropriate doc.

## Project ground rules

- The Xcode project is **generated** by `ruby scripts/generate_xcode_project.rb`. Never edit `project.pbxproj` by hand.
- Every user-facing string goes through `String(localized:comment:)`. Plural-bearing strings use `^[\(count) thing](inflect: true)`.
- Enum display labels live in `VolumeArcNative/Sources/VolumeArcUI/LocalizedLabels.swift`, not inline in views.
- Every visual property comes from `VA.Colors`, `VA.Typography`, `VA.Space`, `VA.Radius`, or `VA.Shadow` — never hardcode.
- Every haptic goes through `VAHaptics.*`.
- Main is protected: every merge requires green CI (build + unit/integration tests + UI smoke tests + SwiftLint + release validation) plus the AI review gate. **As of 2026-05-20: Codex Code Review is the sole AI reviewer** — CodeRabbit Pro is paused while the org's CodeRabbit subscription credits are restored (VOL-227 round 4). Re-enable CodeRabbit by un-commenting the `coderabbit-review` job in `.github/workflows/ai-review-gate.yml` once credits are back.

## Production-readiness status

The original post-95/95 launch blockers (VOL-55 through VOL-67) shipped in PRs [#23](https://github.com/Mabry-Ventures/mv-volumearc/pull/23)–[#31](https://github.com/Mabry-Ventures/mv-volumearc/pull/31) between 2026-04-14 and 2026-04-20. The Go-Live Readiness sweep (VOL-70 through VOL-77, VOL-89, VOL-95, VOL-100) closed the App Store submission blockers and hygiene gaps in PRs [#43](https://github.com/Mabry-Ventures/mv-volumearc/pull/43)–[#63](https://github.com/Mabry-Ventures/mv-volumearc/pull/63) between 2026-04-22 and 2026-04-23.

A **forensic production-readiness audit on 2026-05-01** (full report: [`docs/AUDIT.md`](docs/AUDIT.md)) scored the platform at **84/100** and identified 27 net-new gaps plus 10 existing tickets to close before broad launch. All 37 items are tracked in the [**VolumeArc Production Readiness**](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d) Linear project, organized into four waves over cycles 4–11 (2026-05-03 → 2026-07-12):

- **Wave 1 (cycles 4–5):** App Store submit-ready — close the four critical-severity findings (CI fork guard, dSYM upload, AI review gate blocking, marketing pages)
- **Wave 2 (cycles 6–7):** Hardening + raise coverage gate to **90%+** (VOL-140), document **100% of user journeys** (VOL-141), add snapshot regression, HK/CK fakes, iPad audit
- **Wave 3 (cycles 8–9):** Killer-app differentiators — curated programs library, HealthKit-depth coach prompt, in-app feedback, nightly response-eval CI
- **Wave 4 (cycles 10–11):** Polish + exploratory — Vision form-check V1, Apple Watch Vitals, Apple Intelligence, public coach-quality page

The app is **not yet production-ready**. Marketing pages at `volumearc.app/terms` and `/privacy`, App Store Connect metadata, screenshots, and a TestFlight review pass remain. Consult the Production Readiness project before describing any system as shipped or production-ready.

When in doubt, read [`docs/PLATFORM.md`](docs/PLATFORM.md) — it is the single source of truth and must be updated in the same PR as any status-changing code change. Past "production-ready" claims based on surface-level audits were wrong; treat the docs and Linear project as the only authoritative signal.
