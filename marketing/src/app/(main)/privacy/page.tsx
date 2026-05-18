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
const EFFECTIVE_DATE = 'May 18, 2026'

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
              With your explicit permission, the App reads from Apple
              HealthKit on iOS and watchOS:
            </p>
            <ul>
              <li>Workout history (date, duration, type, energy)</li>
              <li>Heart rate and heart-rate variability (HRV) trends</li>
              <li>Sleep duration and sleep stages</li>
              <li>Active energy expenditure</li>
              <li>Body weight, only if you choose to enter it</li>
            </ul>
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
              relay) embeds numeric aggregates such as &ldquo;7-day HRV mean:
              52 ms,&rdquo; &ldquo;last-night sleep duration: 6h 40m,&rdquo;
              and &ldquo;7-day strength load: 18,200 kg-reps.&rdquo; These
              aggregates are derived from your HealthKit data; the raw
              samples themselves are not transmitted. Aggregates are required
              for the coach to give a meaningful prescription. If you do not
              want HealthKit-derived aggregates in your coach prompt, switch
              the coach to the on-device Foundation Models tier in the App
              settings — that path never leaves your device.
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
              prompt content, response bodies, your name, your account
              identifiers, or any HealthKit aggregates.
            </p>
            <p>
              <strong>What the outgoing prompt contains:</strong> the
              free-text question you typed or spoke; the coach intent
              category; the structured context block (readiness score,
              recent session count, current program, recovery aggregates);
              and a system persona. <strong>What it does not contain:</strong>{' '}
              your name, email, phone number, postal address, IP address (we
              do not pass it through), or raw HealthKit samples. If you
              enable strict privacy mode in App settings, the App also
              redacts email/phone/name patterns from the free-text question
              before transmission.
            </p>
            <p>
              Google&rsquo;s use of prompt data and any data-retention
              behavior on Google&rsquo;s side is governed by Google&rsquo;s
              API terms.
            </p>

            <h3>To Sentry (crash reporting)</h3>
            <p>
              We use Sentry to collect crash reports and error breadcrumbs
              so we can fix bugs. All payloads pass through a privacy
              scrubber we wrote (
              <code>VolumeArcSentryPIIScrubber</code>) before leaving the
              device. The scrubber strips email patterns, phone patterns,
              device identifiers, session tokens, and HealthKit-derived
              fields. We do not send user identifiers, names, exercise
              notes, or coach memory to Sentry. Session Replay is off by
              default. If we ever enable it, this policy will be updated
              with the masking configuration.
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
              <a href="mailto:privacy@volumearc.app">privacy@volumearc.app</a>{' '}
              and we will confirm what we have and remove it within 30 days.
              Note: the relay does not log prompt content, so for typical
              users there is nothing on our side to delete; this right is
              still available.
            </p>

            <h2>5. GDPR &amp; CCPA</h2>
            <p>
              If you reside in the European Economic Area, the United
              Kingdom, or California (or another jurisdiction with similar
              consumer-privacy laws), you have specific rights including
              access, portability, deletion, and the right to object to
              processing. Contact{' '}
              <a href="mailto:privacy@volumearc.app">privacy@volumearc.app</a>{' '}
              to exercise these rights; we will respond within the statutory
              window (typically 30 days under GDPR, 45 days under CCPA).
              Mabry Ventures is the data controller for personal data we
              hold about you.
            </p>

            <h2>6. Children</h2>
            <p>
              VolumeArc is not directed to children under 13. We do not
              knowingly collect personal information from children under 13.
              If you become aware that a child has provided us with personal
              information, contact{' '}
              <a href="mailto:privacy@volumearc.app">privacy@volumearc.app</a>{' '}
              and we will delete it.
            </p>

            <h2>7. Security incident response</h2>
            <p>
              If we become aware of a security incident affecting your
              personal data, we will notify affected users within 72 hours
              of confirmation, by email and via an in-app notice on next
              launch, with the nature of the incident, the data involved,
              and the steps we are taking.
            </p>

            <h2>8. Vulnerability disclosure</h2>
            <p>
              Security researchers who find a vulnerability in the App, the
              relay, or this website may report it to{' '}
              <a href="mailto:security@volumearc.app">
                security@volumearc.app
              </a>
              . We acknowledge within 2 business days and commit to working
              in good faith on coordinated disclosure. We do not pursue
              legal action against researchers operating within the spirit
              of this policy.
            </p>

            <h2>9. Changes to this policy</h2>
            <p>
              We will update the &ldquo;Effective date&rdquo; above when
              this policy changes. Material changes (new categories of data
              collected, new third parties, new egress paths) will be
              surfaced in-app on next launch.
            </p>

            <h2>10. Contact</h2>
            <p>
              Questions about this policy? Email{' '}
              <a href="mailto:privacy@volumearc.app">privacy@volumearc.app</a>{' '}
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
