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
- [`docs/RELEASE.md`](docs/RELEASE.md) — release process, versioning, TestFlight, hotfixes
- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — dev setup, branch strategy, PR process

## When to update which doc

When you change the **implementation status** of a system (a stub becomes real, a feature ships, or scope changes), update **the status row in `docs/PLATFORM.md`** in the same PR — it's the source of truth. Update `docs/FEATURES.md` for granular per-feature changes. Update `docs/ARCHITECTURE.md` only when adding or removing modules or changing the dependency graph. Don't add system-level facts directly into this file — push them down into the appropriate doc.

## Project ground rules

- The Xcode project is **generated** by `ruby scripts/generate_xcode_project.rb`. Never edit `project.pbxproj` by hand.
- Every user-facing string goes through `String(localized:comment:)`. Plural-bearing strings use `^[\(count) thing](inflect: true)`.
- Enum display labels live in `VolumeArcNative/Sources/VolumeArcUI/LocalizedLabels.swift`, not inline in views.
- Every visual property comes from `VA.Colors`, `VA.Typography`, `VA.Space`, `VA.Radius`, or `VA.Shadow` — never hardcode.
- Every haptic goes through `VAHaptics.*`.
- Main is protected: every merge requires green CI (build + unit/integration tests + UI smoke tests + SwiftLint + release validation) plus the two-bot AI review gate (CodeRabbit Pro primary + Codex Code Review secondary).

## Production-readiness status

The original post-95/95 launch blockers (VOL-55 through VOL-67) shipped in PRs [#23](https://github.com/Mabry-Ventures/mv-volumearc/pull/23)–[#31](https://github.com/Mabry-Ventures/mv-volumearc/pull/31) between 2026-04-14 and 2026-04-20. The Go-Live Readiness sweep (VOL-70 through VOL-77, VOL-89, VOL-95, VOL-100) closed the App Store submission blockers (production APS environment, paywall legal links, privacy manifest completeness, Sentry PII scrubbing) and the hygiene gaps (feature flag wiring, real SSE streaming, Liquid Glass adoption, SwiftLint scope, deterministic project generation, coach eval harness) in PRs [#43](https://github.com/Mabry-Ventures/mv-volumearc/pull/43)–[#63](https://github.com/Mabry-Ventures/mv-volumearc/pull/63) between 2026-04-22 and 2026-04-23. The app is **not yet production-ready** — marketing pages at `volumearc.app/terms` and `/privacy`, App Store Connect metadata, screenshots, and a TestFlight review pass remain. Current open work is tracked in the Linear **"Go-Live Readiness"** / **"Production Launch Quality"** projects on the VolumeArc team; consult those projects before describing any system as shipped or production-ready.

When in doubt, read [`docs/PLATFORM.md`](docs/PLATFORM.md) — it is the single source of truth and must be updated in the same PR as any status-changing code change. Past "production-ready" claims based on surface-level audits were wrong; treat the docs and Linear project as the only authoritative signal.
