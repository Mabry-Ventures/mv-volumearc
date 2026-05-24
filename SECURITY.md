# Security Policy

Mabry Ventures, LLC (Nashville, Tennessee) takes the security of the VolumeArc iOS / watchOS app, the supporting Cloudflare Worker relay, and the marketing site at `volumearc.app` seriously.

This file is the front door for security disclosures and points at the in-depth threat model, response timelines, and operational runbooks already maintained in the repo.

## Reporting a vulnerability

Email **security@volumearc.app**.

Please include:

- A clear description of the vulnerability
- Steps to reproduce, or the closest you have to a working PoC
- The affected component (iOS app, watchOS app, marketing site, relay worker, GitHub Actions config, etc.)
- Your contact info for follow-up
- Whether you intend to publish a public writeup, and on what timeline

We acknowledge receipt within **2 business days** and commit to:

- Triage + severity assessment within **5 business days**
- Critical (RCE, account compromise, mass data exfiltration): mitigation in flight within **24 hours** of validation
- High (data leak under specific conditions, auth bypass for a single account): mitigation in next release
- Medium / Low: tracked in Linear and addressed per priority

Coordinated disclosure is preferred. We commit to **not** pursuing legal action against good-faith researchers operating within the spirit of this policy.

## In-depth documentation

Detailed material lives in [`docs/SECURITY.md`](docs/SECURITY.md), which covers:

- Threat model (assets, adversaries, mitigations)
- Network egress allowlist
- App Attest-only authentication for the coach relay
- Keychain vs UserDefaults policy
- PII handling and the privacy-mode redactor
- Vulnerability surface monitored continuously (TruffleHog, Dependabot, AI review gate)

Operational incident response runbooks live in [`docs/INCIDENTS.md`](docs/INCIDENTS.md).

The user-facing privacy disclosure is at <https://volumearc.app/privacy>.
