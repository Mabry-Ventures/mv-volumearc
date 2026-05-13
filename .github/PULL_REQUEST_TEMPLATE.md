## Summary
<1-3 sentences on what changes and why>

## Linked ticket
- Closes [VOL-XXX](https://linear.app/mabry-ventures/issue/VOL-XXX)

## Acceptance criteria
- [ ] <from the Linear ticket>

## Test plan
- [ ] <how to verify>

## Security checklist (VOL-157)
- [ ] No secrets, API keys, signing identities, or `.p12` files in the diff
- [ ] No new PII surfaces in logs, breadcrumbs, or telemetry events (see `docs/SECURITY.md`)
- [ ] No entitlement change without a corresponding `validate_release_config.sh` update + manual sanity pass
- [ ] If touching the AI relay, Sentry config, or CloudKit container: cross-reference `docs/SECURITY.md` "Network egress" + "PII handling" sections
- [ ] If adding a new third-party processor or network host: update `docs/SECURITY.md` egress table + App Store privacy questionnaire

## Screenshots (UI changes only)
<drag images here>

## Notes for reviewers
<anything non-obvious>
