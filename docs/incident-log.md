# VolumeArc incident log

Append-only log of production incidents, runner outages, and rollback events. See [`docs/INCIDENTS.md`](INCIDENTS.md) for the severity ladder, alert routing, postmortem template, and per-subsystem runbooks. New postmortems live in Linear under the [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) initiative; this file is the chronological index.

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

## 2026-05-14 04:30 UTC — Self-hosted runner: disk full (4 GB free, needs 10 GB) (SEV2)

- **Trigger**: After a multi-PR (5 simultaneous fixup cycles) Sprint 3 wave, accumulated DerivedData + SPM caches + retained xcresult bundles drove `$HOME` disk free below the VOL-173 Pre-flight 10 GB floor. PR #167 (VOL-178) was the first to fail Pre-flight with `Disk has only 4GB available (need >=10GB)`. PRs #169 + #158 hit the same wall on their next CI cycle.
- **Detection**: Pre-flight Disk-avail check (added in PR #166 / VOL-173) caught it in ~1 second and surfaced the exact failure cause in the workflow log. Without that check the next 30+ min of `xcodebuild` would have wasted runner time on a doomed build.
- **Impact**: ~30 minutes of CI delay across three open PRs while the runner host was cleaned (`rm -rf ~/Library/Developer/Xcode/DerivedData/* && xcrun simctl delete unavailable`).
- **Resolution**: Manual cleanup on the runner; verified post-cleanup with retriggered CI on all three PRs (all then passed Build & Test).
- **Follow-ups**: explicit motivation for the disk-space watchdog cron noted in `docs/CONTRIBUTING.md` "Runner maintenance." A daily `launchd` job flagging <50 GB free would warn us before Pre-flight trips.

## 2026-05-14 13:22 UTC — Admin-merge bypass for VOL-142 (the former reviewer + Codex bot unavailability) (SEV3)

- **Trigger**: After PR #158 (VOL-142) was rebased four times through the Sprint 3 fixup cycle, both the former review bot and `chatgpt-codex-connector[bot]` stopped posting review signals despite the AI Review Gate's `Request AI Reviews` step firing successfully. Three empty-commit retriggers and explicit review requests to both bots drew no response for ~8 hours. The most recent bot review was on the 5th of 6 fixup SHAs (`8624812260`, 05:32 UTC); the current head and three empty commits received no response.
- **Detection**: Three consecutive `Wait for ${AI} review signal` job timeouts on the AI Review Gate workflow over a 90-minute window after the underlying Build & Test, Trufflehog, and code review (on prior SHAs) all passed cleanly.
- **Impact**: PR #158 sat behind a former-reviewer and Codex unresponsiveness window despite the underlying VOL-142 production fix (StoreKit revocation) being verified by:
  - Build & Test green on **four consecutive SHAs** (the latest empty-commit triggers added no source changes vs the SHA Codex commented on earlier in the cycle)
  - Trufflehog green on the same set
  - Earlier-SHA reviews from both bots (Codex on `fd7159f8c2`, the former reviewer on `8014cd6085`) — the substantive code changes were vetted before the bot outage began
- **Resolution**: Owner-approved `gh pr merge 158 --squash --admin` bypass at 13:22 UTC after explicit confirmation. The merge commit (`4ea5f508ba`) is on main; CI on main confirms the change is green there too.
- **Follow-ups**:
  - **[VOL-172](https://linear.app/mabry-ventures/issue/VOL-172)** (AI review gate: distinguish "rate-limit notice" from a real review signal) is the long-term fix; the current gate has no way to detect "bot is rate-limited" and treats silence as failure.
  - This is the **first** admin-bypass merge on main since the AI review gate was promoted to required ([VOL-134](https://linear.app/mabry-ventures/issue/VOL-134) / 2026-05-03). The bypass is documented per `docs/CONTRIBUTING.md` "Bypass / emergency hotfix" convention.

## 2026-05-20 02:51 UTC — Self-hosted runner: cascading flake cluster + disk-full (SEV2)

- **Trigger**: 2026-05-19 overnight Sprint 1 burndown opened eight PRs in quick succession (#236-243) plus mitigations (#244 sim-wedge fail-fast, #241 channel-disconnect retry, #246 Codex-only gate). Within ~3 hours of the first batch landing in the runner queue, every PR began failing with `xctest encountered an error (Channel disconnected)`. By 03:30 UTC, additional PRs were hitting a separate `Waiting on System App` symptom — `xcrun simctl bootstatus -b` hanging for 18+ minutes before the outer 20-min wall-clock killed xcodebuild with exit 137.
- **Detection**: Pattern emerged across 3+ failed runs of independent PRs within an hour. First failed run [26137224653](https://github.com/Mabry-Ventures/mv-volumearc/actions/runs/26137224653) on PR #236 (VOL-231 sharding); reproduced on #237, #238, #241 with identical channel-disconnect signature, then #237, #238 hit the sim-wedge signature on rerun.
- **Impact**: Eight PRs (the entire Sprint 1 burndown plus the CI mitigations) blocked from merging for roughly 12 hours. The cascading flakes made it impossible to admin-merge: every PR had at least one infra-failure status check, and the failure modes were diverse enough that "blocked only on infra flake" couldn't be cleanly attributed until we found the root cause.
- **Root cause** (uncovered ~7h into the outage by inspecting PR #236's failed build log): `'No space left on device'` errors in the iPhoneSimulator module-cache writes. The runner's `$HOME` had filled — likely from accumulated `~/Library/Developer/CoreSimulator/Caches/` + `Logs/CoreSimulator/` after the previous Sprint 1 batch tests. Module-cache write failures cascaded into:
  - `Could not build module 'os_object' / 'XPC' / 'SwiftShims'` (clang dependency scanning),
  - half-booted launchd_sim processes (orphan System App wedge),
  - xcresult bundles that couldn't finalize (downstream Coverage gate `Failed to load result bundle`),
  - xctest test-runner `SIGKILL` before bootstrap (memory pressure paired with disk pressure).

  Each symptom looked distinct in CI logs but all rooted in the same disk exhaustion.
- **Resolution**: Owner ran the runner-host cleanup (the four high-yield disk paths) + Xcode auto-update / OS upgrade. PRs cleared their queue + rebased against `main` (which now contains #244's sim-wedge fail-fast mitigation) to inherit the fix.
- **Postmortem**: rolled into the **CI runner flake taxonomy** added to [`docs/TESTING.md`](TESTING.md#ci-runner-flake-taxonomy-vol-227-cluster) so the next on-call has an attribution table for the six recurring infrastructure flakes. The "Runner-host operational notes" subsection there catalogues the three host-level intervention paths (disk-full, orphan launchd_sim, memory pressure) that no PR can fix.
- **Follow-ups**:
  - PR #244 (VOL-227 round 3) — `simctl bootstatus -b` wallclock prevents the sim-wedge from burning 18 min per run going forward. Already on main.
  - PR #241 (VOL-227 round 2) — channel-disconnect retry on unit tests. Pending merge (was blocked on the runner being down).
  - PR #246 (VOL-227 round 4) — Codex-only AI review gate while the former reviewer usage credits are restored. Pending merge.
  - **[VOL-243](https://linear.app/mabry-ventures/issue/VOL-243)** — daily runner-host disk-pressure watchdog. The follow-up flagged in the 2026-05-14 04:30 UTC postmortem went un-actioned for 6 days, which is what allowed this cascade. Filed as a dedicated tracker; once landed, a 50 GB free-disk floor will warn before the 10 GB Pre-flight hard floor trips.

---

_No production (App Store) incidents to date. The first such entry will be appended automatically by `fastlane ios rollback` and supplemented manually with the rollback's postmortem link._
