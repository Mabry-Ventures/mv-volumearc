import { type Metadata } from 'next'

import { Container } from '@/components/Container'

export const metadata: Metadata = {
  title: 'Terms of Service',
  description:
    'Terms of Service for VolumeArc. Subscription, usage, and refund policy.',
}

// VOL-195 — finalized legal copy. Mabry Ventures LLC, Nashville TN.
// Tennessee governing law. Effective from launch date. If a future
// revision is needed, bump LAST_UPDATED, add a versioned anchor, and
// keep prior versions reachable per Apple Guideline 3.1.2.
const EFFECTIVE_DATE = 'May 18, 2026'

export default function TermsPage() {
  return (
    <article className="bg-white py-20 sm:py-32">
      <Container>
        <div className="mx-auto max-w-3xl">
          <header>
            <p className="text-sm font-semibold tracking-wide text-sunrise-700 uppercase">
              Legal
            </p>
            <h1 className="mt-2 text-4xl font-medium tracking-tight text-gray-900">
              Terms of Service
            </h1>
            <p className="mt-4 text-sm text-gray-500">
              Effective date: {EFFECTIVE_DATE}
            </p>
            <p className="mt-1 text-sm text-gray-500">
              Operated by Mabry Ventures, LLC · Nashville, Tennessee, USA
            </p>
          </header>

          <section className="prose prose-gray mt-10 max-w-none">
            <h2>1. Acceptance of Terms</h2>
            <p>
              By downloading, installing, or using the VolumeArc app
              (&ldquo;App&rdquo;), you (&ldquo;User&rdquo; or &ldquo;you&rdquo;)
              agree to be bound by these Terms of Service (&ldquo;Terms&rdquo;)
              and the <a href="/privacy">Privacy Policy</a>. If you do not
              agree, do not install or use the App.
            </p>

            <h2>2. The Service</h2>
            <p>
              VolumeArc is a strength-training coaching application owned and
              operated by Mabry Ventures, LLC (&ldquo;Mabry Ventures,&rdquo;
              &ldquo;we,&rdquo; &ldquo;us,&rdquo; or &ldquo;our&rdquo;), a
              limited-liability company organized under the laws of the State
              of Tennessee with its principal place of business in Nashville,
              Tennessee. The App provides workout tracking, AI-powered
              coaching, and integration with Apple HealthKit, CloudKit, and
              StoreKit. The App is distributed exclusively through the Apple
              App Store and runs on iOS, iPadOS, and watchOS devices.
            </p>

            <h2>3. Subscription &amp; Auto-Renewal (Apple Guideline 3.1.2)</h2>
            <p>
              The App is free to download and use for core features (see
              Section 4). It also offers an optional &ldquo;Pro&rdquo;
              subscription billed through your Apple ID at the price displayed
              at the point of purchase (currently $9.99 per month or $79.99
              per year, subject to change with notice on the App Store
              listing). The subscription unlocks the Gemini Pro coach tier and
              live voice coaching, and no other features.
            </p>
            <p>
              <strong>Auto-renewal.</strong> Subscriptions automatically renew
              for the same period at the then-current price unless cancelled
              at least 24 hours before the end of the current billing period.
              You can manage or cancel your subscription at any time in iOS
              Settings → [your name] → Subscriptions → VolumeArc. Cancellation
              takes effect at the end of the current billing period; you keep
              Pro access until the period ends and then revert to the free
              tier.
            </p>
            <p>
              <strong>Refunds.</strong> Refund requests for App Store
              purchases are handled by Apple, not Mabry Ventures. Submit
              requests at{' '}
              <a href="https://reportaproblem.apple.com">
                reportaproblem.apple.com
              </a>
              . If Apple grants a refund, your Pro entitlement is revoked on
              the next subscription state refresh.
            </p>

            <h2>4. Free Tier</h2>
            <p>
              The following features are free and require no subscription:
              full workout tracking, the Apple Watch app and complications,
              Live Activities and widgets, cloud sync via your private
              CloudKit container, the AI coach on the Gemini Flash Lite tier,
              the on-device Foundation Models coach fallback, and readiness
              context derived from HealthKit (HRV, sleep, training load).
            </p>

            <h2>5. Acceptable Use</h2>
            <p>You agree not to:</p>
            <ul>
              <li>
                Reverse engineer, decompile, disassemble, or otherwise attempt
                to derive source code from the App, except to the extent
                expressly permitted by applicable law;
              </li>
              <li>
                Abuse the AI coach through automated, scripted, or
                high-volume querying that interferes with service for other
                users or that attempts to circumvent rate limits;
              </li>
              <li>
                Use the App for medical diagnosis, medical treatment, or any
                purpose where the App&rsquo;s output could reasonably be
                substituted for the advice of a licensed medical professional;
              </li>
              <li>
                Use the App to harass, harm, or attempt to identify another
                person; or upload content you do not have the right to share.
              </li>
            </ul>

            <h2>6. Health Disclaimer (Important)</h2>
            <p>
              <strong>
                VolumeArc is not a medical device and does not provide medical
                advice.
              </strong>{' '}
              The coaching, readiness signals, and prescriptions the App
              provides are for general fitness purposes only and are not a
              substitute for professional medical advice, diagnosis, or
              treatment. Consult a qualified physician before beginning any
              new exercise program, especially if you have a pre-existing
              medical condition or are taking medication. You assume all risk
              of injury arising from your use of the training programs and
              prescriptions in the App.
            </p>

            <h2>7. AI Coaching &amp; Third-Party Models</h2>
            <p>
              The AI coach uses Google&rsquo;s Gemini family of models. When
              you query the cloud coach, the App sends a prompt to a
              Cloudflare Worker we operate at <code>relay.volumearc.app</code>,
              which forwards the prompt to Google&rsquo;s Gemini API. The
              relay forwards prompts as-is and does not retain prompt content
              or response bodies; it logs only request shape (path, status,
              latency) for operational monitoring. Google&rsquo;s use of
              prompt data is governed by Google&rsquo;s API terms. The App
              also runs on-device coaching via Apple&rsquo;s Foundation
              Models when supported; that path never transmits data
              off-device.
            </p>
            <p>
              AI output is generated probabilistically and may be inaccurate,
              incomplete, or unsuitable for your situation. Use your own
              judgment when applying any prescription, and stop if you
              experience pain.
            </p>

            <h2>8. Intellectual Property</h2>
            <p>
              The App, including its design, source code, logos, brand marks,
              eval fixtures, and content, is owned by Mabry Ventures and is
              protected by United States and international copyright,
              trademark, and other intellectual-property laws. We grant you a
              limited, non-exclusive, non-transferable, revocable license to
              use the App on Apple devices you own or control, solely for
              your personal, non-commercial use, subject to these Terms.
            </p>

            <h2>9. Your Content</h2>
            <p>
              You retain all rights in workout notes, coach memory entries,
              and other content you create in the App. Your content is stored
              in your private CloudKit container under your iCloud account
              and is accessible to you, but not to Mabry Ventures (CloudKit
              private databases are encrypted end-to-end by Apple). You grant
              Mabry Ventures no rights to your content beyond what is
              technically necessary to operate the App for you.
            </p>

            <h2>10. Termination</h2>
            <p>
              You may stop using the App at any time by uninstalling it. We
              may suspend or terminate your access to the App if you
              materially breach these Terms, including the Acceptable Use
              provisions in Section 5. On termination, Sections 6, 8, 10, 11,
              12, and 13 survive.
            </p>

            <h2>11. Disclaimer of Warranties</h2>
            <p>
              TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE APP IS
              PROVIDED &ldquo;AS IS&rdquo; AND &ldquo;AS AVAILABLE,&rdquo;
              WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED,
              STATUTORY, OR OTHERWISE, INCLUDING WITHOUT LIMITATION IMPLIED
              WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE,
              AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE APP WILL BE
              UNINTERRUPTED, ERROR-FREE, OR FREE OF HARMFUL COMPONENTS.
            </p>

            <h2>12. Limitation of Liability</h2>
            <p>
              TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT
              SHALL MABRY VENTURES, ITS OFFICERS, MEMBERS, EMPLOYEES, OR
              AGENTS BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL,
              CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS,
              REVENUE, DATA, OR USE, ARISING OUT OF OR RELATED TO YOUR USE OF
              THE APP, EVEN IF WE HAVE BEEN ADVISED OF THE POSSIBILITY OF
              SUCH DAMAGES. OUR TOTAL CUMULATIVE LIABILITY ARISING FROM OR
              RELATED TO THESE TERMS OR THE APP, REGARDLESS OF THE FORM OF
              ACTION, IS LIMITED TO THE GREATER OF (a) THE AMOUNT YOU PAID
              TO APPLE FOR YOUR SUBSCRIPTION TO THE APP IN THE TWELVE MONTHS
              BEFORE THE CLAIM, OR (b) ONE HUNDRED U.S. DOLLARS ($100). SOME
              JURISDICTIONS DO NOT ALLOW THE EXCLUSION OR LIMITATION OF
              CERTAIN DAMAGES, SO PORTIONS OF THIS SECTION MAY NOT APPLY TO
              YOU.
            </p>

            <h2>13. Governing Law &amp; Disputes</h2>
            <p>
              These Terms are governed by the laws of the State of Tennessee,
              United States, without regard to its conflict-of-laws rules.
              You agree that any legal action arising out of or related to
              the App or these Terms will be brought exclusively in the state
              or federal courts located in Davidson County, Tennessee, and
              you consent to the personal jurisdiction of those courts. The
              United Nations Convention on Contracts for the International
              Sale of Goods does not apply.
            </p>

            <h2>14. Apple-Specific Terms</h2>
            <p>
              These Terms are between you and Mabry Ventures, not Apple, and
              Mabry Ventures (not Apple) is solely responsible for the App
              and its content. Apple has no obligation to provide maintenance
              or support for the App. To the maximum extent permitted by
              applicable law, Apple has no warranty obligation whatsoever
              with respect to the App. Apple, and Apple&rsquo;s subsidiaries,
              are third-party beneficiaries of these Terms and may enforce
              them against you.
            </p>

            <h2>15. Changes to These Terms</h2>
            <p>
              We may revise these Terms from time to time. The
              &ldquo;Effective date&rdquo; above will reflect the latest
              revision. Material changes will be surfaced in-app or via the
              App Store listing&rsquo;s &ldquo;What&rsquo;s New&rdquo;
              section. Your continued use of the App after a revision
              constitutes acceptance of the updated Terms.
            </p>

            <h2>16. Contact</h2>
            <p>
              Questions about these Terms? Email{' '}
              <a href="mailto:legal@volumearc.app">legal@volumearc.app</a>{' '}
              or write to:
            </p>
            <p>
              Mabry Ventures, LLC
              <br />
              Attn: Legal
              <br />
              Nashville, Tennessee, USA
            </p>
          </section>
        </div>
      </Container>
    </article>
  )
}
