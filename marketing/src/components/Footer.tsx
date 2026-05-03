import Link from 'next/link'

import { Container } from '@/components/Container'
import { Logomark } from '@/components/Logo'

const footerNav = [
  {
    heading: 'Product',
    links: [
      { label: 'Features', href: '/#features' },
      { label: 'Pricing', href: '/#pricing' },
      { label: 'FAQs', href: '/#faqs' },
      { label: 'Coach quality', href: '/quality' },
    ],
  },
  {
    heading: 'Company',
    links: [
      { label: 'Mabry Ventures', href: 'https://mabryventures.com' },
      { label: 'Support', href: '/support' },
      { label: 'Press', href: '/support#press' },
    ],
  },
  {
    heading: 'Legal',
    links: [
      { label: 'Privacy Policy', href: '/privacy' },
      { label: 'Terms of Service', href: '/terms' },
    ],
  },
]

export function Footer() {
  return (
    <footer className="border-t border-gray-200 bg-white">
      <Container>
        <div className="grid grid-cols-1 gap-y-12 pt-16 pb-10 sm:grid-cols-4 sm:gap-x-8 lg:py-16">
          <div className="sm:col-span-1">
            <div className="flex items-center text-gray-900">
              <Logomark className="h-10 w-10 flex-none fill-cyan-500" />
              <div className="ml-3">
                <p className="text-base font-semibold tracking-tight">
                  VolumeArc
                </p>
                <p className="mt-0.5 text-sm text-gray-500">
                  Deepest Apple-ecosystem strength coach.
                </p>
              </div>
            </div>
          </div>
          {footerNav.map((section) => (
            <div key={section.heading}>
              <h3 className="text-sm font-semibold text-gray-900">
                {section.heading}
              </h3>
              <ul role="list" className="mt-4 space-y-3">
                {section.links.map((link) => (
                  <li key={link.label}>
                    <Link
                      href={link.href}
                      className="text-sm text-gray-600 hover:text-gray-900"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="flex flex-col items-start gap-y-3 border-t border-gray-200 py-8 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-gray-500">
            &copy; {new Date().getFullYear()} Mabry Ventures, LLC. All rights
            reserved.
          </p>
          <p className="text-sm text-gray-500">
            VolumeArc requires iOS 26 or later. Apple Watch features require
            watchOS 26.4 or later.
          </p>
        </div>
      </Container>
    </footer>
  )
}
