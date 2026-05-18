import { type Metadata } from 'next'

import { Container } from '@/components/Container'

export const metadata: Metadata = {
  title: 'Coach Quality',
  description:
    'Public eval-trend results for the VolumeArc AI coach. We publish our regression test outcomes so you can verify what the AI actually does.',
}

const fixtureSummary = [
  {
    axis: 'Readiness × Intent',
    description:
      'Bucketed at readiness 45 / 60 / 72 / 82 / 88 across six intents (progression, deload, form, recovery, substitution, free).',
  },
  {
    axis: 'Coaching style',
    description:
      'Three personas: motivational, analytical, minimal. The system prompt envelope is asserted to match the user setting on every render.',
  },
  {
    axis: 'Session history',
    description:
      'Cold-start (0 sessions), single-session, established (5+ sessions). Tests verify the coach references real prior context when present.',
  },
  {
    axis: 'Privacy mode',
    description:
      'Strict-mode redaction is asserted to drop user identifiers from the outbound prompt envelope before it leaves the device.',
  },
]

export default function QualityPage() {
  return (
    <article className="bg-white py-20 sm:py-32">
      <Container>
        <div className="mx-auto max-w-4xl">
          <header>
            <p className="text-sm font-semibold tracking-wide text-sunrise-700 uppercase">Quality</p>
            <h1 className="mt-2 text-4xl font-medium tracking-tight text-gray-900">
              Coach quality, in the open.
            </h1>
            <p className="mt-4 text-lg text-gray-600">
              Most fitness apps with an AI coach don&rsquo;t publish what their
              coach actually does. We publish ours. Every coach prompt VolumeArc
              ships goes through a 20-fixture regression test. This page shows
              the latest results.
            </p>
          </header>

          <div className="mt-10 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
            <strong>Coming soon.</strong> The live eval-trend chart and
            per-fixture last-run table are wiring up in{' '}
            <a
              className="underline"
              href="https://linear.app/mabry-ventures/issue/VOL-148"
            >
              VOL-148
            </a>
            . The data source is{' '}
            <code>docs/coach-eval-trend.json</code> in the app repo, populated
            by the nightly response-eval CI job (
            <a
              className="underline"
              href="https://linear.app/mabry-ventures/issue/VOL-147"
            >
              VOL-147
            </a>
            ). Until then, this page describes what the harness covers.
          </div>

          <section className="mt-12">
            <h2 className="text-2xl font-semibold text-gray-900">
              What the harness covers
            </h2>
            <div className="mt-6 grid gap-6 sm:grid-cols-2">
              {fixtureSummary.map((row) => (
                <div
                  key={row.axis}
                  className="rounded-2xl border border-gray-200 p-6"
                >
                  <h3 className="text-base font-semibold text-gray-900">
                    {row.axis}
                  </h3>
                  <p className="mt-2 text-sm text-gray-700">
                    {row.description}
                  </p>
                </div>
              ))}
            </div>
          </section>

          <section className="mt-12">
            <h2 className="text-2xl font-semibold text-gray-900">
              Two layers of testing
            </h2>
            <div className="mt-6 space-y-6 text-base text-gray-700">
              <p>
                <strong>Template layer (hermetic, runs in CI).</strong> Every
                prompt rendered through{' '}
                <code>CoachPromptTemplate.render(...)</code> is asserted to
                contain the template marker, the intent envelope, the persona
                appropriate to the user&rsquo;s coaching style, and the verbatim
                question. A regression that bypasses the template drops the
                marker and trips the test. Runs on every pull request.
              </p>
              <p>
                <strong>Response layer (live-relay, runs nightly).</strong>{' '}
                Twenty fixtures POST to the production relay. Each response is
                checked for: maximum sentence count, presence of numeric
                grounding (RPE / weight / reps), reference to readiness state,
                no banned phrases (&ldquo;I don&rsquo;t know&rdquo;,
                &ldquo;ChatGPT&rdquo;, etc.), and pain-signal flagging where
                expected. A failed nightly run fails the GitHub Actions
                workflow — the cron-failure email and the Actions summary
                tab are the operator signals today. Automated Slack /
                Linear regression filing is a planned follow-up.
              </p>
            </div>
          </section>

          <section className="mt-12">
            <h2 className="text-2xl font-semibold text-gray-900">
              Why we publish this
            </h2>
            <p className="mt-3 text-base text-gray-700">
              LLMs drift. Frontier models change. Prompts that worked yesterday
              may degrade tomorrow. The only honest answer to &ldquo;is the
              coach actually good?&rdquo; is to put the test results in front of
              you. If you see a fixture failing or a trend going the wrong way,
              you&rsquo;ll see it here before we ship anything new.
            </p>
          </section>
        </div>
      </Container>
    </article>
  )
}
