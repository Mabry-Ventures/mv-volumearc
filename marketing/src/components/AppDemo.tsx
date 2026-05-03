'use client'

import { useId, useRef, useState } from 'react'
import clsx from 'clsx'
import { motion, useInView, useMotionValue } from 'framer-motion'

import { AppScreen } from '@/components/AppScreen'

// Synthetic 30-day readiness trend used for the hero phone mockup.
// Values are bounded to a realistic 50–95 readiness range and mostly
// ascend so the chart reads as a "you're getting better" story.
const readiness = [
  62, 64, 60, 67, 71, 65, 69, 72, 68, 74, 76, 71, 75, 78, 72, 80, 82, 78, 81,
  84, 80, 83, 86, 82, 85, 88, 84, 87, 89, 82,
]
const maxReadiness = 100
const minReadiness = 40

function Chart({
  className,
  activePointIndex,
  onChangeActivePointIndex,
  width: totalWidth,
  height: totalHeight,
  paddingX = 0,
  paddingY = 0,
  gridLines = 6,
  ...props
}: React.ComponentPropsWithoutRef<'svg'> & {
  activePointIndex: number | null
  onChangeActivePointIndex: (index: number | null) => void
  width: number
  height: number
  paddingX?: number
  paddingY?: number
  gridLines?: number
}) {
  let width = totalWidth - paddingX * 2
  let height = totalHeight - paddingY * 2

  let id = useId()
  let svgRef = useRef<React.ElementRef<'svg'>>(null)
  let pathRef = useRef<React.ElementRef<'path'>>(null)
  let isInView = useInView(svgRef, { amount: 0.5, once: true })
  let pathWidth = useMotionValue(0)
  let [interactionEnabled, setInteractionEnabled] = useState(false)

  let path = ''
  let points: Array<{ x: number; y: number }> = []

  for (let index = 0; index < readiness.length; index++) {
    let x = paddingX + (index / (readiness.length - 1)) * width
    let y =
      paddingY +
      (1 - (readiness[index] - minReadiness) / (maxReadiness - minReadiness)) *
        height
    points.push({ x, y })
    path += `${index === 0 ? 'M' : 'L'} ${x.toFixed(4)} ${y.toFixed(4)}`
  }

  return (
    <svg
      ref={svgRef}
      viewBox={`0 0 ${totalWidth} ${totalHeight}`}
      className={clsx(className, 'overflow-visible')}
      {...(interactionEnabled
        ? {
            onPointerLeave: () => onChangeActivePointIndex(null),
            onPointerMove: (event) => {
              let x = event.nativeEvent.offsetX
              let closestPointIndex: number | null = null
              let closestDistance = Infinity
              for (
                let pointIndex = 0;
                pointIndex < points.length;
                pointIndex++
              ) {
                let point = points[pointIndex]
                let distance = Math.abs(point.x - x)
                if (distance < closestDistance) {
                  closestDistance = distance
                  closestPointIndex = pointIndex
                } else {
                  break
                }
              }
              onChangeActivePointIndex(closestPointIndex)
            },
          }
        : {})}
      {...props}
    >
      <defs>
        <clipPath id={`${id}-clip`}>
          <path d={`${path} V ${height + paddingY} H ${paddingX} Z`} />
        </clipPath>
        <linearGradient id={`${id}-gradient`} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stopColor="#F26B33" />
          <stop offset="100%" stopColor="#F26B33" stopOpacity="0" />
        </linearGradient>
      </defs>
      {[...Array(gridLines - 1).keys()].map((index) => (
        <line
          key={index}
          stroke="#a3a3a3"
          opacity="0.1"
          x1="0"
          y1={(totalHeight / gridLines) * (index + 1)}
          x2={totalWidth}
          y2={(totalHeight / gridLines) * (index + 1)}
        />
      ))}
      <motion.rect
        y={paddingY}
        width={pathWidth}
        height={height}
        fill={`url(#${id}-gradient)`}
        clipPath={`url(#${id}-clip)`}
        opacity="0.5"
      />
      <motion.path
        ref={pathRef}
        d={path}
        fill="none"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        initial={{ pathLength: 0 }}
        transition={{ duration: 1 }}
        {...(isInView ? { stroke: '#F26B33', animate: { pathLength: 1 } } : {})}
        onUpdate={({ pathLength }) => {
          if (pathRef.current && typeof pathLength === 'number') {
            pathWidth.set(
              pathRef.current.getPointAtLength(
                pathLength * pathRef.current.getTotalLength(),
              ).x,
            )
          }
        }}
        onAnimationComplete={() => setInteractionEnabled(true)}
      />
      {activePointIndex !== null && (
        <>
          <line
            x1="0"
            y1={points[activePointIndex].y}
            x2={totalWidth}
            y2={points[activePointIndex].y}
            stroke="#F26B33"
            strokeDasharray="1 3"
          />
          <circle
            r="4"
            cx={points[activePointIndex].x}
            cy={points[activePointIndex].y}
            fill="#fff"
            strokeWidth="2"
            stroke="#F26B33"
          />
        </>
      )}
    </svg>
  )
}

const recentSessions = [
  { name: 'Lower Strength', volume: '14,720 lb', when: 'Yesterday' },
  { name: 'Upper Hypertrophy', volume: '9,860 lb', when: 'Tue' },
  { name: 'Push Day', volume: '11,420 lb', when: 'Sun' },
]

export function AppDemo() {
  let [activePointIndex, setActivePointIndex] = useState<number | null>(null)
  let activeReadiness =
    readiness[activePointIndex ?? readiness.length - 1] ?? readiness[0]
  let trendDelta =
    activePointIndex && activePointIndex > 0
      ? activeReadiness - readiness[activePointIndex - 1]
      : null

  return (
    <AppScreen>
      <AppScreen.Body>
        <div className="p-4">
          <div className="flex items-baseline gap-2">
            <div className="text-xs/6 font-semibold text-gray-500 uppercase">
              VolumeArc · Today
            </div>
            <div className="ml-auto rounded-full bg-emerald-50 px-2 py-0.5 text-[10px] font-semibold text-emerald-700">
              Ready to push
            </div>
          </div>
          <div className="mt-3 border-t border-gray-200 pt-5">
            <div className="flex items-baseline gap-2">
              <div className="text-3xl font-medium tracking-tight text-gray-900 tabular-nums">
                {activeReadiness}
              </div>
              <div className="text-sm text-gray-500">readiness · 30d</div>
              {trendDelta !== null && (
                <div
                  className={clsx(
                    'ml-auto text-sm tracking-tight tabular-nums',
                    trendDelta >= 0 ? 'text-sunrise-500' : 'text-gray-500',
                  )}
                >
                  {`${trendDelta >= 0 ? '+' : ''}${trendDelta}`}
                </div>
              )}
            </div>
            <div className="mt-6 flex gap-4 text-xs text-gray-500">
              <div>7D</div>
              <div className="font-semibold text-sunrise-600">30D</div>
              <div>90D</div>
              <div>1Y</div>
              <div>All</div>
            </div>
            <div className="mt-3 rounded-lg bg-gray-50 ring-1 ring-black/5 ring-inset">
              <Chart
                width={286}
                height={172}
                paddingX={16}
                paddingY={28}
                activePointIndex={activePointIndex}
                onChangeActivePointIndex={setActivePointIndex}
              />
            </div>
            <div className="mt-4 rounded-lg bg-sunrise-500 px-4 py-2 text-center text-sm font-semibold text-white">
              Start next workout
            </div>
            <div className="mt-3 divide-y divide-gray-100 text-sm">
              {recentSessions.map((session) => (
                <div
                  key={session.name}
                  className="flex items-center justify-between py-1.5"
                >
                  <div>
                    <div className="font-medium text-gray-900">
                      {session.name}
                    </div>
                    <div className="text-xs text-gray-500">{session.when}</div>
                  </div>
                  <div className="text-xs font-semibold tabular-nums text-gray-900">
                    {session.volume}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </AppScreen.Body>
    </AppScreen>
  )
}
