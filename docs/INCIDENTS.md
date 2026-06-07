# Incident response runbook

> **Scope:** what to do when something is on fire in a shipped VolumeArc build. Covers Sentry alert response, severity classification, communication, and the canonical fix paths for common failure shapes.
>
> **Companion docs:** [`docs/RELEASE.md`](RELEASE.md) (rollback mechanics + hotfix process), [`docs/SECURITY.md`](SECURITY.md) (privacy / PII handling), [`docs/CHAOS.md`](CHAOS.md) (fault-injection patterns that can repro production issues in test).

## Severity ladder

| Severity | Definition | Response time | Examples |
|---|---|---|---|
| **SEV1** | Production-down or data-loss event affecting all users | Acknowledge within 15 min, mitigation in flight within 1 hour | Cold-launch crash for >5% of sessions (crash-free-sessions < 95%), CloudKit data corruption, paywall stuck preventing all purchases, App Store metadata pulled |
| **SEV2** | Major feature broken for many users, but the app still launches | Acknowledge within 1 hour, fix in next release | Coach relay 5xx for >30 min, Watch sync stalled, Live Activity not appearing, widget snapshot stale for all users |
| **SEV3** | Feature broken for some users or in some configurations | Acknowledge within 1 business day, fix in next planned release | Specific exercise illustration missing, screen reader misses a label, one localization missing a string |
| **SEV4** | Cosmetic, minor, or single-user issue | File for normal triage cadence | Off-by-one in a count, a typo, a rare race condition with no user impact |

The crash-free-sessions thresholds (95% for SEV1, 99.5% for the Sentry alert rule) are deliberately strict because we're a small team and a small surface — we don't have the volume to absorb a sustained outage without losing trust. Re-evaluate the thresholds quarterly as install base grows.

## Alert routing (Sentry)

The production Sentry project (`mabry-ventures-llc/volumearc-ios`) has the following alert rules wired (or scheduled to be wired — see VOL-156 Phase 2):

| Rule | Threshold | Channel | Severity |
|---|---|---|---|
| **Crash-free sessions** | < 99.5% over 1-hour window for any release | Pager + `#volumearc-incidents` | SEV1 |
| **New error type** | First-seen error fingerprint with > 10 occurrences in 1 hour | Slack `#volumearc-incidents` | SEV2 (escalate to SEV1 if widespread) |
| **Release health regression** | Any release where session-error-rate is 2× the prior release's rate | Slack `#volumearc-incidents` | SEV2 |
| **Sentry quota** | > 80% of monthly events budget consumed | Slack `#volumearc-eng` (informational) | SEV4 |

Pager destination is configured in Sentry's notification rules per release. For the v1.0 launch period, all SEV1 alerts route to the founder's pager via PagerDuty integration; pager rotation lands once the team grows past one.

## Communication channels

| Channel | Purpose | Audience |
|---|---|---|
| `#volumearc-incidents` (Slack) | Active incident chat. One channel per incident is overkill at our size; thread per incident inside the same channel | Eng + founder |
| `#volumearc-eng` | General eng discussion, non-urgent ops notifications | Eng |
| GitHub Issues + Linear | Incident postmortem ticket | Public-facing (Linear is private to org) |
| Status page (`status.volumearc.app`, deferred) | User-facing degradation acknowledgment | All users |

Status page is intentionally deferred until install base warrants it — for now, in-app degradation banners (VOL-167 ticket cluster) communicate to the user directly.

## Postmortem template

After any SEV1 or SEV2 incident, the on-call responder files a Linear ticket using this template. The goal is forensic clarity, not blame; the "five whys" matter more than the "who."

```markdown
# Incident YYYY-MM-DD: <one-line summary>

**Severity:** SEV1 | SEV2 | SEV3 | SEV4
**Started:** YYYY-MM-DD HH:MM UTC (first user impact)
**Detected:** YYYY-MM-DD HH:MM UTC (first alert / report)
**Mitigated:** YYYY-MM-DD HH:MM UTC (rollback / fix deployed)
**Fully resolved:** YYYY-MM-DD HH:MM UTC (final fix landed on main, monitoring clean)
**Sentry release:** com.mabryventures.VolumeArc@<version>+<build>
**Incident channel:** thread link in `#volumearc-incidents`

## Summary

One paragraph: what broke, what users experienced, what we did.

## Impact

- Users affected: <count or % of DAU>
- Functional surface: <which features were degraded>
- Duration: <X minutes / hours>
- Data loss: yes / no (if yes, scope)

## Timeline

| Time (UTC) | Event |
|---|---|
| HH:MM | Deploy / config change that introduced the bug |
| HH:MM | First user-visible symptom |
| HH:MM | Sentry alert fired |
| HH:MM | Responder acknowledged |
| ... | ... |
| HH:MM | Mitigation deployed |
| HH:MM | Monitoring clean |

## Root cause

Five whys, ending at the systemic cause (not "the developer made a mistake" — *why* did the mistake get to production?).

## What went well

- ...

## What went poorly

- ...

## Action items

| Item | Owner | Linear | Severity |
|---|---|---|---|
| Add regression test for X | @claude | VOL-XXX | High |
| Document Y in CONTRIBUTING.md | @jared | VOL-XXX | Medium |
| ... | | | |

Each action item MUST have a Linear ticket. "We'll be more careful" is not an action item.
```

## Common-issue runbooks

These are the failure shapes most likely to fire alerts based on our current architecture. Each runbook is forensic — read top-to-bottom during the incident, file action items via the postmortem template at the end.

### Relay 5xx (coach unavailable)

**Symptom:** Sentry alert "coach.relay_error" rate elevated. Users see the fallback heuristic banner ("Coach is temporarily limited") for streaming requests.

**Probable causes (descending likelihood):**
1. **Cloudflare Worker error** — `relay.volumearc.app` returning 5xx from `relay/src/worker.ts`. Check the Cloudflare dashboard's Worker analytics tab; spike correlates with a recent worker deploy.
2. **Gemini upstream outage** — Worker is forwarding 5xx from `generativelanguage.googleapis.com`. Check [Google AI Studio status](https://status.cloud.google.com/) for the GenAI tag.
3. **Auth-token expiry** — the Worker rotates session tokens via VOL-AUTH-XXX; if rotation fails, every request 401s and the Worker maps to 503. Check `wrangler tail relay` for token-refresh errors.

**Mitigation:**
- If Worker-side: rollback the worker via `wrangler deployments list` + `wrangler rollback`.
- If Gemini-side: no action available; the app's local heuristic provider already serves degraded responses. Communicate via in-app banner (existing).
- If auth-side: rotate the upstream API key in Cloudflare secrets, redeploy.

**Verify:** `curl -X POST https://relay.volumearc.app/v1/coach/stream -d '{"prompt":"test"}' -H 'Authorization: Bearer <token>'` returns 200 with a streaming body.

### CloudKit auth failure (sync stalled)

**Symptom:** `cloudsync.auth_failed` telemetry spike. Users may see sync-pending indicators that never clear.

**Probable causes:**
1. **Apple ID signed out** — single-user issue; the user resigned in.
2. **iCloud quota exceeded** — user's private database is full. App should surface "iCloud storage full" alert via the existing iCloud error mapping.
3. **CloudKit schema deployment lag** — after a new SwiftData schema version ships, CloudKit's record-type metadata can take 10–15 min to propagate to the public production environment. Check [CloudKit dashboard](https://icloud.developer.apple.com/dashboard/) for the production environment status.
4. **CloudKit container misconfiguration** — entitlement mismatch or container ID drift. Check `App/VolumeArc.Release.entitlements` matches the dashboard's container.

**Mitigation:**
- For schema lag: wait. Sync will resume once propagation completes. No code change.
- For container misconfig: revert to the prior signed entitlement; file a Linear ticket to investigate the mismatch before re-deploying.

### Paywall stuck (purchase failures)

**Symptom:** `subscription.entitlement.purchase_pending` telemetry spike OR users report tapping a plan with no response.

**Probable causes:**
1. **App Store Connect outage** — purchase flow hits Apple's IAP server. Check Apple's [System Status](https://www.apple.com/support/systemstatus/) for "App Store" rows.
2. **Product not in App Store** — somebody pulled or paused a product in ASC. Check the products list under our app's "In-App Purchases" tab.
3. **Receipt validation failure** — see VOL-142 P2's receipt-validation tests once they land; for now, force-refresh via `restorePurchases()`.

**Mitigation:**
- If ASC-side: communicate via in-app banner; no code action.
- If product-pulled: re-enable the product in ASC. No app change required — once the product is live again, the next launch resolves.

### dSYM upload broken (post-release, before deploy)

**Symptom:** New TestFlight build uploaded but Sentry's Debug Files tab doesn't show the dSYM for the matching release tag. Future crashes from that build will surface as un-symbolicated stack traces.

**Probable causes:**
1. **`SENTRY_AUTH_TOKEN` expired** — most common. Sentry user tokens last 1 year by default.
2. **`ci_post_xcodebuild.sh` failed silently** — Xcode Cloud's post-action ran but `sentry-cli` errored. Check the Xcode Cloud build log for "sentry-cli debug-files upload" output.
3. **dSYM path mismatch** — recent generator change moved the dSYM output dir. Check `archive_for_distribution.sh` against the post-action's expected path.
4. **Bundled `Sentry.framework` UUID mismatch** — Xcode may thin/process the SwiftPM framework so the vendor XCFramework dSYM no longer matches the archived binary. `ci_post_xcodebuild.sh` and `fastlane ios beta` generate `Sentry.framework.dSYM` from the archived framework before upload; if that step is missing, framework frames can remain un-symbolicated.

**Mitigation:**
- For token expiry: rotate in Sentry (`Settings → Account → API → Auth Tokens` → create new with `project:write`), update the GitHub `SENTRY_AUTH_TOKEN` secret AND the Xcode Cloud env var.
- Manual upload as a one-off: generate the framework companion with `dsymutil <path-to-Archive.xcarchive>/Products/Applications/VolumeArc.app/Frameworks/Sentry.framework/Sentry -o <path-to-Archive.xcarchive>/dSYMs/Sentry.framework.dSYM`, then run `sentry-cli debug-files upload --include-sources <path-to-Archive.xcarchive>/dSYMs/`. Don't ship a release without dSYMs; un-symbolicated production crashes are nearly impossible to action.

### Sentry DSN missing from TestFlight build

**Symptom:** A TestFlight build installs, but Sentry receives no crashes, sessions, feedback, or performance events from that build. `VolumeArcSentryDSN` is empty in the archived app `Info.plist`.

**Mitigation:**
- Set `SENTRY_DSN` in the Xcode Cloud archive workflow and local release shell. It is a public client DSN, not the Sentry auth token.
- Set `VOLUMEARC_AI_RELAY_URL=https://relay.volumearc.app` in the same release environment; a build with Sentry but no cloud relay still produces misleading TestFlight coverage.
- Re-archive and verify `VolumeArcSentryDSN` is non-empty and `VolumeArcAIRelayURL` is `https://relay.volumearc.app` before upload. `ci_post_xcodebuild.sh` and `scripts/validate_release_config.sh` now hard-fail production-signed archives that omit either value.
- Do not call a TestFlight build release-ready until both DSN initialization and dSYM upload have been proven for the exact build number.

### App Store metadata pulled

**Symptom:** App Store listing returns 404 / "App not available" for users searching.

**Probable causes:**
1. **Apple review removal** — Apple flagged the app for a guideline violation. Check the email tied to the developer account; Apple posts the rejection reason in App Store Connect's Resolution Center.
2. **Manual ASC pull** — somebody on our side hit "Remove from Sale." Check the ASC audit log under `Settings → People → Activity`.
3. **Auto-pull due to tax / banking** — agreement lapsed. Check `Agreements, Tax, and Banking` in ASC.

**Mitigation:** Address the underlying cause; Apple will re-list within 24h of the issue being resolved. There is **no automated rollback** for App Store visibility — manual ASC operation only.

## Rollback procedures

See [`docs/RELEASE.md`](RELEASE.md#rollback) for the canonical mechanic. The short version:

- **TestFlight** (VOL-178): run `bundle exec fastlane ios rollback build:<N> reason:"<one sentence>" severity:SEV2`. The lane validates the target build, prints the operator walk-through for the App Store Connect UI swap, and auto-appends an entry to `docs/incident-log.md`.
- **App Store**: there is no automated rollback. The fastest mitigation is to ship a hotfix (see RELEASE.md "Hotfix process"). For SEV1, file an "Expedited review request" at [developer.apple.com/contact/app-store/?topic=expedite](https://developer.apple.com/contact/app-store/?topic=expedite) and submit the hotfix via `fastlane ios release` pointing at the rollback target. The operator may also walk through ASC's "Phased Release" pause flow to slow the bleed while the hotfix is in review.

After every rollback, the `fastlane ios rollback` lane auto-appends an entry to [`docs/incident-log.md`](incident-log.md). For manual rollbacks (App Store, or partial swaps outside the lane), append the entry by hand using the same heading shape.

## VOL-156 Phase 2 progress

Phase 1 (PR #162) shipped this document. Phase 2 lands the operational pieces; tracking ticket [VOL-178](https://linear.app/mabry-ventures/issue/VOL-178).

| Piece | Status | Landed in |
|---|---|---|
| `fastlane ios rollback` lane | Done Shipped | PR #167 (VOL-178 Phase 2A) |
| `docs/incident-log.md` template + retroactive entries | Done Shipped | PR #167 (VOL-178 Phase 2A) |
| Sentry alert rules (crash-free-sessions, new-fingerprint, release-health) | ⏳ Blocked on Sentry-admin access | tracked in VOL-178 |
| PagerDuty + Slack webhook wiring | ⏳ Blocked on PagerDuty/Slack admin setup | tracked in VOL-178 |
| Pre-release dry-run drill | ⏳ Pending — runs after the above land | tracked in VOL-178 |
