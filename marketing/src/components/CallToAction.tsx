import { AppStoreLink } from '@/components/AppStoreLink'
import { CircleBackground } from '@/components/CircleBackground'
import { Container } from '@/components/Container'

export function CallToAction() {
  return (
    <section
      id="get-started"
      className="bg-sunrise-gradient relative overflow-hidden py-20 sm:py-28"
    >
      {/* Decorative orbiting circle — echoes the orange "arc" in the app icon
          (the brand mark itself). White-on-sunrise reads as the icon's white
          inner ring. */}
      <div className="absolute top-1/2 left-20 -translate-y-1/2 sm:left-1/2 sm:-translate-x-1/2">
        <CircleBackground color="#fff" className="animate-spin-slower" />
      </div>
      <Container className="relative">
        <div className="mx-auto max-w-md sm:text-center">
          <h2 className="font-display text-3xl font-semibold tracking-tight text-white sm:text-4xl">
            Train smarter today.
          </h2>
          <p className="mt-4 text-lg text-white/85">
            Free to install. Sign in with Apple. Your first coach response
            arrives in under two seconds.
          </p>
          <div className="mt-8 flex justify-center">
            <AppStoreLink color="white" />
          </div>
        </div>
      </Container>
    </section>
  )
}
