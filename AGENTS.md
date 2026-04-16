# AGENTS.md — mv-volumearc

Use this file as the primary operating manual for Codex, Claude Code, and any other coding agent working in this repository.

## Project Overview
mv-volumearc is the VolumeArc web product line, currently centered on a workout/training prototype where data integrity and UX clarity matter.

**Stack:** Next.js, TypeScript, testing/visual diff scripts, product prototype workflows.

## Always Read Before Major Work
- `README.md`
- `docs/PRODUCT-CANON.md`
- `docs/CANONICAL.md`

## Role Split
- **Spock** owns scope, architecture, review discipline, canonical-doc freshness, and release readiness.
- **Claude Code** is preferred for direct local implementation when Jared is coding in that environment.
- **Codex** is preferred for structured delegated implementation and analysis through OpenClaw.
- Keep identity stable and adapt prompting style to the active model.

## Prime Directives

### D1: Memory and Documentation Freshness
- Update the real canonical docs for the product when behavior, architecture, metrics, env contracts, or release state changes.
- Do not rely on memory alone. If the change matters, write it down in the repo docs named in `docs/CANONICAL.md`.
- Timestamp-only doc refreshes do not count; capture the actual state delta.

### D2: Execution Discipline
- Every tracked task needs clear scope, acceptance criteria, and traceability.
- Update ticket / issue / PR state before reporting done.
- Reference the tracking ID in commits and PRs when one exists.

### D3: Build Verification
- Run the relevant verification commands before every push unless the change is docs-only.
- Fix failures before asking for review.
- Never treat CI as the first place to discover basic build or test breakage.

### D4: Demand Elegance
- Ask “is there a simpler way?” before every commit.
- No TODO/FIXME/HACK placeholders without a tracked follow-up.
- Match existing patterns and leave the repo cleaner than you found it.

### D5: Self-Improvement Loop
- When a bug or workflow failure teaches a repeatable lesson, update the relevant docs or guardrails instead of carrying it as tribal knowledge.
- Prefer reusable fixes, checklists, and documented patterns over one-off heroics.

### D6: Plan Before Build
- Plan files, patterns, risks, and verification before broad edits or agent delegation.
- One scoped task per branch or delegated run. No scope creep.

### D7: Model-Native Prompting
- Codex work should use structured, scope-bounded prompts with explicit verification.
- Claude Code should get direct, constraint-aware prompts without anti-laziness filler.
- All agents must review `docs/CANONICAL.md` before finalizing changes.

### D8: Canonical Docs Before Merge
- No PR merges until the affected canonical docs in `docs/CANONICAL.md` are reviewed and updated in the same branch.
- If a doc is stale for incidental reasons, fix it while you are there.
- A clean build with stale product docs is still an incomplete PR.

## Verification Commands
- `npm run lint`
- `npm run test`
- `npm run build`

## Review Guidelines
- Protect workout correctness, progress integrity, privacy, and auth behavior.
- Flag prototype shortcuts that create durable debt in data models or release-critical flows.
- Require validation for training logic, API behavior, and visual regression-sensitive surfaces.
- Treat missing or materially weakened tests for changed behavior as P1.
- Treat behavior, architecture, pricing, policy, or release changes without matching canonical doc updates as P1.
- Flag workflow steps that depend on interactive shell PATH, implicit Homebrew visibility, or host-specific machine state without explicit setup.
## Canonical Document Rule
Before a PR is merged, check `docs/CANONICAL.md`, determine which docs are affected, and update them in the same branch. Do not leave product truth or operational docs stale.

## Branch and Commit Hygiene
- Work from the correct base branch for the repo, never a guessed branch.
- Prefer small, traceable commits with clear intent.
- Do not push directly to protected branches unless explicitly directed and allowed by repo rules.

## Safety
- Never commit secrets, API keys, or sensitive user data.
- Ask before irreversible external actions when human approval materially matters.
- Prefer fixing the system over patching around the symptom.
