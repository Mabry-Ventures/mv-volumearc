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

// VOL-210: schema.org JSON-LD structured data. SoftwareApplication +
// Organization + WebSite give Google's rich-results pipeline a clean
// shape for the App Store badge, the publisher, and site search. We
// don't include `offers` yet because final App Store pricing isn't
// locked in production (Pro is $9.99/mo / $79.99/yr per VOL-91 today
// but copy-team may revise pre-launch — VOL-216 ASC metadata is the
// SOT for what we publish). Once pricing is final, add `offers` /
// `Offer` here and the App Store search snippet will get the price.
const structuredData = [
  {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'VolumeArc',
    description:
      'AI-powered strength training app that runs on-device, drives prescription from your real recovery data, and lives natively on your Apple Watch.',
    applicationCategory: 'HealthApplication',
    operatingSystem: 'iOS 26, watchOS 26',
    url: 'https://volumearc.app',
    image: 'https://volumearc.app/og-image.png',
    publisher: {
      '@type': 'Organization',
      name: 'Mabry Ventures, LLC',
      url: 'https://mabryventures.com',
      address: {
        '@type': 'PostalAddress',
        addressLocality: 'Nashville',
        addressRegion: 'TN',
        addressCountry: 'US',
      },
    },
    softwareHelp: {
      '@type': 'CreativeWork',
      url: 'https://volumearc.app/support',
    },
  },
  {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: 'Mabry Ventures, LLC',
    url: 'https://mabryventures.com',
    sameAs: ['https://volumearc.app'],
    address: {
      '@type': 'PostalAddress',
      addressLocality: 'Nashville',
      addressRegion: 'TN',
      addressCountry: 'US',
    },
  },
  {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: 'VolumeArc',
    url: 'https://volumearc.app',
    publisher: {
      '@type': 'Organization',
      name: 'Mabry Ventures, LLC',
    },
  },
]

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className={clsx('bg-gray-50 antialiased', inter.variable)}>
      <head>
        {/*
          VOL-210: schema.org JSON-LD. Emitted as a script tag in head
          (not a Next/Script) so it's part of the static HTML payload
          and crawlable on the first GET — script tags loaded with
          `strategy="afterInteractive"` arrive after Google's crawler
          snapshots the page.
        */}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify(structuredData),
          }}
        />
      </head>
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
