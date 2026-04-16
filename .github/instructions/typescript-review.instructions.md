---
applyTo: "**/*.{ts,tsx,js,jsx,mjs,cjs}"
---
# TypeScript and web review rules

- Prioritize auth, secrets, privacy, billing, telemetry honesty, and user-facing behavior regressions.
- Treat missing or weakened validation for changed behavior as important.
- Flag trust-boundary changes that lack explicit validation, sanitization, or error handling.
- Confirm behavior changes also update the affected canonical docs named in `docs/CANONICAL.md`.
- Ignore formatting-only nits already enforced by tooling.
