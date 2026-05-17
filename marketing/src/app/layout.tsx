import { type Metadata } from 'next'
import { Inter } from 'next/font/google'
import Script from 'next/script'
import clsx from 'clsx'

import '@/styles/tailwind.css'

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-inter',
})

export const metadata: Metadata = {
  metadataBase: new URL('https://volumearc.app'),
  title: {
    template: '%s · VolumeArc',
    default: 'VolumeArc — The deepest Apple-ecosystem strength coach',
  },
  description:
    'AI-powered strength training that runs on-device, drives prescription from your real recovery data, and lives natively on your Apple Watch. Built for iOS 26 + watchOS 26.',
  applicationName: 'VolumeArc',
  authors: [{ name: 'Mabry Ventures', url: 'https://mabryventures.com' }],
  keywords: [
    'strength training',
    'AI coach',
    'Apple Watch',
    'iOS 26',
    'watchOS 26',
    'Foundation Models',
    'HealthKit',
    'workout tracker',
    'lifting app',
  ],
  openGraph: {
    title: 'VolumeArc — The deepest Apple-ecosystem strength coach',
    description:
      'AI-powered strength training that runs on-device, drives prescription from your real recovery data, and lives natively on your Apple Watch.',
    url: 'https://volumearc.app',
    siteName: 'VolumeArc',
    locale: 'en_US',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'VolumeArc — The deepest Apple-ecosystem strength coach',
    description:
      'AI-powered strength training that runs on-device, drives prescription from your real recovery data, and lives natively on your Apple Watch.',
  },
  robots: {
    index: true,
    follow: true,
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className={clsx('bg-gray-50 antialiased', inter.variable)}>
      <body>{children}</body>
      {/*
        VOL-189: Plausible analytics (privacy-friendly, cookie-less,
        IP-anonymized — no GDPR consent banner required). Loaded with
        `afterInteractive` so analytics never blocks the initial render
        or hurts LCP. The init script is a separate `<Script>` tag so
        Next.js can manage its lifecycle alongside the bundle script.
        Active on production + Vercel preview deploys; preview noise is
        acceptable given the scale.
      */}
      <Script
        async
        src="https://plausible.io/js/pa-a38d_pbJeue8jQZq5p7QK.js"
        strategy="afterInteractive"
      />
      <Script id="plausible-init" strategy="afterInteractive">
        {`window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init()`}
      </Script>
    </html>
  )
}
