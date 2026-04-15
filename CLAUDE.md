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
- Enum display labels live in `VolumeArcKit/Sources/VolumeArcUI/LocalizedLabels.swift`, not inline in views.
- Every visual property comes from `VA.Colors`, `VA.Typography`, `VA.Space`, `VA.Radius`, or `VA.Shadow` — never hardcode.
- Every haptic goes through `VAHaptics.*`.
- Main is protected: every merge requires green CI (build + unit/integration tests + UI smoke tests + SwiftLint + release validation) plus the two-bot AI review gate (Gemini + Codex).

## Known launch blockers (post-95/95 audit)

The project is **not** production-ready as of 2026-04-14. An independent audit found multiple systems with broken end-to-end wiring (empty migration plan, missing Info.plist keys, unreachable onboarding/paywall, dead feature flags). See [the launch-blocker section in `docs/PLATFORM.md`](docs/PLATFORM.md#implementation-status) and the active **VOL-54 through VOL-69** tickets in Linear before describing any system as "shipped" or "production-ready". The 95/95 score from the previous push was wrong — the surface-level audits I ran caught code paths but not end-to-end wiring, and the auditor caught what I missed. Treat the docs as the source of truth, not previous status messages.
