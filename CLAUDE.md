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
- [`docs/AUDIT.md`](docs/AUDIT.md) — forensic production-readiness audits and launch findings
- [`docs/VOLUMEARC_RELEASE.md`](docs/VOLUMEARC_RELEASE.md) — active VolumeArc Release initiative, blocker ledger, and 9.5+ scorecard gate

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
- Main is protected by required CI and an agentic review aggregate. The review workflow requests a current-head Codex Code Review signal; Gemini Code Assist provides independent advisory feedback when available.

## Release status

VolumeArc is pre-launch. Active launch work now rolls up to the [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) initiative and the release operating plan in [`docs/VOLUMEARC_RELEASE.md`](docs/VOLUMEARC_RELEASE.md).

The release bar is strict: every world-class scorecard category must be 9.5 or higher, every P0-P4 finding must be closed or explicitly accepted by Jared, and Apple build/test/performance/UAT/App Store evidence must be green before paid public launch.

The app is not yet launch-ready. Consult `docs/PLATFORM.md` for implementation truth, `docs/AUDIT.md` for findings, and `docs/VOLUMEARC_RELEASE.md` for the active blocker ledger before describing any surface as ready for public paid launch.

When in doubt, read [`docs/PLATFORM.md`](docs/PLATFORM.md) — it is the single source of truth and must be updated in the same PR as any status-changing code change. Past readiness claims based on surface-level audits were wrong; treat the docs and VolumeArc Release initiative as the authoritative signal.

<!-- BEGIN MABRY VENTURES WEB-21 CLAUDE ADDENDUM -->
## Mabry Ventures WEB-21 Claude Code Addendum

Start by reading `AGENTS.md`, then the Linear issue. Treat the WEB-21 operating contract in `AGENTS.md` as binding alongside this repo's canonical docs.

Claude-specific workflow:
- Use plan mode before production, billing, auth/security, data migration, App Store, DNS, credential, permissions, external integration, or destructive changes.
- Preserve the suggestion-first Linear workflow. Propose labels/assignees/status/project/cycle/related links before applying them unless Jared explicitly asks.
- Use Code Intelligence or repo search to cite likely files before broad implementation.
- Do not enable Linear MCP, Extend access to all members, or new external connectors from this repo context without explicit approval.
- Final handoff must include Linear issue, branch/PR, files changed, validation run, tests skipped, remaining risk, and next owner action.
<!-- END MABRY VENTURES WEB-21 CLAUDE ADDENDUM -->
