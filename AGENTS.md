# AGENTS.md

This file provides durable repository guidance for Codex, Codex Code Review, CodeRabbit Pro, and other coding agents.

## Repository expectations

- Read the repository README, package/tooling files, and nearby source before making changes.
- Keep changes scoped to the requested behavior and consistent with the existing architecture.
- Do not introduce hardcoded secrets, production credentials, broad permissions, or destructive data operations.
- Prefer existing project patterns, scripts, helpers, and design-system primitives over new abstractions.
- If behavior changes, update the relevant docs in the same branch.

## Verification

- Run the smallest relevant lint, typecheck, build, or test command that validates the change.
- Add or update tests when product behavior, public APIs, persistence, auth, billing, or release logic changes.
- If verification cannot run locally, state the blocker and the exact command that should be run.

## Review guidelines

Codex Code Review and CodeRabbit Pro are enabled on this repository. Both should stay focused on high-signal review findings:

- Treat security, privacy, auth, authorization, secrets, data loss, billing, release, CI, and migration risks as P0/P1 findings.
- Treat missing or weakened tests for changed behavior as P1 unless the PR clearly explains why tests are not needed.
- Treat stale product, architecture, privacy, pricing, release, or canonical documentation after behavior changes as P1.
- Flag accessibility, performance, metadata/SEO, analytics/privacy, and user-facing regression risks when they are material.
- Avoid style-only comments and formatting nits that lint, formatters, or existing tests already cover.
- Prefer a small number of actionable findings with concrete file/line evidence over broad commentary.
- When reviewing agent-generated code, verify it preserves existing architecture boundaries and does not introduce hidden coupling, speculative abstractions, or unsafe shortcuts.

