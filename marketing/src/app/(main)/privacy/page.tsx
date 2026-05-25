import { type Metadata } from 'next'

import { Container } from '@/components/Container'

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description:
    'Privacy Policy for VolumeArc. How we handle HealthKit, CloudKit, the AI relay, and crash reporting.',
}

// VOL-195 — finalized privacy copy. Mabry Ventures LLC, Nashville TN.
// Tennessee governing law. Effective from launch date. Aligned with
// the VOL-209 disclosure normalization: raw HealthKit samples stay
// on-device; computed aggregates may travel to the AI relay when the
// user invokes the coach.
// VOL-124 — truthfulness pass after a Codex cross-check against the
// app's actual data flows. Corrected: per-platform HealthKit read set
// (no body weight); standard-mode prompt egress now discloses profile
// name + recent notes (strict mode strips them, on-device sends
// nothing); relay rate-limit identifier; full Sentry collection scope
// + crash-only session replay (text AND images masked); in-app
// feedback bundle; and expanded GDPR / CCPA-CPRA disclosures. The
// matching code changes (strict-mode question redaction on the relay
// path; maskAllImages) ship in the same PR.
const EFFECTIVE_DATE = 'May 25, 2026'

export default function PrivacyPage() {
  return (
    <article className="bg-white py-20 sm:py-32">
      <Container>
        <div className="mx-auto max-w-3xl">
          <header>
            <p className="text-sm font-semibold tracking-wide text-sunrise-700 uppercase">
              Legal
            </p>
            <h1 className="mt-2 text-4xl font-medium tracking-tight text-gray-900">
              Privacy Policy
            </h1>
            <p className="mt-4 text-sm text-gray-500">
              Effective date: {EFFECTIVE_DATE}
            </p>
            <p className="mt-1 text-sm text-gray-500">
              Operated by Mabry Ventures, LLC · Nashville, Tennessee, USA
            </p>
          </header>

          <section className="prose prose-gray mt-10 max-w-none">
            <h2>Our principle</h2>
            <p>
              VolumeArc is built privacy-first. Wherever we can keep your data
              on your own device under Apple&rsquo;s encryption rather than on
              our servers, we do. This policy describes exactly what data
              touches what system, and why.
            </p>

            <h2>1. Data we collect on your device</h2>

            <h3>HealthKit</h3>
            <p>
              With your explicit permission, the App reads a small, fixed set
              of HealthKit types. The exact set differs by device:
            </p>
            <ul>
              <li>
                <strong>On iPhone:</strong> workouts, heart-rate variability
                (HRV, SDNN), sleep analysis, Workout Effort (logged and
                estimated), Apple sleeping wrist temperature, and respiratory
                rate.
              </li>
              <li>
                <strong>On Apple Watch:</strong> workouts, heart rate, and
                active energy burned.
              </li>
            </ul>
            <p>
              The App writes one type back to HealthKit — completed workouts —
              so your VolumeArc sessions appear in Apple Health. It does not
              read body weight, body measurements, contacts, photos, or
              location.
            </p>
            <p>
              <strong>
                Raw HealthKit samples never leave your device. They remain in
                Apple Health under Apple&rsquo;s encryption boundary.
              </strong>{' '}
              The App reads them on-device and uses them to populate the
              recovery chip, the readiness signal, and the structured context
              that accompanies your coach prompt.
            </p>
            <p>
              <strong>
                Computed aggregates derived from your HealthKit data{' '}
                <em>may</em> leave your device.
              </strong>{' '}
              When you ask the cloud AI coach a question, the prompt the App
              sends to Google&rsquo;s Gemini API (via our Cloudflare Worker
              relay) embeds numeric aggregates such as a 7-day HRV mean versus
              your 28-day baseline (e.g. &ldquo;54 ms vs 58 ms, −7%&rdquo;), a
              7-day sleep total versus target (e.g. &ldquo;47.2h over 7 days vs
              56h target&rdquo;), a 7-day strength-training load in kilojoules
              and minutes (e.g. &ldquo;4,200 kJ across 180 min&rdquo;), Workout
              Effort trends, sleeping wrist-temperature trends, and
              respiratory-rate trends. These aggregates are derived from your
              HealthKit data; the raw samples themselves are not transmitted.
              These aggregates are numeric, not raw samples, and are included
              whenever you use the cloud coach. On devices that support
              Apple&rsquo;s on-device Foundation Models, the coach may answer
              locally without contacting the relay; if the on-device model is
              unavailable, the request falls back to the cloud path. If you
              would rather these aggregates were never computed or sent,
              decline or revoke HealthKit access (iOS Settings → Privacy &amp;
              Security → Health → VolumeArc).
            </p>

            <h3>Camera form check</h3>
            <p>
              If you start a form check during an active workout, the App asks
              for camera permission and uses the rear camera to run Apple&rsquo;s
              on-device Vision pose detection. Camera frames are processed in
              memory on your device only. We do not save, upload, or transmit
              form-check video, photos, or camera frames to VolumeArc,
              Cloudflare, Google Gemini, Sentry, iCloud, or Apple Health.
              Starting or stopping capture from Apple Watch sends only a
              WatchConnectivity control message; it does not move camera frames
              off the iPhone.
            </p>
            <p>
              The App keeps only derived form-check metrics such as exercise,
              rep count, tempo, lateral drift, verdict, and coaching cue. If
              you later ask the cloud AI coach a question, those derived
              metrics may be included in the structured coach context so the
              coach can reference the latest form check. The camera frames
              themselves are never included.
            </p>

            <h3>CloudKit (your private container)</h3>
            <p>
              Your training history (workouts, sets, RPE, training plans,
              workout notes, coach memory entries) is stored in your private
              CloudKit container under your own iCloud account. CloudKit
              private databases are encrypted in transit and at rest by
              Apple; Apple holds the keys; Mabry Ventures does not have
              access. We cannot read, list, search, or recover your CloudKit
              data.
            </p>

            <h3>Subscriptions</h3>
            <p>
              Subscription state is managed by Apple through StoreKit 2. The
              App receives an entitlement signal (premium yes/no) from Apple
              on each launch and on subscription state changes. Your payment
              method, billing address, name, and transaction history are
              held by Apple, not by Mabry Ventures.
            </p>

            <h2>2. Data that travels off-device</h2>

            <h3>To the VolumeArc AI relay (Cloudflare Worker) and Google Gemini</h3>
            <p>
              When you query the cloud AI coach, the App sends your prompt
              through a Cloudflare Worker we operate at{' '}
              <code>relay.volumearc.app</code>. The Worker forwards the
              prompt to Google&rsquo;s Gemini API and streams the response
              back. The Worker is operated by Mabry Ventures, runs in
              Cloudflare&rsquo;s edge network, and is configured to log only
              request shape (path, status code, latency, timing) for
              operational monitoring. It does <strong>not</strong> log
              prompt content, response bodies, or your HealthKit aggregates.
            </p>
            <p>
              <strong>Rate-limiting identifier.</strong> To prevent abuse, the
              Worker authenticates each request with Apple App Attest and keeps
              a short-lived count of recent requests for the attested app key in
              Cloudflare&rsquo;s edge key-value store. That key is not your name,
              email, or Apple ID, is not forwarded to Google, and the counter
              entries expire automatically. It lets us enforce rate limits
              without an account system.
            </p>
            <p>
              <strong>
                What the outgoing prompt contains depends on your privacy mode.
              </strong>{' '}
              In the default (<strong>Standard</strong>) mode, the prompt
              includes: the free-text question you typed or spoke; the coach
              intent category; a system persona; the recovery aggregates
              described above; latest derived form-check metrics when present;
              and a structured context block that{' '}
              <strong>
                includes your profile name, recent session summaries, and your
                most recent coaching notes
              </strong>{' '}
              so the coach can address you and reason about your training. In{' '}
              <strong>Strict</strong> mode, the App replaces your name with
              &ldquo;the athlete,&rdquo; omits session summaries and coaching
              notes, and applies best-effort redaction of email, phone, name,
              and street-address patterns to the free-text question before it
              leaves the device. (Strict-mode redaction is defense-in-depth,
              not a guarantee of zero PII egress — novel PII-shaped text you
              type may not be caught.) On devices that
              support Apple&rsquo;s <strong>on-device</strong> Foundation
              Models (where enabled), the coach may answer locally, in which
              case the prompt is processed on-device; if the on-device model is
              unavailable the request falls back to the cloud relay path above.
            </p>
            <p>
              Aside from the free-text question itself, the outgoing
              prompt&rsquo;s structured fields never contain your email address,
              phone number, postal address, IP address (we do not pass it
              through), Apple ID, or raw HealthKit samples. The free-text
              question is whatever you type or dictate: in{' '}
              <strong>Standard</strong> mode it is sent as-is, so avoid typing
              sensitive personal details into the coach box; in{' '}
              <strong>Strict</strong> mode it is best-effort redacted as
              described above.
            </p>
            <p>
              Google&rsquo;s use of prompt data and any data-retention
              behavior on Google&rsquo;s side is governed by Google&rsquo;s
              API terms.
            </p>

            <h3>To Sentry (crash reporting &amp; diagnostics)</h3>
            <p>
              We use Sentry (operated by Functional Software, Inc.) to find and
              fix crashes, performance problems, and bugs. The Sentry SDK is
              configured to collect:
            </p>
            <ul>
              <li>Crash reports and error events, with breadcrumbs;</li>
              <li>
                Automatic session tracking (app launches, foreground/background
                transitions) so we can compute a crash-free-sessions rate;
              </li>
              <li>Failed network requests (status and timing, not bodies);</li>
              <li>
                Performance traces on a 20% sample, with profiling on a small
                subset of those traces;
              </li>
              <li>
                MetricKit diagnostics and app-hang (ANR) detection for hangs
                longer than 5 seconds.
              </li>
            </ul>
            <p>
              <strong>Session Replay is enabled for crashed sessions only</strong>{' '}
              (0% of normal sessions; 100% of sessions that crash), so an
              engineer can see the final seconds of UI leading to a crash.{' '}
              <strong>All text and all images are masked</strong> in the replay,
              so workout notes, coach messages, HealthKit numbers, and profile
              fields never appear in replay frames — only anonymized layout
              boxes.
            </p>
            <p>
              Before any event leaves your device, it passes through a privacy
              scrubber we wrote. The scrubber strips email and phone patterns,
              device identifiers, session tokens, and HealthKit-derived fields;
              drops breadcrumbs in the user-input and coach-memory categories;
              and clears Sentry&rsquo;s built-in user fields (email, username,
              IP address). We do not deliberately send your name to Sentry; if
              a stray name string slips into an event field the scrubber does
              not cover, it may be transmitted, which is why we keep the
              scrubber patterns under test and expand them when we find gaps.
            </p>
            <h3>In-app feedback (sent to Sentry)</h3>
            <p>
              When you use <strong>Send Feedback</strong> (Profile → Help), the
              App sends Sentry the description you write plus diagnostic context:
              OS version, device model, recent in-app telemetry breadcrumbs, and
              a non-reversible app-state hash. This is sent only when you choose
              to submit feedback. Because you author the description, please
              avoid typing personal details you don&rsquo;t want shared. To
              request deletion of a feedback submission, email{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>.
            </p>

            <h3>Support form email (sent through Resend)</h3>
            <p>
              If you use the support form on <code>volumearc.app/support</code>,
              we send the name, email address, topic, and message you provide
              through Resend (operated by Resend, Inc.) to deliver the request
              to our support inbox. This is transactional support email only;
              we do not add support-form submissions to a marketing list. The
              route uses transient in-memory rate limiting from request metadata
              to reduce abuse; those counters are not sent to Resend and expire
              automatically.
            </p>

            <h3>Microphone &amp; speech (voice input)</h3>
            <p>
              If you ask the coach a question by voice, the App requests
              microphone and speech-recognition permission and uses
              Apple&rsquo;s Speech framework to transcribe your speech to text.
              Transcription is performed by Apple and is governed by
              Apple&rsquo;s privacy practices; VolumeArc receives only the
              resulting text, which then follows the same coach-prompt path
              (and privacy-mode rules) described above. We do not store your
              audio. Microphone access is used only while you are actively
              dictating a question.
            </p>

            <h3>To Apple (HealthKit, CloudKit, StoreKit, APNs)</h3>
            <p>
              Apple-managed integrations carry their own data flows under
              Apple&rsquo;s privacy practices. We use them as the OS
              intends; we do not re-publish the data they handle.
            </p>

            <h2>3. Data we do not collect</h2>
            <ul>
              <li>We do not use third-party advertising SDKs.</li>
              <li>We do not use third-party analytics SDKs in the App.</li>
              <li>
                We do not use a remote-configuration or experimentation
                service. Feature flags are local and shipped with the build.
              </li>
              <li>We do not sell your data to anyone, ever.</li>
              <li>
                We do not use your HealthKit data for any purpose other than
                running the App for you.
              </li>
              <li>We do not read your contacts, photos, or location.</li>
              <li>
                We do not upload or store form-check video, photos, or camera
                frames.
              </li>
            </ul>
            <p>
              The marketing website at <code>volumearc.app</code> uses
              Plausible Analytics, which is a privacy-respecting analytics
              service that does not use cookies and does not collect
              personal data. Plausible only sees aggregate page-view counts
              and referrers for the website itself, not data from inside
              the App.
            </p>

            <h2>4. Your rights</h2>
            <p>
              <strong>Revoke HealthKit access.</strong> iOS Settings → Privacy
              &amp; Security → Health → VolumeArc.
            </p>
            <p>
              <strong>Delete your CloudKit data.</strong> Delete the App, then
              delete the VolumeArc data in iOS Settings → [your name] →
              iCloud → Manage Storage → VolumeArc.
            </p>
            <p>
              <strong>Cancel your subscription.</strong> iOS Settings → [your
              name] → Subscriptions → VolumeArc.
            </p>
            <p>
              <strong>Request server-side deletion.</strong> If you believe
              we hold any data about you on our own infrastructure (the AI
              relay, Sentry, etc.), email{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>{' '}
              and we will confirm what we have and remove it within 30 days.
              Note: the relay does not log prompt content, so for typical
              users there is nothing on our side to delete; this right is
              still available.
            </p>

            <h2>5. Processors, transfers &amp; retention</h2>
            <p>
              Mabry Ventures, LLC is the data controller for the limited
              personal data we process. We use the following processors, all
              based in the United States, under their respective data-processing
              terms:
            </p>
            <ul>
              <li>
                <strong>Apple</strong> — HealthKit, CloudKit, StoreKit, push
                notifications, and on-device/Apple speech recognition.
              </li>
              <li>
                <strong>Cloudflare</strong> — hosts the AI relay Worker and the
                edge rate-limit store.
              </li>
              <li>
                <strong>Google</strong> — the Gemini API that generates coach
                responses.
              </li>
              <li>
                <strong>Functional Software, Inc. (Sentry)</strong> — crash and
                diagnostics reporting.
              </li>
              <li>
                <strong>Resend, Inc.</strong> — transactional support-form email
                delivery from the marketing website.
              </li>
            </ul>
            <p>
              <strong>International transfers.</strong> If you are outside the
              United States, using the cloud coach or crash reporting transfers
              data to US-based processors. Those transfers rely on the
              processors&rsquo; standard contractual clauses and data-processing
              agreements as appropriate safeguards.
            </p>
            <p>
              <strong>Retention.</strong> Your CloudKit training data stays in
              your iCloud account until you delete it (we cannot access it). The
              relay does not retain prompt content; the rate-limit identifier
              counters expire automatically within minutes. Sentry events are
              retained for Sentry&rsquo;s default period (about 90 days) and
              then deleted. Support-form emails are retained in the support
              inbox only as long as needed to answer and audit the request.
            </p>

            <h2>6. GDPR (EEA &amp; UK)</h2>
            <p>
              If you are in the European Economic Area or the United Kingdom,
              Mabry Ventures is the controller for your personal data. Our
              lawful bases (UK/EU GDPR Article 6, and Article 9 for health
              data) are:
            </p>
            <ul>
              <li>
                <strong>Performance of a contract</strong> — operating the App
                and coach for you.
              </li>
              <li>
                <strong>Explicit consent</strong> — reading HealthKit data and
                sending HealthKit-derived aggregates to the cloud coach (you
                grant HealthKit access and choose the cloud tier; health data is
                special-category data processed only on your explicit consent,
                which you can withdraw at any time by revoking HealthKit access
                or switching to the on-device tier).
              </li>
              <li>
                <strong>Legitimate interests</strong> — crash/diagnostics
                reporting and abuse prevention (rate limiting), balanced against
                your rights.
              </li>
            </ul>
            <p>
              You have the right to access, rectify, erase, restrict, port, and
              object to processing of your personal data, to withdraw consent,
              and to lodge a complaint with your supervisory authority. Email{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>{' '}
              and we will respond within 30 days.
            </p>

            <h2>7. California (CCPA/CPRA)</h2>
            <p>
              If you are a California resident, the following describes our
              practices in the preceding 12 months. <strong>We do not sell or
              share your personal information</strong> (as &ldquo;sell&rdquo;
              and &ldquo;share&rdquo; are defined under the CPRA), and we do not
              use it for cross-context behavioral advertising.
            </p>
            <ul>
              <li>
                <strong>Categories collected:</strong> identifiers (a
                pseudonymous per-install ID for rate limiting); health-derived
                aggregates and other content you provide to the coach (sensitive
                personal information); and usage/diagnostic data (crash and
                performance telemetry).
              </li>
              <li>
                <strong>Sources:</strong> you, and your device/app interactions.
              </li>
              <li>
                <strong>Purposes:</strong> to provide the coaching service, fix
                bugs and crashes, and prevent abuse.
              </li>
              <li>
                <strong>Disclosures:</strong> only to the service providers
                listed above, for those purposes.
              </li>
            </ul>
            <p>
              You have the right to know, delete, and correct your personal
              information; to limit the use of sensitive personal information;
              and to not be discriminated against for exercising these rights.
              To exercise any of these, email{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>;
              we will respond within 45 days.
            </p>

            <h2>8. Children</h2>
            <p>
              VolumeArc is not directed to children under 13. We do not
              knowingly collect personal information from children under 13.
              If you become aware that a child has provided us with personal
              information, contact{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>{' '}
              and we will delete it.
            </p>

            <h2>9. Security incident response</h2>
            <p>
              If we become aware of a security incident affecting your
              personal data, we will notify affected users where legally
              required and without undue delay, using the channels available
              to us — an in-app notice on next launch, a notice on{' '}
              <code>volumearc.app</code>, the App Store release notes, and
              email where we have one — with the nature of the incident, the
              data involved, and the steps we are taking. Because we operate no
              account system and do not collect your email, an in-app/website
              notice is typically our primary channel.
            </p>

            <h2>10. Vulnerability disclosure</h2>
            <p>
              Security researchers who find a vulnerability in the App, the
              relay, or this website may report it to{' '}
              <a href="mailto:security@volumearc.com">
                security@volumearc.com
              </a>
              . We acknowledge within 2 business days and commit to working
              in good faith on coordinated disclosure. We do not pursue
              legal action against researchers operating within the spirit
              of this policy.
            </p>

            <h2>11. Changes to this policy</h2>
            <p>
              We will update the &ldquo;Effective date&rdquo; above when
              this policy changes. Material changes (new categories of data
              collected, new third parties, new egress paths) will be
              surfaced in-app on next launch.
            </p>

            <h2>12. Contact</h2>
            <p>
              Questions about this policy? Email{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>{' '}
              or write to:
            </p>
            <p>
              Mabry Ventures, LLC
              <br />
              Attn: Privacy
              <br />
              Nashville, Tennessee, USA
            </p>
          </section>
        </div>
      </Container>
    </article>
  )
}
