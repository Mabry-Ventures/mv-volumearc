import { type Metadata } from 'next'

import { Container } from '@/components/Container'

export const metadata: Metadata = {
  title: 'Terms of Service',
  description:
    'Terms of Service for VolumeArc. Subscription, usage, and refund policy.',
}

export default function TermsPage() {
  return (
    <article className="bg-white py-20 sm:py-32">
      <Container>
        <div className="mx-auto max-w-3xl">
          <header>
            <p className="text-sm font-semibold text-cyan-600">Legal</p>
            <h1 className="mt-2 text-4xl font-medium tracking-tight text-gray-900">
              Terms of Service
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
            <h2>1. Acceptance of Terms</h2>
            <p>
              By downloading, installing, or using the VolumeArc app
              (&ldquo;App&rdquo;), you (&ldquo;User&rdquo;) agree to be bound by
              these Terms of Service (&ldquo;Terms&rdquo;) and the{' '}
              <a href="/privacy">Privacy Policy</a>. If you do not agree, do not
              use the App.
            </p>

            <h2>2. The Service</h2>
            <p>
              VolumeArc is a strength training coaching application owned and
              operated by Mabry Ventures, LLC (&ldquo;Mabry Ventures,&rdquo;
              &ldquo;we,&rdquo; &ldquo;us,&rdquo; or &ldquo;our&rdquo;). The App
              provides workout tracking, AI-powered coaching, and integration
              with HealthKit and CloudKit.
            </p>

            <h2>3. Subscription &amp; Auto-Renewal (Apple Guideline 3.1.2)</h2>
            <p>
              VolumeArc offers an optional Pro subscription billed through your
              Apple ID at the price displayed at the point of purchase
              (currently $9.99/month or $79.99/year). Subscriptions
              automatically renew at the end of each billing period unless
              cancelled at least 24 hours before the end of the current period.
              Manage or cancel your subscription in iOS Settings → [your name] →
              Subscriptions.
            </p>

            <h2>4. Free Tier</h2>
            <p>
              Core functionality (workout tracking, CloudKit sync, the AI coach
              on the Flash Lite tier and on-device Foundation Models) is free.
              No subscription is required to use the App.
            </p>

            <h2>5. Acceptable Use</h2>
            <p>
              You agree not to: (a) reverse engineer or attempt to extract the
              source code of the App; (b) abuse the AI coach by automated or
              high-volume querying that interferes with service for other users;
              (c) use the App for medical diagnosis or treatment.
            </p>

            <h2>6. Health Disclaimer</h2>
            <p>
              VolumeArc is not a medical device. The coaching it provides is for
              fitness purposes only and is not a substitute for professional
              medical advice, diagnosis, or treatment. Consult a physician
              before beginning any exercise program.
            </p>

            <h2>7. Intellectual Property</h2>
            <p>
              The App, including its design, code, logos, and content, is owned
              by Mabry Ventures and is protected by copyright, trademark, and
              other intellectual property laws.
            </p>

            <h2>8. Refunds</h2>
            <p>
              Refund requests for App Store purchases must be submitted to Apple
              through{' '}
              <a href="https://reportaproblem.apple.com">
                reportaproblem.apple.com
              </a>
              . Mabry Ventures cannot directly issue refunds.
            </p>

            <h2>9. Termination</h2>
            <p>
              We may suspend or terminate your access to the App for violation
              of these Terms. You may stop using the App at any time by
              uninstalling it.
            </p>

            <h2>10. Limitation of Liability</h2>
            <p>
              To the maximum extent permitted by law, Mabry Ventures&rsquo;
              total liability arising from or related to your use of the App is
              limited to the amount you paid for the subscription in the prior
              twelve months.
            </p>

            <h2>11. Governing Law</h2>
            <p>
              These Terms are governed by the laws of the State of [TBD —
              pending counsel] without regard to conflict-of-law principles.
            </p>

            <h2>12. Changes to These Terms</h2>
            <p>
              We may update these Terms from time to time. The &ldquo;Effective
              date&rdquo; above will reflect the latest revision.
            </p>

            <h2>13. Contact</h2>
            <p>
              Questions about these Terms? Email{' '}
              <a href="mailto:legal@volumearc.com">legal@volumearc.com</a>.
            </p>
          </section>
        </div>
      </Container>
    </article>
  )
}
