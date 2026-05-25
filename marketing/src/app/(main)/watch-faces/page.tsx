import type { Metadata } from 'next'

import { Container } from '@/components/Container'

export const metadata: Metadata = {
  title: 'Watch Faces - VolumeArc',
  description:
    'Designed Apple Watch face presets for VolumeArc readiness, next workout, last session, and streak complications.',
}

const presets = [
  {
    name: 'VolumeArc Modular',
    family: 'Modular Duo',
    summary: 'A daily training dashboard for deciding what to do next.',
    tone: 'OLED black with sunrise accents',
    face: 'modular',
    slots: ['Readiness', 'Next Workout', 'Last Session', 'Streak'],
  },
  {
    name: 'VolumeArc Infograph',
    family: 'Infograph',
    summary: 'Dense power-user context without opening the app.',
    tone: 'Analog dial with readiness arc',
    face: 'infograph',
    slots: ['Readiness Bezel', 'Next Workout', 'Last Session', 'Streak'],
  },
  {
    name: 'VolumeArc Photo',
    family: 'Photos',
    summary: 'Personal-photo face with two useful VolumeArc anchors.',
    tone: 'Full-bleed photo with quiet overlays',
    face: 'photo',
    slots: ['Readiness', 'Streak'],
  },
] as const

export default function WatchFacesPage() {
  return (
    <main className="bg-white">
      <section className="border-b border-gray-200 bg-gray-950 text-white">
        <Container>
          <div className="grid gap-10 pt-16 pb-14 lg:grid-cols-[0.9fr_1.1fr] lg:items-end lg:pt-20">
            <div>
              <p className="text-sm font-semibold text-orange-300">
                Apple Watch presets
              </p>
              <h1 className="mt-4 text-4xl font-semibold tracking-normal text-white sm:text-5xl">
                VolumeArc Watch Faces
              </h1>
              <p className="mt-5 max-w-2xl text-base leading-7 text-gray-300">
                Three designed faces bring readiness, the next lift, recent
                work, and streak context to the wrist so training decisions
                stay visible between sets.
              </p>
            </div>
            <div className="grid grid-cols-3 gap-3 sm:gap-5">
              {presets.map((preset) => (
                <WatchRender key={preset.name} face={preset.face} />
              ))}
            </div>
          </div>
        </Container>
      </section>

      <section className="py-16 sm:py-20">
        <Container>
          <div className="grid gap-6 lg:grid-cols-3">
            {presets.map((preset) => (
              <article
                key={preset.name}
                className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm"
              >
                <div className="mb-6 flex justify-center">
                  <WatchRender face={preset.face} large />
                </div>
                <p className="text-sm font-semibold text-orange-600">
                  {preset.family}
                </p>
                <h2 className="mt-2 text-2xl font-semibold tracking-normal text-gray-900">
                  {preset.name}
                </h2>
                <p className="mt-3 text-sm leading-6 text-gray-600">
                  {preset.summary}
                </p>
                <p className="mt-4 text-sm font-medium text-gray-900">
                  {preset.tone}
                </p>
                <ul className="mt-5 space-y-2">
                  {preset.slots.map((slot) => (
                    <li
                      key={slot}
                      className="flex items-center justify-between border-t border-gray-100 pt-2 text-sm"
                    >
                      <span className="text-gray-600">{slot}</span>
                      <span className="font-medium text-gray-900">
                        VolumeArc
                      </span>
                    </li>
                  ))}
                </ul>
              </article>
            ))}
          </div>
        </Container>
      </section>
    </main>
  )
}

function WatchRender({
  face,
  large = false,
}: {
  face: (typeof presets)[number]['face']
  large?: boolean
}) {
  return (
    <div
      className={[
        'relative rounded-[2rem] bg-gradient-to-br from-gray-600 via-gray-950 to-black p-1.5 shadow-2xl',
        large ? 'h-60 w-48' : 'h-40 w-full min-w-0',
      ].join(' ')}
      aria-hidden="true"
    >
      <div className="absolute top-12 -right-1 h-7 w-1.5 rounded bg-gray-500" />
      <div className="h-full overflow-hidden rounded-[1.6rem] bg-black">
        {face === 'modular' && <ModularFace />}
        {face === 'infograph' && <InfographFace />}
        {face === 'photo' && <PhotoFace />}
      </div>
    </div>
  )
}

function ModularFace() {
  return (
    <div className="flex h-full flex-col gap-1.5 p-3 text-white">
      <div className="flex items-baseline justify-between">
        <span className="text-lg font-bold text-orange-300">9:41</span>
        <span className="text-[0.55rem] font-semibold text-gray-400">MON</span>
      </div>
      <div className="flex items-center gap-2 rounded-lg bg-white/10 p-2">
        <div className="grid h-8 w-8 place-items-center rounded-full border-4 border-orange-300 text-[0.55rem] font-bold">
          82
        </div>
        <div>
          <div className="text-xs font-semibold">Readiness</div>
          <div className="text-[0.6rem] text-gray-400">Green light</div>
        </div>
      </div>
      <div className="rounded-lg bg-white/10 p-2 text-xs font-semibold">
        Push A <span className="text-[0.6rem] text-gray-400">Bench</span>
      </div>
      <div className="mt-auto grid grid-cols-2 gap-1.5">
        <MiniStat label="Last" value="12.4k" />
        <MiniStat label="Streak" value="16" />
      </div>
    </div>
  )
}

function InfographFace() {
  return (
    <div className="relative h-full text-white">
      <div className="absolute inset-4 rounded-full border border-white/20" />
      <div className="absolute inset-x-8 top-5 h-12 rounded-t-full border-t-4 border-orange-400" />
      <span className="absolute top-4 left-4 text-xs font-bold">82</span>
      <span className="absolute top-4 right-4 text-xs font-bold">Push</span>
      <span className="absolute bottom-5 left-4 text-xs font-bold">12k</span>
      <span className="absolute right-4 bottom-5 text-xs font-bold">16</span>
      <div className="grid h-full place-items-center text-lg font-bold">9:41</div>
    </div>
  )
}

function PhotoFace() {
  return (
    <div className="relative h-full bg-[radial-gradient(circle_at_70%_20%,rgba(92,153,230,0.45),transparent_35%),linear-gradient(150deg,#111827,#21120c_70%,#050505)] text-white">
      <div className="absolute inset-0 bg-gradient-to-b from-black/0 via-black/10 to-black/65" />
      <span className="absolute top-7 left-3 text-xs font-bold text-orange-300">
        82
      </span>
      <span className="absolute top-7 right-3 text-xs font-bold text-orange-300">
        16
      </span>
      <div className="absolute inset-x-0 bottom-9 text-center text-3xl font-black">
        9:41
      </div>
    </div>
  )
}

function MiniStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-white/10 p-1.5">
      <div className="text-[0.5rem] font-bold text-gray-400">{label}</div>
      <div className="text-xs font-bold">{value}</div>
    </div>
  )
}
