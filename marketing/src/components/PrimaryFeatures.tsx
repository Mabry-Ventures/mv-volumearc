'use client'

import { Fragment, useEffect, useId, useRef, useState } from 'react'
import { Tab, TabGroup, TabList, TabPanel, TabPanels } from '@headlessui/react'
import clsx from 'clsx'
import {
  type MotionProps,
  type Variant,
  type Variants,
  AnimatePresence,
  motion,
} from 'framer-motion'
import { useDebouncedCallback } from 'use-debounce'

import { AppScreen } from '@/components/AppScreen'
import { CircleBackground } from '@/components/CircleBackground'
import { Container } from '@/components/Container'
import { PhoneFrame } from '@/components/PhoneFrame'

const MotionAppScreenHeader = motion(AppScreen.Header)
const MotionAppScreenBody = motion(AppScreen.Body)

interface CustomAnimationProps {
  isForwards: boolean
  changeCount: number
}

const features = [
  {
    name: 'AI coach with on-device fallback',
    description:
      'A three-tier provider chain. Premium routes to Gemini Pro via streaming SSE. Free routes to Gemini Flash Lite. Both fall back to Apple Foundation Models on-device when the network drops, then to a heuristic engine offline. Every prompt is template-validated against a 20-fixture eval matrix.',
    icon: CoachIcon,
    screen: CoachScreen,
  },
  {
    name: 'Apple Watch as the primary surface',
    description:
      'Start, log, and finish a session entirely from the watch — real HKWorkoutSession, native rest timer, set decisions, coach cues. Offline payload queue replays to the phone the moment connectivity returns.',
    icon: WatchIcon,
    screen: WatchScreen,
  },
  {
    name: 'Readiness from real recovery data',
    description:
      'Five-factor readiness score derived from HRV trend, sleep debt, training load, recovery, and recent volume — all from HealthKit. The coach reads this context before answering, so the prescription matches the body that opened the app.',
    icon: ReadinessIcon,
    screen: ReadinessScreen,
  },
]

function CoachIcon(props: React.ComponentPropsWithoutRef<'svg'>) {
  return (
    <svg viewBox="0 0 32 32" aria-hidden="true" {...props}>
      <circle cx={16} cy={16} r={16} fill="#A3A3A3" fillOpacity={0.2} />
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M8 8a4 4 0 014-4h8a4 4 0 014 4v9a4 4 0 01-4 4h-3l-4 4v-4h-1a4 4 0 01-4-4V8zm6 5a1 1 0 100-2 1 1 0 000 2zm5-1a1 1 0 11-2 0 1 1 0 012 0zm-9 5a1 1 0 100-2 1 1 0 000 2z"
        fill="#737373"
      />
    </svg>
  )
}

function WatchIcon(props: React.ComponentPropsWithoutRef<'svg'>) {
  return (
    <svg viewBox="0 0 32 32" aria-hidden="true" {...props}>
      <circle cx={16} cy={16} r={16} fill="#A3A3A3" fillOpacity={0.2} />
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M11 4h10l-1 4h-8l-1-4zm-1 5a3 3 0 013-3h6a3 3 0 013 3v14a3 3 0 01-3 3h-6a3 3 0 01-3-3V9zm1 19h10l-1-4h-8l-1 4zm5-7a5 5 0 100-10 5 5 0 000 10zm.5-7v3l2 1.5"
        stroke="#737373"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  )
}

function ReadinessIcon(props: React.ComponentPropsWithoutRef<'svg'>) {
  let id = useId()

  return (
    <svg viewBox="0 0 32 32" fill="none" aria-hidden="true" {...props}>
      <defs>
        <linearGradient
          id={`${id}-gradient`}
          x1={16}
          y1={6}
          x2={16}
          y2={26}
          gradientUnits="userSpaceOnUse"
        >
          <stop stopColor="#F26B33" />
          <stop offset={1} stopColor="#F26B33" stopOpacity={0.3} />
        </linearGradient>
      </defs>
      <circle cx={16} cy={16} r={16} fill="#A3A3A3" fillOpacity={0.2} />
      <path
        d="M16 6 L24 12 L21 24 L11 24 L8 12 Z"
        stroke={`url(#${id}-gradient)`}
        strokeWidth={2}
        strokeLinejoin="round"
      />
      <text
        x={16}
        y={19}
        textAnchor="middle"
        fontSize={9}
        fontWeight={600}
        fill="#171717"
      >
        82
      </text>
    </svg>
  )
}

const headerAnimation: Variants = {
  initial: { opacity: 0, transition: { duration: 0.3 } },
  animate: { opacity: 1, transition: { duration: 0.3, delay: 0.3 } },
  exit: { opacity: 0, transition: { duration: 0.3 } },
}

const maxZIndex = 2147483647

const bodyVariantBackwards: Variant = {
  opacity: 0.4,
  scale: 0.8,
  zIndex: 0,
  filter: 'blur(4px)',
  transition: { duration: 0.4 },
}

const bodyVariantForwards: Variant = (custom: CustomAnimationProps) => ({
  y: '100%',
  zIndex: maxZIndex - custom.changeCount,
  transition: { duration: 0.4 },
})

const bodyAnimation: MotionProps = {
  initial: 'initial',
  animate: 'animate',
  exit: 'exit',
  variants: {
    initial: (custom: CustomAnimationProps, ...props) =>
      custom.isForwards
        ? bodyVariantForwards(custom, ...props)
        : bodyVariantBackwards,
    animate: (custom: CustomAnimationProps) => ({
      y: '0%',
      opacity: 1,
      scale: 1,
      zIndex: maxZIndex / 2 - custom.changeCount,
      filter: 'blur(0px)',
      transition: { duration: 0.4 },
    }),
    exit: (custom: CustomAnimationProps, ...props) =>
      custom.isForwards
        ? bodyVariantBackwards
        : bodyVariantForwards(custom, ...props),
  },
}

type ScreenProps =
  | {
      animated: true
      custom: CustomAnimationProps
    }
  | { animated?: false }

function CoachScreen(props: ScreenProps) {
  return (
    <AppScreen className="w-full">
      <MotionAppScreenHeader {...(props.animated ? headerAnimation : {})}>
        <AppScreen.Title>Coach</AppScreen.Title>
        <AppScreen.Subtitle>
          <span className="text-white">Ready to lift</span> · readiness 82
        </AppScreen.Subtitle>
      </MotionAppScreenHeader>
      <MotionAppScreenBody
        {...(props.animated ? { ...bodyAnimation, custom: props.custom } : {})}
      >
        <div className="space-y-4 px-4 py-6 text-sm">
          <div className="rounded-2xl bg-gray-100 p-4">
            <p className="text-xs font-semibold tracking-wide text-gray-500 uppercase">
              You
            </p>
            <p className="mt-2 text-gray-900">
              Last week I hit 5×5 at 225. Should I push to 230 today or hold?
            </p>
          </div>
          <div className="rounded-2xl bg-sunrise-500 p-4 text-white">
            <p className="text-xs font-semibold tracking-wide text-sunrise-100 uppercase">
              VolumeArc · Pro
            </p>
            <p className="mt-2">
              HRV is up 6% vs your 28-day baseline and you slept 7h42m. Push to
              230×5×5. If bar speed slows on set 3, drop to 225 for the last
              two — log RPE so I can recalibrate next session.
            </p>
          </div>
          <div className="rounded-full bg-sunrise-50 px-3 py-1.5 text-center text-xs font-medium text-sunrise-700">
            Streaming · first token 0.6s · Gemini Pro
          </div>
        </div>
      </MotionAppScreenBody>
    </AppScreen>
  )
}

function WatchScreen(props: ScreenProps) {
  return (
    <AppScreen className="w-full">
      <MotionAppScreenHeader {...(props.animated ? headerAnimation : {})}>
        <AppScreen.Title>Lower Strength</AppScreen.Title>
        <AppScreen.Subtitle>
          <span className="text-white">Set 3 of 5</span> · 230 lb
        </AppScreen.Subtitle>
      </MotionAppScreenHeader>
      <MotionAppScreenBody
        {...(props.animated ? { ...bodyAnimation, custom: props.custom } : {})}
      >
        <div className="px-4 py-6">
          <div className="rounded-3xl bg-gray-900 p-6 text-center text-white">
            <p className="text-xs font-semibold tracking-wide text-gray-400 uppercase">
              Rest timer
            </p>
            <p className="mt-3 font-mono text-5xl">1:23</p>
            <p className="mt-3 text-sm text-gray-400">Bar speed: target met</p>
          </div>
          <div className="mt-6 grid grid-cols-3 gap-3">
            {[
              { label: 'Decrease', tone: 'bg-rose-50 text-rose-700' },
              { label: 'Hold', tone: 'bg-gray-100 text-gray-900' },
              { label: 'Increase', tone: 'bg-emerald-50 text-emerald-700' },
            ].map((item) => (
              <div
                key={item.label}
                className={clsx(
                  'rounded-2xl px-2 py-3 text-center text-xs font-semibold',
                  item.tone,
                )}
              >
                {item.label}
              </div>
            ))}
          </div>
        </div>
      </MotionAppScreenBody>
    </AppScreen>
  )
}

function ReadinessScreen(props: ScreenProps) {
  return (
    <AppScreen className="w-full">
      <MotionAppScreenHeader {...(props.animated ? headerAnimation : {})}>
        <AppScreen.Title>Today</AppScreen.Title>
        <AppScreen.Subtitle>
          <span className="text-white">Readiness 82</span> · ready to push
        </AppScreen.Subtitle>
      </MotionAppScreenHeader>
      <MotionAppScreenBody
        {...(props.animated ? { ...bodyAnimation, custom: props.custom } : {})}
      >
        <div className="px-4 py-6">
          <div className="rounded-3xl bg-gradient-to-br from-sunrise-500 to-coral-500 p-6 text-white">
            <p className="text-xs font-semibold tracking-wide text-sunrise-100 uppercase">
              Readiness
            </p>
            <p className="mt-2 text-5xl font-medium tracking-tight">82</p>
            <p className="mt-2 text-sm text-sunrise-100">out of 100</p>
          </div>
          <div className="mt-6 space-y-3 text-sm">
            {[
              { label: 'HRV trend', value: '+6% vs 28d', tone: 'text-sunrise-600' },
              { label: 'Sleep debt', value: '0:18', tone: 'text-gray-900' },
              {
                label: 'Training load (7d)',
                value: '4 sessions',
                tone: 'text-gray-900',
              },
              {
                label: 'Recovery',
                value: 'On track',
                tone: 'text-emerald-600',
              },
              {
                label: 'Volume vs target',
                value: '92%',
                tone: 'text-gray-900',
              },
            ].map((row) => (
              <div
                key={row.label}
                className="flex items-center justify-between border-b border-gray-100 pb-2"
              >
                <span className="text-gray-500">{row.label}</span>
                <span className={clsx('font-semibold', row.tone)}>
                  {row.value}
                </span>
              </div>
            ))}
          </div>
        </div>
      </MotionAppScreenBody>
    </AppScreen>
  )
}

function usePrevious<T>(value: T) {
  let ref = useRef<T | undefined>(undefined)

  useEffect(() => {
    ref.current = value
  }, [value])

  return ref.current
}

function FeaturesDesktop() {
  let [changeCount, setChangeCount] = useState(0)
  let [selectedIndex, setSelectedIndex] = useState(0)
  let prevIndex = usePrevious(selectedIndex)
  let isForwards = prevIndex === undefined ? true : selectedIndex > prevIndex

  let onChange = useDebouncedCallback(
    (selectedIndex) => {
      setSelectedIndex(selectedIndex)
      setChangeCount((changeCount) => changeCount + 1)
    },
    100,
    { leading: true },
  )

  return (
    <TabGroup
      className="grid grid-cols-12 items-center gap-8 lg:gap-16 xl:gap-24"
      selectedIndex={selectedIndex}
      onChange={onChange}
      vertical
    >
      <TabList className="relative z-10 order-last col-span-6 space-y-6">
        {features.map((feature, featureIndex) => (
          <div
            key={feature.name}
            className="relative rounded-2xl transition-colors hover:bg-gray-800/30"
          >
            {featureIndex === selectedIndex && (
              <motion.div
                layoutId="activeBackground"
                className="absolute inset-0 bg-gray-800"
                initial={{ borderRadius: 16 }}
              />
            )}
            <div className="relative z-10 p-8">
              <feature.icon className="h-8 w-8" />
              <h3 className="mt-6 text-lg font-semibold text-white">
                <Tab className="text-left data-selected:not-data-focus:outline-hidden">
                  <span className="absolute inset-0 rounded-2xl" />
                  {feature.name}
                </Tab>
              </h3>
              <p className="mt-2 text-sm text-gray-400">
                {feature.description}
              </p>
            </div>
          </div>
        ))}
      </TabList>
      <div className="relative col-span-6">
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2">
          <CircleBackground color="#F26B33" className="animate-spin-slower" />
        </div>
        <PhoneFrame className="z-10 mx-auto w-full max-w-[366px]">
          <TabPanels as={Fragment}>
            <AnimatePresence
              initial={false}
              custom={{ isForwards, changeCount }}
            >
              {features.map((feature, featureIndex) =>
                selectedIndex === featureIndex ? (
                  <TabPanel
                    static
                    key={feature.name + changeCount}
                    className="col-start-1 row-start-1 flex focus:outline-offset-32 data-selected:not-data-focus:outline-hidden"
                  >
                    <feature.screen
                      animated
                      custom={{ isForwards, changeCount }}
                    />
                  </TabPanel>
                ) : null,
              )}
            </AnimatePresence>
          </TabPanels>
        </PhoneFrame>
      </div>
    </TabGroup>
  )
}

function FeaturesMobile() {
  let [activeIndex, setActiveIndex] = useState(0)
  let slideContainerRef = useRef<React.ElementRef<'div'>>(null)
  let slideRefs = useRef<Array<React.ElementRef<'div'>>>([])

  useEffect(() => {
    let observer = new window.IntersectionObserver(
      (entries) => {
        for (let entry of entries) {
          if (entry.isIntersecting && entry.target instanceof HTMLDivElement) {
            setActiveIndex(slideRefs.current.indexOf(entry.target))
            break
          }
        }
      },
      {
        root: slideContainerRef.current,
        threshold: 0.6,
      },
    )

    for (let slide of slideRefs.current) {
      if (slide) {
        observer.observe(slide)
      }
    }

    return () => {
      observer.disconnect()
    }
  }, [slideContainerRef, slideRefs])

  return (
    <>
      <div
        ref={slideContainerRef}
        className="-mb-4 flex snap-x snap-mandatory -space-x-4 overflow-x-auto overscroll-x-contain scroll-smooth pb-4 [scrollbar-width:none] sm:-space-x-6 [&::-webkit-scrollbar]:hidden"
      >
        {features.map((feature, featureIndex) => (
          <div
            key={featureIndex}
            ref={(ref) => {
              if (ref) {
                slideRefs.current[featureIndex] = ref
              }
            }}
            className="w-full flex-none snap-center px-4 sm:px-6"
          >
            <div className="relative transform overflow-hidden rounded-2xl bg-gray-800 px-5 py-6">
              <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2">
                <CircleBackground
                  color="#F26B33"
                  className={featureIndex % 2 === 1 ? 'rotate-180' : undefined}
                />
              </div>
              <PhoneFrame className="relative mx-auto w-full max-w-[366px]">
                <feature.screen />
              </PhoneFrame>
              <div className="absolute inset-x-0 bottom-0 bg-gray-800/95 p-6 backdrop-blur-sm sm:p-10">
                <feature.icon className="h-8 w-8" />
                <h3 className="mt-6 text-sm font-semibold text-white sm:text-lg">
                  {feature.name}
                </h3>
                <p className="mt-2 text-sm text-gray-400">
                  {feature.description}
                </p>
              </div>
            </div>
          </div>
        ))}
      </div>
      <div className="mt-6 flex justify-center gap-3">
        {features.map((_, featureIndex) => (
          <button
            type="button"
            key={featureIndex}
            className={clsx(
              'relative h-0.5 w-4 rounded-full',
              featureIndex === activeIndex ? 'bg-gray-300' : 'bg-gray-500',
            )}
            aria-label={`Go to slide ${featureIndex + 1}`}
            onClick={() => {
              slideRefs.current[featureIndex].scrollIntoView({
                block: 'nearest',
                inline: 'nearest',
              })
            }}
          >
            <span className="absolute -inset-x-1.5 -inset-y-3" />
          </button>
        ))}
      </div>
    </>
  )
}

export function PrimaryFeatures() {
  return (
    <section
      id="features"
      aria-label="Primary features"
      className="bg-gray-900 py-20 sm:py-32"
    >
      <Container>
        <div className="mx-auto max-w-2xl lg:mx-0 lg:max-w-3xl">
          <h2 className="text-3xl font-medium tracking-tight text-white">
            Three things VolumeArc does that other strength apps don’t.
          </h2>
          <p className="mt-2 text-lg text-gray-400">
            On-device AI that works offline. A watch app that doesn’t need your
            phone. Readiness driven by your real recovery data, not a survey.
          </p>
        </div>
      </Container>
      <div className="mt-16 md:hidden">
        <FeaturesMobile />
      </div>
      <Container className="hidden md:mt-20 md:block">
        <FeaturesDesktop />
      </Container>
    </section>
  )
}
