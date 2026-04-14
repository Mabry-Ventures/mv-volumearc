# AGENTS.md - Beast Mode Web Prototype

You are working on the Beast Mode web prototype for the VolumeArc product line.

## Review guidelines

- Treat workout correctness, user progress integrity, auth, billing, and privacy as highest severity.
- Flag any change that could corrupt workout history, plans, readiness state, or mobile relay behavior.
- Prefer minimal changes that preserve the current architecture and avoid widening prototype debt.
- Call out missing tests or missing validation for training logic, API behavior, and release-critical user flows.
- Avoid secrets, noisy logs, and unsafe server-side behavior.
