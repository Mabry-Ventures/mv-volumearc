import { type Metadata } from 'next'

import { Container } from '@/components/Container'

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description:
    'Privacy Policy for VolumeArc. How we handle HealthKit, CloudKit, AI relay, and Sentry data.',
}

export default function PrivacyPage() {
  return (
    <article className="bg-white py-20 sm:py-32">
      <Container>
        <div className="mx-auto max-w-3xl">
          <header>
            <p className="text-sm font-semibold tracking-wide text-sunrise-700 uppercase">Legal</p>
            <h1 className="mt-2 text-4xl font-medium tracking-tight text-gray-900">
              Privacy Policy
            </h1>
            <p className="mt-4 text-sm text-gray-500">
              Effective date: <em>TBD — pending legal review (VOL-124)</em>
            </p>
          </header>

          <div className="mt-8 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
            <strong>Draft.</strong> This page is a placeholder structure. Final
            content is being prepared with legal counsel and will replace this
            page before App Store submission. See{' '}
            <a
              className="underline"
              href="https://linear.app/mabry-ventures/issue/VOL-124"
            >
              VOL-124
            </a>
            .
          </div>

          <section className="prose prose-gray mt-10 max-w-none">
            <h2>Our principle</h2>
            <p>
              VolumeArc is built privacy-first. Wherever we can put your data on
              your own device under Apple&rsquo;s encryption rather than on our
              servers, we do.
            </p>

            <h2>Data we collect</h2>
            <h3>HealthKit</h3>
            <p>
              With your explicit permission, the App reads from HealthKit:
              workout history, heart-rate variability (HRV) trends, sleep
              duration, training load, and basic recovery signals. This data is
              read on-device and used by the Readiness model and the AI coach
              prompt.{' '}
              <strong>
                Raw HealthKit data never leaves your device unencrypted.
              </strong>{' '}
              Computed summaries (e.g., &ldquo;HRV down 8% vs baseline&rdquo;)
              may be included in the redacted coach prompt envelope when you ask
              the coach a question.
            </p>

            <h3>CloudKit (your private container)</h3>
            <p>
              Your training history (workouts, sets, RPE, training plans, coach
              memory) is stored in your private CloudKit container under your
              own iCloud account. Mabry Ventures does not have access to this
              data and cannot read it. Apple holds the encryption keys.
            </p>

            <h3>AI relay (Cloudflare Worker → Gemini)</h3>
            <p>
              When you query the AI coach on the cloud tier, the App sends a
              redacted prompt envelope through a Cloudflare Worker we operate to
              Google&rsquo;s Gemini API. The envelope includes: your question,
              the coach intent, the structured context block (readiness score,
              recent session count, current program), and a system persona. It
              does <strong>not</strong> include: your name, email, address,
              phone number, exact body weight, or any HealthKit raw values.
            </p>

            <h3>Sentry (crash reporting)</h3>
            <p>
              We use Sentry to collect anonymous crash reports and error
              telemetry. All payloads pass through{' '}
              <code>VolumeArcSentryPIIScrubber</code> before leaving the device,
              which strips emails, phone numbers, and other PII. We do not send
              user identifiers, names, or HealthKit data to Sentry.
            </p>

            <h3>Subscriptions</h3>
            <p>
              Subscription state is managed by Apple via StoreKit 2. We receive
              an entitlement signal (premium yes/no), not your payment details.
            </p>

            <h2>Data we do not collect</h2>
            <ul>
              <li>We do not use third-party advertising SDKs.</li>
              <li>We do not sell your data to anyone, ever.</li>
              <li>
                We do not use your HealthKit data for any purpose other than
                running the App for you.
              </li>
              <li>We do not read your contacts, photos, or location.</li>
            </ul>

            <h2>Your rights</h2>
            <p>
              You can revoke HealthKit access at any time in iOS Settings →
              Privacy &amp; Security → Health → VolumeArc. You can delete your
              CloudKit data by deleting the App, then deleting the
              VolumeArc-related data in iOS Settings → [your name] → iCloud →
              Manage Storage. To request deletion of any server-side data we
              hold, email{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>.
            </p>

            <h2>GDPR &amp; CCPA</h2>
            <p>
              If you reside in the European Economic Area, the United Kingdom,
              or California, you have specific rights under GDPR and CCPA
              including the right to access, port, and delete your data. Contact{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>{' '}
              to exercise these rights.
            </p>

            <h2>Children</h2>
            <p>
              VolumeArc is not directed to children under 13 and we do not
              knowingly collect data from children under 13.
            </p>

            <h2>Changes to this policy</h2>
            <p>
              We will update the &ldquo;Effective date&rdquo; above when this
              policy changes. Material changes will be communicated in-app.
            </p>

            <h2>Contact</h2>
            <p>
              Questions about this policy?{' '}
              <a href="mailto:privacy@volumearc.com">privacy@volumearc.com</a>.
            </p>
          </section>
        </div>
      </Container>
    </article>
  )
}
