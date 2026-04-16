When reviewing this repository:
- Respect `AGENTS.md`, `CLAUDE.md`, and `docs/CANONICAL.md` as the operating contract.
- Prefer a small number of high-signal findings over stylistic nits.
- Classify findings as critical, important, or nit.
- Confirm the PR updated the affected canonical docs before approving behavior-changing work.
- Protect workout correctness, progress integrity, privacy, and auth behavior.
- Flag prototype shortcuts that create durable debt in data models or release-critical flows.
- Require validation for training logic, API behavior, and visual regression-sensitive surfaces.
- If no material issues are present, say so briefly instead of inventing feedback.
