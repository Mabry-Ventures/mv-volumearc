When reviewing this repository:
- Prioritize correctness, regressions, data loss, privacy, security, performance cliffs, and migration safety.
- Respect the repository's standards in AGENTS.md and CLAUDE.md if present.
- For Swift code, focus on platform availability, Swift concurrency, actor isolation, persistence migrations, CloudKit sync behavior, and test coverage gaps.
- Flag risky edge cases clearly, especially anything that could break fresh installs, upgrades, sync, or user data integrity.
- Prefer a small number of high-signal findings over stylistic nits.
- Classify findings as critical, important, or nit.
- If no material issues are present, say so briefly instead of inventing feedback.
