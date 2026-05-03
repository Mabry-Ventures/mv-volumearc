import { type Metadata } from 'next'
import { Inter } from 'next/font/google'
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
    </html>
  )
}
