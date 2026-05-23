import { type Metadata } from 'next'

import { Container } from '@/components/Container'
import trendData from '@/data/coach-eval-trend.json'

export const metadata: Metadata = {
  title: 'Coach Quality',
  description:
    'Public eval-trend results for the VolumeArc AI coach. We publish our regression test outcomes so you can verify what the AI actually does.',
}

type AxisKey = 'readiness' | 'intent' | 'style'

type TrendAxisBucket = {
  label: string
  total: number
  passed: number
  failed: number
}

type CoachEvalFixtureResult = {
  id: string
  verdict: 'PASS' | 'FAIL'
  note: string
  intent: string
  style: string
  readiness: number | null
}

type CoachEvalTrendRecord = {
  timestamp: string
  sha: string
  runId: string
  total: number
  passed: number
  failed: number
  axes: Partial<Record<AxisKey, TrendAxisBucket[]>>
  fixtures: CoachEvalFixtureResult[]
}

const axisSeries: {
  key: AxisKey | 'overall'
  label: string
  color: string
}[] = [
  { key: 'readiness', label: 'Readiness', color: '#d14f1c' },
  { key: 'intent', label: 'Intent', color: '#0f766e' },
  { key: 'style', label: 'Style', color: '#4f46e5' },
]

const fixtureSummary = [
  {
    axis: 'Readiness × Intent',
    description:
      'Bucketed at readiness 45 / 60 / 72 / 82 / 88 across six intents: progression, deload, form, recovery, substitution, and free-form coaching.',
  },
  {
    axis: 'Coaching style',
    description:
      'Three personas: motivational, analytical, and minimal. The system prompt envelope is asserted to match the user setting on every render.',
  },
  {
    axis: 'Session history',
    description:
      'Cold-start, single-session, and established lifter histories. Tests verify that the coach references real prior context when present.',
  },
  {
    axis: 'Privacy mode',
    description:
      'Strict-mode redaction is asserted before an outbound prompt can leave the device for the relay-backed coach path.',
  },
]

const qualitySignals = [
  'Sentence-count cap so answers stay coach-like instead of essay-like.',
  'Numeric grounding from RPE, readiness, weight, reps, or load context.',
  'Readiness / fatigue references when the fixture expects recovery awareness.',
  'Pain-signal flagging so the coach does not recommend loading through pain.',
  'Banned-phrase guardrails for model and product-name leakage.',
]

function toFiniteNumber(value: unknown) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value
  }

  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : null
  }

  return null
}

function requireString(value: unknown, field: string) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Invalid docs/coach-eval-trend.json: ${field} is required`)
  }

  return value
}

function normalizeAxisBuckets(value: unknown, field: string) {
  if (value === undefined) {
    return []
  }

  if (!Array.isArray(value)) {
    throw new Error(
      `Invalid docs/coach-eval-trend.json: ${field} must be an array`,
    )
  }

  return value.map((bucket, index): TrendAxisBucket => {
    if (typeof bucket !== 'object' || bucket === null) {
      throw new Error(
        `Invalid docs/coach-eval-trend.json: ${field}[${index}] must be an object`,
      )
    }

    const record = bucket as Record<string, unknown>
    const total = toFiniteNumber(record.total)
    const passed = toFiniteNumber(record.passed)
    const failed = toFiniteNumber(record.failed)

    if (
      total === null ||
      passed === null ||
      failed === null ||
      total < 0 ||
      passed < 0 ||
      failed < 0 ||
      passed + failed > total
    ) {
      throw new Error(
        `Invalid docs/coach-eval-trend.json: ${field}[${index}] has invalid counts`,
      )
    }

    return {
      label: requireString(record.label, `${field}[${index}].label`),
      total,
      passed,
      failed,
    }
  })
}

function normalizeFixtureResult(
  value: unknown,
  index: number,
): CoachEvalFixtureResult {
  if (typeof value !== 'object' || value === null) {
    throw new Error(
      `Invalid docs/coach-eval-trend.json: fixtures[${index}] must be an object`,
    )
  }

  const record = value as Record<string, unknown>
  const verdictValue = requireString(
    record.verdict,
    `fixtures[${index}].verdict`,
  )

  if (verdictValue !== 'PASS' && verdictValue !== 'FAIL') {
    throw new Error(
      `Invalid docs/coach-eval-trend.json: fixtures[${index}].verdict must be PASS or FAIL`,
    )
  }
  const verdict: CoachEvalFixtureResult['verdict'] = verdictValue

  const readiness = toFiniteNumber(record.readiness)

  return {
    id: requireString(record.id, `fixtures[${index}].id`),
    verdict,
    note:
      typeof record.note === 'string' && record.note.trim() !== ''
        ? record.note
        : '-',
    intent: typeof record.intent === 'string' ? record.intent : 'unknown',
    style: typeof record.style === 'string' ? record.style : 'unknown',
    readiness,
  }
}

function normalizeTrendRecord(
  value: unknown,
  index: number,
): CoachEvalTrendRecord {
  if (typeof value !== 'object' || value === null) {
    throw new Error(
      `Invalid docs/coach-eval-trend.json: records[${index}] must be an object`,
    )
  }

  const record = value as Record<string, unknown>
  const timestamp = requireString(
    record.timestamp,
    `records[${index}].timestamp`,
  )
  const total = toFiniteNumber(record.total)
  const passed = toFiniteNumber(record.passed)
  const failed = toFiniteNumber(record.failed)

  if (Number.isNaN(Date.parse(timestamp))) {
    throw new Error(
      `Invalid docs/coach-eval-trend.json: records[${index}].timestamp is invalid`,
    )
  }

  if (
    total === null ||
    passed === null ||
    failed === null ||
    total <= 0 ||
    passed < 0 ||
    failed < 0 ||
    passed + failed > total
  ) {
    throw new Error(
      `Invalid docs/coach-eval-trend.json: records[${index}] has invalid counts`,
    )
  }

  if (
    record.axes !== undefined &&
    (typeof record.axes !== 'object' ||
      record.axes === null ||
      Array.isArray(record.axes))
  ) {
    throw new Error(
      `Invalid docs/coach-eval-trend.json: records[${index}].axes must be an object`,
    )
  }

  if (record.fixtures !== undefined && !Array.isArray(record.fixtures)) {
    throw new Error(
      `Invalid docs/coach-eval-trend.json: records[${index}].fixtures must be an array`,
    )
  }

  const axes = (record.axes ?? {}) as Record<string, unknown>
  const fixtures = record.fixtures

  return {
    timestamp,
    sha: requireString(record.sha, `records[${index}].sha`),
    runId: requireString(record.run_id, `records[${index}].run_id`),
    total,
    passed,
    failed,
    axes: {
      readiness: normalizeAxisBuckets(
        axes.readiness,
        `records[${index}].axes.readiness`,
      ),
      intent: normalizeAxisBuckets(
        axes.intent,
        `records[${index}].axes.intent`,
      ),
      style: normalizeAxisBuckets(axes.style, `records[${index}].axes.style`),
    },
    fixtures:
      fixtures === undefined ? [] : fixtures.map(normalizeFixtureResult),
  }
}

function loadTrendRecords() {
  const parsed = trendData as { records?: unknown }

  if (!Array.isArray(parsed.records)) {
    throw new Error(
      'Invalid docs/coach-eval-trend.json: records must be an array',
    )
  }

  return parsed.records
    .map(normalizeTrendRecord)
    .sort(
      (left, right) => Date.parse(left.timestamp) - Date.parse(right.timestamp),
    )
}

function formatDate(timestamp: string) {
  return new Intl.DateTimeFormat('en-US', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'UTC',
  }).format(new Date(timestamp))
}

function formatPassRate(record: CoachEvalTrendRecord) {
  const rate = (record.passed / record.total) * 100
  return Number.isInteger(rate) ? `${rate}%` : `${rate.toFixed(1)}%`
}

function countPassingStreak(records: CoachEvalTrendRecord[]) {
  let streak = 0

  for (const record of [...records].reverse()) {
    if (record.failed > 0) {
      break
    }

    streak += 1
  }

  return streak
}

function bucketRate(buckets: TrendAxisBucket[]) {
  const totals = buckets.reduce(
    (memo, bucket) => ({
      total: memo.total + bucket.total,
      passed: memo.passed + bucket.passed,
    }),
    { total: 0, passed: 0 },
  )

  return totals.total === 0 ? null : totals.passed / totals.total
}

function rateForRecord(
  record: CoachEvalTrendRecord,
  series: (typeof axisSeries)[number],
) {
  if (series.key === 'overall') {
    return record.passed / record.total
  }

  const axisRate = bucketRate(record.axes[series.key] ?? [])
  return axisRate
}

function chartPoint(
  record: CoachEvalTrendRecord,
  recordIndex: number,
  recordCount: number,
  series: (typeof axisSeries)[number],
) {
  const width = 640
  const paddingX = 30
  const paddingY = 28
  const innerWidth = width - paddingX * 2
  const innerHeight = 164
  const rate = rateForRecord(record, series)

  if (rate === null) {
    return null
  }

  const denominator = Math.max(recordCount - 1, 1)

  return {
    x: paddingX + (recordIndex / denominator) * innerWidth,
    y: paddingY + (1 - rate) * innerHeight,
    label: `${formatDate(record.timestamp)}: ${series.label} ${Math.round(
      rate * 100,
    )}% passing`,
  }
}

function TrendChart({ records }: { records: CoachEvalTrendRecord[] }) {
  const recentRecords = records.slice(-30)
  const hasAxisData = recentRecords.some((record) =>
    axisSeries.some((series) => rateForRecord(record, series) !== null),
  )
  const seriesToRender = hasAxisData
    ? axisSeries
    : [{ key: 'overall' as const, label: 'Overall', color: '#d14f1c' }]

  if (recentRecords.length === 0) {
    return (
      <div className="flex h-48 items-center justify-center rounded-xl border border-dashed border-gray-300 bg-gray-50 px-6 text-center sm:h-64">
        <p className="max-w-md text-sm text-gray-600">
          No public trend records have been committed yet. The nightly cron
          writes the first row after a scheduled run on main.
        </p>
      </div>
    )
  }

  return (
    <div>
      <svg
        aria-label="Coach eval pass-rate trend for the latest 30 public nightly runs"
        className="h-auto w-full overflow-visible"
        role="img"
        viewBox="0 0 640 220"
      >
        {[0, 0.25, 0.5, 0.75, 1].map((line) => {
          const y = 28 + (1 - line) * 164

          return (
            <g key={line}>
              <line
                stroke="#e5e7eb"
                strokeDasharray={line === 1 ? undefined : '4 6'}
                x1="30"
                x2="610"
                y1={y}
                y2={y}
              />
              <text
                fill="#6b7280"
                fontSize="12"
                textAnchor="end"
                x="22"
                y={y + 4}
              >
                {Math.round(line * 100)}
              </text>
            </g>
          )
        })}

        {seriesToRender.map((series) => {
          const points = recentRecords
            .map((record, index) =>
              chartPoint(record, index, recentRecords.length, series),
            )
            .filter(
              (point): point is NonNullable<typeof point> => point !== null,
            )
          const linePath = points
            .map((point) => `${point.x},${point.y}`)
            .join(' ')

          return (
            <g key={series.key}>
              {points.length > 1 ? (
                <polyline
                  fill="none"
                  points={linePath}
                  stroke={series.color}
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="4"
                />
              ) : null}

              {points.map((point) => (
                <g key={`${series.key}-${point.x}-${point.y}`}>
                  <title>{point.label}</title>
                  <circle cx={point.x} cy={point.y} fill="#fff" r="6" />
                  <circle cx={point.x} cy={point.y} fill={series.color} r="4" />
                </g>
              ))}
            </g>
          )
        })}
      </svg>

      <div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-xs font-medium text-gray-600">
        {seriesToRender.map((series) => (
          <span className="inline-flex items-center gap-2" key={series.key}>
            <span
              aria-hidden="true"
              className="h-2.5 w-2.5 rounded-full"
              style={{ backgroundColor: series.color }}
            />
            {series.label}
          </span>
        ))}
      </div>
    </div>
  )
}

function StatCard({
  label,
  value,
  detail,
}: {
  label: string
  value: string
  detail: string
}) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <p className="text-sm font-medium text-gray-500">{label}</p>
      <p className="mt-2 text-3xl font-semibold tracking-tight text-gray-900">
        {value}
      </p>
      <p className="mt-2 text-sm text-gray-600">{detail}</p>
    </div>
  )
}

function FixtureLastRunTable({
  latest,
}: {
  latest: CoachEvalTrendRecord | undefined
}) {
  if (latest === undefined) {
    return null
  }

  if (latest.fixtures.length === 0) {
    return (
      <div className="mt-6 rounded-xl border border-gray-200 bg-white p-5 text-sm text-gray-600">
        Fixture-level detail is not available for this legacy trend record. The
        nightly workflow now publishes fixture rows for every new run.
      </div>
    )
  }

  return (
    <section className="mt-6 rounded-xl border border-gray-200 bg-white p-5">
      <div className="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h3 className="text-base font-semibold text-gray-900">
            Last-run fixture table
          </h3>
          <p className="mt-1 text-sm text-gray-600">
            {latest.fixtures.length} fixtures from{' '}
            {formatDate(latest.timestamp)}.
          </p>
        </div>
      </div>

      <div className="mt-4 overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200 text-left text-sm">
          <thead>
            <tr className="text-xs font-semibold tracking-wide text-gray-500 uppercase">
              <th className="py-3 pr-4">Fixture</th>
              <th className="px-4 py-3">Axis</th>
              <th className="px-4 py-3">Status</th>
              <th className="py-3 pl-4">Assertion detail</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {latest.fixtures.map((fixture) => (
              <tr key={fixture.id}>
                <td className="max-w-xs py-3 pr-4 font-medium text-gray-900">
                  {fixture.id}
                </td>
                <td className="px-4 py-3 text-gray-600">
                  {fixture.intent} · {fixture.style}
                  {fixture.readiness === null
                    ? ''
                    : ` · readiness ${fixture.readiness}`}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={
                      fixture.verdict === 'PASS'
                        ? 'rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700'
                        : 'rounded-full bg-red-50 px-2.5 py-1 text-xs font-semibold text-red-700'
                    }
                  >
                    {fixture.verdict === 'PASS' ? 'Pass' : 'Fail'}
                  </span>
                </td>
                <td className="max-w-md py-3 pl-4 text-gray-600">
                  {fixture.verdict === 'PASS'
                    ? 'No failing assertion.'
                    : fixture.note}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}

export default function QualityPage() {
  const records = loadTrendRecords()
  const latest = records.at(-1)
  const passingStreak = countPassingStreak(records)
  const latestRunUrl = latest
    ? `https://github.com/Mabry-Ventures/mv-volumearc/actions/runs/${latest.runId}`
    : null
  const latestCommitUrl = latest
    ? `https://github.com/Mabry-Ventures/mv-volumearc/commit/${latest.sha}`
    : null

  return (
    <article className="bg-white py-20 sm:py-32">
      <Container>
        <div className="mx-auto max-w-5xl">
          <header className="max-w-4xl">
            <p className="text-sm font-semibold tracking-wide text-sunrise-700 uppercase">
              Quality
            </p>
            <h1 className="mt-2 text-4xl font-medium tracking-tight text-gray-900">
              Coach quality, in the open.
            </h1>
            <p className="mt-4 text-lg text-gray-600">
              Most fitness apps with an AI coach don&rsquo;t publish what their
              coach actually does. We publish ours. Every VolumeArc coach prompt
              goes through a regression harness, and the live-relay response
              layer writes its nightly results into this public trend.
            </p>
          </header>

          <section className="mt-10 rounded-2xl border border-gray-200 bg-gray-50 p-6">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <h2 className="text-xl font-semibold text-gray-900">
                  Latest nightly response eval
                </h2>
                <p className="mt-2 max-w-3xl text-sm text-gray-600">
                  Source:{' '}
                  <code className="rounded bg-white px-1.5 py-0.5 text-gray-800">
                    docs/coach-eval-trend.json
                  </code>
                  , mirrored into the marketing build. The workflow appends one
                  record on each scheduled main-branch run and keeps raw
                  per-fixture artifacts in GitHub Actions for 30 days.
                </p>
              </div>

              <div
                className={
                  latest === undefined
                    ? 'rounded-full border border-gray-200 bg-white px-3 py-1 text-sm font-semibold text-gray-700'
                    : latest.failed === 0
                      ? 'rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1 text-sm font-semibold text-emerald-700'
                      : 'rounded-full border border-red-200 bg-red-50 px-3 py-1 text-sm font-semibold text-red-700'
                }
              >
                {latest === undefined
                  ? 'Awaiting first run'
                  : latest.failed === 0
                    ? 'Passing'
                    : 'Needs attention'}
              </div>
            </div>

            <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <StatCard
                detail={
                  latest === undefined
                    ? 'No scheduled public run has been published yet.'
                    : `${latest.passed} of ${latest.total} fixtures passed.`
                }
                label="Pass rate"
                value={latest === undefined ? '—' : formatPassRate(latest)}
              />
              <StatCard
                detail={
                  latest === undefined
                    ? 'Trend starts after the first cron append.'
                    : `${records.length} public record${
                        records.length === 1 ? '' : 's'
                      } tracked.`
                }
                label="Passing streak"
                value={latest === undefined ? '—' : `${passingStreak}`}
              />
              <StatCard
                detail={
                  latest === undefined
                    ? 'GitHub Actions run links appear with the first record.'
                    : latest.failed === 0
                      ? 'No response-quality assertions failed.'
                      : `${latest.failed} fixture${
                          latest.failed === 1 ? '' : 's'
                        } need review.`
                }
                label="Failures"
                value={latest === undefined ? '—' : `${latest.failed}`}
              />
              <StatCard
                detail={
                  latest === undefined
                    ? 'The nightly schedule runs at 07:00 UTC.'
                    : 'Displayed in UTC to match the workflow log.'
                }
                label="Last run"
                value={
                  latest === undefined
                    ? 'Pending'
                    : formatDate(latest.timestamp)
                }
              />
            </div>

            <div className="mt-8 rounded-xl border border-gray-200 bg-white p-4">
              <TrendChart records={records} />
            </div>

            <FixtureLastRunTable latest={latest} />

            {latest === undefined ? null : (
              <div className="mt-5 flex flex-wrap gap-3 text-sm font-medium">
                <a
                  className="text-sunrise-700 underline decoration-sunrise-300 underline-offset-4"
                  href={latestRunUrl ?? undefined}
                >
                  View GitHub Actions run
                </a>
                <a
                  className="text-sunrise-700 underline decoration-sunrise-300 underline-offset-4"
                  href={latestCommitUrl ?? undefined}
                >
                  View source commit
                </a>
              </div>
            )}
          </section>

          <section className="mt-12">
            <h2 className="text-2xl font-semibold text-gray-900">
              What the harness covers
            </h2>
            <div className="mt-6 grid gap-6 sm:grid-cols-2">
              {fixtureSummary.map((row) => (
                <div
                  className="rounded-xl border border-gray-200 p-6"
                  key={row.axis}
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

          <section className="mt-12 grid gap-10 lg:grid-cols-[1fr_1.05fr]">
            <div>
              <h2 className="text-2xl font-semibold text-gray-900">
                Two layers of testing
              </h2>
              <div className="mt-5 space-y-5 text-base text-gray-700">
                <p>
                  <strong>Template layer.</strong> Pull-request CI renders every
                  fixture through <code>CoachPromptTemplate.render(...)</code>{' '}
                  and asserts the marker, intent envelope, style persona, and
                  verbatim user question stay intact.
                </p>
                <p>
                  <strong>Response layer.</strong> The nightly workflow signs a
                  relay request for each fixture, streams the production coach
                  response, appends the summary above, and fails the job if any
                  assertion fails.
                </p>
              </div>
            </div>

            <div className="rounded-xl border border-gray-200 bg-gray-50 p-6">
              <h3 className="text-base font-semibold text-gray-900">
                Response-quality assertions
              </h3>
              <ul className="mt-4 space-y-3 text-sm text-gray-700">
                {qualitySignals.map((signal) => (
                  <li className="flex gap-3" key={signal}>
                    <span
                      aria-hidden="true"
                      className="mt-1 h-2 w-2 flex-none rounded-full bg-sunrise-600"
                    />
                    <span>{signal}</span>
                  </li>
                ))}
              </ul>
            </div>
          </section>

          <section className="mt-12 max-w-4xl">
            <h2 className="text-2xl font-semibold text-gray-900">
              Why we publish this
            </h2>
            <p className="mt-3 text-base text-gray-700">
              LLMs drift. Frontier models change. Prompts that worked yesterday
              may degrade tomorrow. The honest answer to &ldquo;is the coach
              actually good?&rdquo; is to put the test results in front of you.
              If the trend turns red, the same workflow fails internally before
              a new coach regression can hide behind product copy.
            </p>
          </section>
        </div>
      </Container>
    </article>
  )
}
