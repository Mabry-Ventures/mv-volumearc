# Canonical Documents — mv-volumearc

These are the documents and instruction surfaces that must stay fresh. Any PR that changes behavior, UX, architecture, metrics, pricing, integrations, environment contracts, release state, or operational expectations must update the affected docs below in the same branch before merge.

## Rules
- Review this file during planning and again before requesting review.
- If a doc is stale for incidental reasons, fix it while you are already in the repo.
- A code-complete PR with stale canonical docs is not done.

## Canonical Documents
- `AGENTS.md` — Primary agent operating contract for Codex and Claude Code.
- `CLAUDE.md` — Claude Code entry point; inherits AGENTS.md and repo-specific guidance.
- `README.md` — Project overview and local workflow.
- `docs/PRODUCT-CANON.md` — Authoritative product truth and workflow guardrails.
- `docs/CANONICAL.md` — This file, the doc-freshness routing table.
- `.github/copilot-instructions.md` — Repo-specific review priorities for Copilot and human reviewers.
- `.github/pull_request_template.md` — PR checklist enforcing validation and canonical-doc review.
- `.github/instructions/*.instructions.md` — Path-specific Copilot review rules for language and package surfaces.
- `.github/workflows/self-hosted-runner-canary.yml` — Manual and scheduled self-hosted runner environment canary.
