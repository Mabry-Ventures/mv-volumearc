import { type Metadata } from 'next'

import { Container } from '@/components/Container'
import { SupportForm } from '@/components/SupportForm'

export const metadata: Metadata = {
  title: 'Support',
  description:
    'Get help with VolumeArc. Contact, FAQs, and press inquiries.',
}

const supportSections = [
  {
    heading: 'Contact',
    body: (
      <>
        <p>
          For app questions or bug reports, the fastest path is in-app: open{' '}
          <strong>Profile → Help → Send feedback</strong>. The form attaches a
          redacted diagnostic bundle so we can reproduce the issue without
          seeing your personal data.
        </p>
        <SupportForm />
      </>
    ),
  },
  {
    heading: 'Email',
    body: (
      <ul className="space-y-2">
        <li>
          General support:{' '}
          <a className="underline" href="mailto:support@mabryventures.com">
            support@mabryventures.com
          </a>
        </li>
        <li>
          Privacy /{' '}
          <a className="underline" href="/privacy">
            data requests
          </a>
          :{' '}
          <a className="underline" href="mailto:privacy@volumearc.com">
            privacy@volumearc.com
          </a>
        </li>
        <li>
          Legal:{' '}
          <a className="underline" href="mailto:legal@volumearc.com">
            legal@volumearc.com
          </a>
        </li>
      </ul>
    ),
  },
  {
    heading: 'Common issues',
    body: (
      <ul className="space-y-3">
        <li>
          <strong>HealthKit prompt didn&rsquo;t appear:</strong> iOS Settings →
          Privacy &amp; Security → Health → VolumeArc → enable the categories
          you want VolumeArc to read.
        </li>
        <li>
          <strong>Watch app stalls or won&rsquo;t pair:</strong> open the iOS
          Watch app, find VolumeArc, ensure it&rsquo;s installed; toggle Show in
          Control Center; restart both devices if needed.
        </li>
        <li>
          <strong>Subscription not recognised:</strong> in the app, Profile →
          Restore subscription. If the entitlement still doesn&rsquo;t apply,
          email support@ with the Apple receipt.
        </li>
        <li>
          <strong>Coach feels off:</strong> we publish per-fixture eval results
          at <a href="/quality">volumearc.app/quality</a>. If you see drift, the
          in-app feedback form lets you flag the bad response so we can add it
          to the regression suite.
        </li>
      </ul>
    ),
  },
  {
    heading: 'Press',
    body: (
      <p id="press">
        Press inquiries:{' '}
        <a className="underline" href="mailto:press@mabryventures.com">
          press@mabryventures.com
        </a>
        . We&rsquo;ll send our press kit, founder Q&amp;A, and embargo-friendly
        artwork. For coach-quality questions specifically, see{' '}
        <a href="/quality">/quality</a> for our public eval-trend results.
      </p>
    ),
  },
]

export default function SupportPage() {
  return (
    <article className="bg-white py-20 sm:py-32">
      <Container>
        <div className="mx-auto max-w-3xl">
          <header>
            <p className="text-sm font-semibold tracking-wide text-sunrise-700 uppercase">Support</p>
            <h1 className="mt-2 text-4xl font-medium tracking-tight text-gray-900">
              Get help with VolumeArc
            </h1>
            <p className="mt-4 text-lg text-gray-600">
              We&rsquo;re a small team. We read every message. Most people get a
              response within one business day.
            </p>
          </header>

          <div className="mt-12 space-y-12">
            {supportSections.map((section) => (
              <section key={section.heading}>
                <h2 className="text-xl font-semibold text-gray-900">
                  {section.heading}
                </h2>
                <div className="mt-3 text-base text-gray-700">
                  {section.body}
                </div>
              </section>
            ))}
          </div>
        </div>
      </Container>
    </article>
  )
}
