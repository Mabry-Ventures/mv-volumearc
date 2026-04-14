# Beast Mode web prototype code review style guide

Review every change for the following:

- Protect workout correctness, training history, sync integrity, and user trust.
- Flag privacy leaks involving health-adjacent data, account information, voice content, or relay credentials.
- Treat bugs that can corrupt plans, workout logs, or backend/mobile relay behavior as critical.
- Prefer small, maintainable fixes that match the current architecture.
- Require relevant validation for API behavior, training logic, and release-critical flows.
