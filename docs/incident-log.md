# VolumeArc incident log

Append-only log of production incidents, runner outages, and rollback events. See [`docs/INCIDENTS.md`](INCIDENTS.md) for the severity ladder, alert routing, postmortem template, and per-subsystem runbooks. Postmortems themselves live in Linear under the [VolumeArc Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d) project; this file is the chronological index.

## Conventions

Each entry uses the heading `## <YYYY-MM-DD HH:MM UTC> — <short description> (<SEV>)` and includes:

- **Trigger** / **Detection**: how the incident was first noticed.
- **Impact**: who/what was affected and for how long.
- **Resolution**: the action that restored service.
- **Postmortem**: Linear ticket link (filed within 48h for SEV1/2).
- **Follow-ups**: tracked tickets that prevent recurrence.

Append new entries at the bottom; do not edit historical ones except to add the postmortem link once filed.

The `fastlane ios rollback` lane (VOL-178) automatically appends an entry for every TestFlight rollback it performs.

---

## 2026-05-10 16:14 UTC — Self-hosted runner: iOS 26.4 simulator runtime missing (SEV2)

- **Trigger**: All four Sprint 1 PRs (#144, #145, #146, #147) failed `Build & Test` on the `mv-volumearc-runner` self-hosted runner with `xcodebuild: error: ... iOS 26.4 is not installed. Please download and install the platform from Xcode > Settings > Components.` Simulator *devices* were still registered, but the runtime resolved to `(null)`.
- **Detection**: First failed run [25633019303](https://github.com/Mabry-Ventures/mv-volumearc/actions/runs/25633019303); reproduced across three additional PRs within ~5 minutes.
- **Impact**: All Sprint 1 PRs blocked from merging for ~4 hours.
- **Resolution**: `xcodebuild -downloadPlatform iOS` on the runner machine reinstalled the runtime; PRs unblocked after re-run.
- **Postmortem**: [VOL-173](https://linear.app/mabry-ventures/issue/VOL-173)
- **Follow-ups**:
  - VOL-173 hardening (PR #166): `xcrun simctl list runtimes -j` probe in `ci.yml` Pre-flight fails fast in ~1s with the precise install command instead of letting the build proceed into ~30s of confusing `xcodebuild -showdestinations` output.
  - `docs/CONTRIBUTING.md` → "Runner maintenance" section now documents the Xcode auto-update vs simulator-runtime interaction.

## 2026-05-10 23:13 UTC — Self-hosted runner: CoreSimulator version mismatch (SEV2)

- **Trigger**: After the 16:14 UTC fix, the runner began emitting `CoreSimulator daemon was upgraded but the simulator wasn't relaunched` on every `xcodebuild test` invocation, hanging tests indefinitely.
- **Detection**: Second wave of Sprint 1 PR re-runs all timed out.
- **Impact**: ~30 minutes of additional CI delay before resolution.
- **Resolution**: Reboot of the runner machine cleared the stale CoreSimulator daemon state.
- **Postmortem**: rolled into [VOL-173](https://linear.app/mabry-ventures/issue/VOL-173).
- **Follow-ups**:
  - `docs/CONTRIBUTING.md` "Runner maintenance" notes that simulator-runtime install via `xcodebuild -downloadPlatform` should be followed by a runner reboot if any tests were in-flight at install time.

## 2026-05-12 14:38 UTC — Self-hosted runner: iOS 26.5 simulator runtime missing after Xcode auto-update (SEV2)

- **Trigger**: Same shape as the 2026-05-10 16:14 UTC outage but on iOS 26.5; Xcode auto-update advanced the toolchain overnight without auto-installing the matching runtime.
- **Detection**: Recurrence rate confirmed the auto-update root cause.
- **Impact**: ~1h of CI delay before manual runtime install.
- **Resolution**: `xcodebuild -downloadPlatform iOS` again.
- **Postmortem**: rolled into [VOL-173](https://linear.app/mabry-ventures/issue/VOL-173) — explicitly motivated the Pre-flight gate (PR #166) and the auto-update hardening guidance in `docs/CONTRIBUTING.md`.

---

_No production (App Store) incidents to date. The first such entry will be appended automatically by `fastlane ios rollback` and supplemented manually with the rollback's postmortem link._
