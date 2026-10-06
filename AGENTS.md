# VolumeArc — Agent Guide

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
- Preserve branch protection and exact-candidate release gates. GitHub Actions and hosted automatic review were disabled at the 2026-10-04 audit; old fleet documentation is not evidence of an active or passing pipeline. Apple qualification belongs locally first, then in Xcode Cloud.

## Release status

VolumeArc is pre-launch. Active launch work now rolls up to the [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) initiative and the release operating plan in [`docs/VOLUMEARC_RELEASE.md`](docs/VOLUMEARC_RELEASE.md).

The release bar is strict: every world-class scorecard category must be 9.5 or higher, every P0-P4 finding must be closed or explicitly accepted by Jared, and Apple build/test/performance/UAT/App Store evidence must be green before paid public launch.

The app is not yet launch-ready. Consult `docs/PLATFORM.md` for implementation truth, `docs/AUDIT.md` for findings, and `docs/VOLUMEARC_RELEASE.md` for the active blocker ledger before describing any surface as ready for public paid launch.

When in doubt, read [`docs/PLATFORM.md`](docs/PLATFORM.md) — it is the single source of truth and must be updated in the same PR as any status-changing code change. Past readiness claims based on surface-level audits were wrong; treat the docs and VolumeArc Release initiative as the authoritative signal.

## CI and review budget

Use the included Ubuntu GitHub runners for portable CI. GitHub Mac and self-hosted
runners require a new, explicit owner exception; do not add dynamic runner labels.
Run affected Apple build, simulator, unit/UI and platform checks locally on the
exact candidate first, then manually admit the matching Xcode Cloud validation.
Local proof, cloud proof, signing and distribution remain separate gates.

Keep hosted PRs draft while iterating. VolumeArc automatic Codex review is
disabled; use one explicitly requested primary review for the final candidate.
Fresh evidence is required when material changes invalidate that review. A quota/credit refusal is unavailable evidence,
never approval. Preserve this repo's required checks and reviewer authority.
Do not retry identical review requests or buy credits automatically.
See [CI economy](docs/CI-ECONOMY.md) for runner and cloud admission policy.
