# Solo-developer CI policy

Owner decision, October 4, 2026: keep included GitHub-hosted Linux runners.
GitHub Mac and unregistered self-hosted runner routes are prohibited. An
exception requires Jared's explicit approval of the exact workflow/commit,
purpose, maximum runtime and expiry before allocation. A manual-dispatch
button or a positive credit balance is not that approval.

Run `python3 scripts/check-ci-policy.py` (PyYAML 6.0.3) before pushing workflow
changes. The workflow check is defense in depth, not a platform-level runner
ban; another workflow can allocate before it finishes. Standard hosted runners
remain enabled to preserve the included Linux allowance.

Apple work: qualify the exact clean candidate locally first (build, analysis,
affected unit/integration/UI tests, iPad/watch/macOS destinations where relevant,
and documented skips); record the commit, toolchain, commands and results.
Only then manually admit that candidate to Xcode Cloud. Do not trigger Apple
CI to discover compile failures. Keep archives/distribution separate from
validation; preserve independent release approvals and installed-device proof.

Use one hosted review request per final candidate head, with local review during
iteration. Review failures and provider quota errors must stay merge-blocking
where required; missing review is never a pass. Do not retry the same refusal
in a polling loop. Avoid combining automatic every-push reviews with duplicate
manual requests. Deep/exhaustive review is reserved for release or risk-specific
work. Retain current production, security and exact-head gates.

Cancel superseded PR compute, but never interrupt production migrations or
custom-check finalization. Use explicit job timeouts; do not reduce tests or
coverage floors to fit a timeout. Preserve the current 90-day global evidence
retention; shorten only disposable artifacts. GitHub paid overage remains $0;
Xcode Cloud remains on its current tier. No auto-reload or credit spending is
implied by this policy.

## VolumeArc migration state

The absent self-hosted fleet recipes are preserved as non-executable references
under docs/retired-ci. GitHub Actions was disabled at the audit and must remain
disabled until the portable workflows and branch checks are qualified. No green
replacement check may stand in for native Build & Test or generator proof.

Run scripts/local-apple-preflight.sh on the committed candidate, followed by
VOL-PR and VOL-Main local test plans and relevant real-device journeys. These
checks are required before manually starting the matching Xcode Cloud workflow.
VolumeArc PR and VolumeArc Main use manual admission and Xcode 26.6 (17F113).
The former Xcode 26.5 image is no longer selectable; Xcode 27 rejects the current
legacy WatchKit extension, so validation stays on the supported 26.6 image.
Locally, set `DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer`
and `WATCHOS_TEST_OS=26.5` when newer simulator runtimes are also installed.
The separate archive lane is unchanged; its qualification remains a release gate.
The native UAT and coach-eval reference recipes remain separate qualification
work, not a passing hosted gate or an automatic nightly charge.

The trusted policy workflow checks candidate YAML as data using only the base
revision checker. Candidate checker/tests execute separately in the unprivileged
PR lane. Both are path-scoped; no candidate program runs in pull_request_target.
New trusted workflow definitions become active only after integration.
