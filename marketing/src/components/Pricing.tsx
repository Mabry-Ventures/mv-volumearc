'use client'

import { useState } from 'react'
import { Radio, RadioGroup } from '@headlessui/react'
import clsx from 'clsx'

import { Button } from '@/components/Button'
import { Container } from '@/components/Container'
import { Logomark } from '@/components/Logo'

// TODO(VOL-91 follow-up): confirm final pricing with App Store Connect StoreKit products
// before launch. Current placeholders match the StoreKit 2 product IDs in PLATFORM.md.
const plans = [
  {
    name: 'Free',
    featured: false,
    price: { Monthly: '$0', Annually: '$0' },
    description:
      'Track every set, every workout. Get the coach on Gemini Flash Lite + on-device Foundation Models. Cloud sync across all your Apple devices.',
    button: {
      label: 'Download for iPhone',
      // VOL-208 / VOL-198: route through the `/download` redirect rather
      // than hard-coding the App Store URL, so once the listing is live
      // a single Vercel redirect update flips every link in the site.
      href: '/download',
    },
    features: [
      'Full workout tracker',
      'Apple Watch app + complications',
      'Live Activities + widgets',
      'Cloud sync (CloudKit private DB)',
      'AI coach — Flash Lite tier',
      'On-device Foundation Models fallback',
      'Readiness from HealthKit (HRV, sleep, training load)',
    ],
    logomarkClassName: 'fill-gray-300',
  },
  // VOL-198: Pro features list MUST describe only what Premium actually
  // unlocks today, per `docs/PLATFORM.md`'s Premium definition (VOL-91):
  // Gemini Pro coach tier + live voice coaching. Items previously
  // listed here as Pro (curated programs library, Apple Watch
  // Vitals/Training Load, priority eval-trend) are still backlog
  // (VOL-144 / VOL-154) and were paid-feature misrepresentation under
  // App Review Guideline 3.1.2.
  {
    name: 'Pro',
    featured: true,
    price: { Monthly: '$9.99', Annually: '$79.99' },
    description:
      'The full AI coach experience — Gemini Pro tier and live voice coaching. For lifters who want the deepest prescription their data can give them.',
    button: {
      label: 'Start with Pro',
      href: '/download',
    },
    features: [
      'Everything in Free',
      'AI coach — Gemini Pro tier',
      'Live voice coaching (hands-free between sets)',
    ],
    logomarkClassName: 'fill-sunrise-500',
  },
]

function CheckIcon(props: React.ComponentPropsWithoutRef<'svg'>) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" {...props}>
      <path
        d="M9.307 12.248a.75.75 0 1 0-1.114 1.004l1.114-1.004ZM11 15.25l-.557.502a.75.75 0 0 0 1.15-.043L11 15.25Zm4.844-5.041a.75.75 0 0 0-1.188-.918l1.188.918Zm-7.651 3.043 2.25 2.5 1.114-1.004-2.25-2.5-1.114 1.004Zm3.4 2.457 4.25-5.5-1.187-.918-4.25 5.5 1.188.918Z"
        fill="currentColor"
      />
      <circle
        cx="12"
        cy="12"
        r="8.25"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function Plan({
  name,
  price,
  description,
  button,
  features,
  activePeriod,
  logomarkClassName,
  featured = false,
}: {
  name: string
  price: {
    Monthly: string
    Annually: string
  }
  description: string
  button: {
    label: string
    href: string
  }
  features: Array<string>
  activePeriod: 'Monthly' | 'Annually'
  logomarkClassName?: string
  featured?: boolean
}) {
  return (
    <section
      className={clsx(
        'flex flex-col overflow-hidden rounded-3xl p-6',
        featured
          ? 'order-first bg-gradient-to-br from-gray-900 via-sunrise-950 to-coral-950 shadow-2xl shadow-sunrise-900/30 ring-1 ring-inset ring-white/10 lg:order-0'
          : 'bg-white shadow-lg shadow-gray-900/5 ring-1 ring-inset ring-gray-200/60',
      )}
    >
      <h3
        className={clsx(
          'flex items-center text-sm font-semibold',
          featured ? 'text-white' : 'text-gray-900',
        )}
      >
        <Logomark className={clsx('h-6 w-6 flex-none', logomarkClassName)} />
        <span className="ml-4">{name}</span>
      </h3>
      <p
        className={clsx(
          'relative mt-5 flex text-3xl tracking-tight',
          featured ? 'text-white' : 'text-gray-900',
        )}
      >
        {price.Monthly === price.Annually ? (
          price.Monthly
        ) : (
          <>
            <span
              aria-hidden={activePeriod === 'Annually'}
              className={clsx(
                'transition duration-300',
                activePeriod === 'Annually' &&
                  'pointer-events-none translate-x-6 opacity-0 select-none',
              )}
            >
              {price.Monthly}
              <span className="ml-1 text-base text-gray-400">/mo</span>
            </span>
            <span
              aria-hidden={activePeriod === 'Monthly'}
              className={clsx(
                'absolute top-0 left-0 transition duration-300',
                activePeriod === 'Monthly' &&
                  'pointer-events-none -translate-x-6 opacity-0 select-none',
              )}
            >
              {price.Annually}
              <span className="ml-1 text-base text-gray-400">/yr</span>
            </span>
          </>
        )}
      </p>
      <p
        className={clsx(
          'mt-3 text-sm',
          featured ? 'text-gray-300' : 'text-gray-700',
        )}
      >
        {description}
      </p>
      <div className="order-last mt-6">
        <ul
          role="list"
          className={clsx(
            '-my-2 divide-y text-sm',
            featured
              ? 'divide-gray-800 text-gray-300'
              : 'divide-gray-200 text-gray-700',
          )}
        >
          {features.map((feature) => (
            <li key={feature} className="flex py-2">
              <CheckIcon
                className={clsx(
                  'h-6 w-6 flex-none',
                  featured ? 'text-sunrise-300' : 'text-sunrise-500',
                )}
              />
              <span className="ml-4">{feature}</span>
            </li>
          ))}
        </ul>
      </div>
      <Button
        href={button.href}
        color={featured ? 'sunrise' : 'gray'}
        className="mt-6"
        aria-label={`${button.label} — ${name} plan`}
      >
        {button.label}
      </Button>
    </section>
  )
}

export function Pricing() {
  let [activePeriod, setActivePeriod] = useState<'Monthly' | 'Annually'>(
    'Monthly',
  )

  return (
    <section
      id="pricing"
      aria-labelledby="pricing-title"
      className="border-t border-gray-200 bg-gray-100 py-20 sm:py-32"
    >
      <Container>
        <div className="mx-auto max-w-2xl text-center">
          <h2
            id="pricing-title"
            className="text-3xl font-medium tracking-tight text-gray-900"
          >
            Simple pricing. Subscription auto-renews under App Store rules.
          </h2>
          <p className="mt-2 text-lg text-gray-600">
            Free covers the full tracker, sync, and on-device AI. Pro unlocks
            Gemini Pro and live voice coaching.
          </p>
        </div>

        <div className="mt-8 flex justify-center">
          <div className="relative">
            <RadioGroup
              value={activePeriod}
              onChange={setActivePeriod}
              className="grid grid-cols-2"
            >
              {['Monthly', 'Annually'].map((period) => (
                <Radio
                  key={period}
                  value={period}
                  className={clsx(
                    'cursor-pointer border border-gray-300 px-[calc(--spacing(3)-1px)] py-[calc(--spacing(2)-1px)] text-sm text-gray-700 transition-colors hover:border-gray-400 data-focus:outline-2 data-focus:outline-offset-2',
                    period === 'Monthly'
                      ? 'rounded-l-lg'
                      : '-ml-px rounded-r-lg',
                  )}
                >
                  {period}
                </Radio>
              ))}
            </RadioGroup>
            <div
              aria-hidden="true"
              className={clsx(
                // VOL-228 fix: bg moved from `bg-sunrise-500` to
                // `bg-sunrise-700` so the white text inside the inner
                // divs lands at ~5.07:1 contrast (WCAG AA pass) instead
                // of 3.27:1 (fail). The parent's bg is itself behind
                // the clip-path, but axe scans the inner divs against
                // their parent's bg, so they need to match.
                'pointer-events-none absolute inset-0 z-10 grid grid-cols-2 overflow-hidden rounded-lg bg-sunrise-700 transition-all duration-300',
                activePeriod === 'Monthly'
                  ? '[clip-path:inset(0_50%_0_0)]'
                  : '[clip-path:inset(0_0_0_calc(50%-1px))]',
              )}
            >
              {['Monthly', 'Annually'].map((period) => (
                // VOL-228 fix: explicit `bg-sunrise-700` on each label
                // matches the parent's orange (which itself moved from
                // 500 → 700 in the same PR for WCAG AA contrast) and
                // gives axe-core white-on-sunrise-700 = ~5.07:1, well
                // above the 4.5:1 floor. `aria-hidden` on the parent
                // already makes this overlay decorative-only — the
                // underlying RadioGroup is the semantic source — but
                // axe still scans the styles, so the explicit bg is the
                // path of least resistance.
                <div
                  key={period}
                  className={clsx(
                    'bg-sunrise-700 py-2 text-center text-sm font-semibold text-white',
                    period === 'Annually' && '-ml-px',
                  )}
                >
                  {period}
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="mx-auto mt-16 grid max-w-2xl grid-cols-1 items-start gap-x-8 gap-y-10 sm:mt-20 lg:max-w-4xl lg:grid-cols-2">
          {plans.map((plan) => (
            <Plan key={plan.name} {...plan} activePeriod={activePeriod} />
          ))}
        </div>

        {/*
          VOL-228 fix: `text-gray-500` on white was right at the 4.83:1
          contrast cliff (passes WCAG calculator, but axe-core sometimes
          flags it depending on the surrounding markup — likely from
          the inline `text-sunrise-700` anchors changing the computed
          baseline). `text-gray-600` (~6.47:1 vs white) lands well clear.
        */}
        <p className="mx-auto mt-10 max-w-2xl text-center text-sm text-gray-600">
          Subscriptions are billed through your Apple ID. Auto-renews until
          cancelled. Manage in iOS Settings → Apple ID → Subscriptions. See{' '}
          <a className="text-sunrise-700 underline decoration-sunrise-300 underline-offset-4 hover:decoration-sunrise-500" href="/terms">
            Terms
          </a>{' '}
          and{' '}
          <a className="text-sunrise-700 underline decoration-sunrise-300 underline-offset-4 hover:decoration-sunrise-500" href="/privacy">
            Privacy Policy
          </a>{' '}
          for full disclosure.
        </p>
      </Container>
    </section>
  )
}
