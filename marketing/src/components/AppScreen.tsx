import { forwardRef } from 'react'
import clsx from 'clsx'

// Tiny VolumeArc mark for the in-phone status bar — orange arc reflects the
// app icon (App/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png) and
// "VolumeArc" wordmark in white sits on the dark phone-frame top.
function PhoneStatusMark(props: React.ComponentPropsWithoutRef<'svg'>) {
  return (
    <svg viewBox="0 0 110 24" fill="none" aria-hidden="true" {...props}>
      {/* Arc — matches the orange ring in the actual app icon */}
      <circle cx="12" cy="12" r="9" stroke="#ffffff" strokeOpacity="0.18" strokeWidth="2" />
      <path
        d="M12 3 a9 9 0 0 1 6.36 15.36"
        stroke="url(#vapStatusArcGrad)"
        strokeWidth="2.8"
        strokeLinecap="round"
        fill="none"
      />
      <circle cx="18.36" cy="18.36" r="1.6" fill="#3373D9" />
      <defs>
        <linearGradient id="vapStatusArcGrad" x1="3" y1="3" x2="20" y2="20" gradientUnits="userSpaceOnUse">
          <stop stopColor="#FFB37A" />
          <stop offset="0.6" stopColor="#F26B33" />
          <stop offset="1" stopColor="#C74A6E" />
        </linearGradient>
      </defs>
      <text
        x="30"
        y="16.5"
        fill="#ffffff"
        style={{
          fontFamily:
            '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
          fontSize: 12,
          fontWeight: 600,
          letterSpacing: '-0.02em',
        }}
      >
        VolumeArc
      </text>
    </svg>
  )
}

function MenuIcon(props: React.ComponentPropsWithoutRef<'svg'>) {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true" {...props}>
      <path
        d="M5 6h14M5 18h14M5 12h14"
        stroke="#fff"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function UserIcon(props: React.ComponentPropsWithoutRef<'svg'>) {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true" {...props}>
      <path
        d="M15 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM6.696 19h10.608c1.175 0 2.08-.935 1.532-1.897C18.028 15.69 16.187 14 12 14s-6.028 1.689-6.836 3.103C4.616 18.065 5.521 19 6.696 19Z"
        stroke="#fff"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export function AppScreen({
  children,
  className,
  ...props
}: React.ComponentPropsWithoutRef<'div'>) {
  return (
    <div className={clsx('flex flex-col', className)} {...props}>
      <div className="flex justify-between px-4 pt-4">
        <MenuIcon className="h-6 w-6 flex-none" />
        <PhoneStatusMark className="h-6 flex-none" />
        <UserIcon className="h-6 w-6 flex-none" />
      </div>
      {children}
    </div>
  )
}

AppScreen.Header = forwardRef<
  React.ElementRef<'div'>,
  { children: React.ReactNode }
>(function AppScreenHeader({ children }, ref) {
  return (
    <div ref={ref} className="mt-6 px-4 text-white">
      {children}
    </div>
  )
})

AppScreen.Title = forwardRef<
  React.ElementRef<'div'>,
  { children: React.ReactNode }
>(function AppScreenTitle({ children }, ref) {
  return (
    <div ref={ref} className="text-2xl text-white">
      {children}
    </div>
  )
})

AppScreen.Subtitle = forwardRef<
  React.ElementRef<'div'>,
  { children: React.ReactNode }
>(function AppScreenSubtitle({ children }, ref) {
  return (
    <div ref={ref} className="text-sm text-gray-500">
      {children}
    </div>
  )
})

AppScreen.Body = forwardRef<
  React.ElementRef<'div'>,
  { className?: string; children: React.ReactNode }
>(function AppScreenBody({ children, className }, ref) {
  return (
    <div
      ref={ref}
      className={clsx('mt-6 flex-auto rounded-t-2xl bg-white', className)}
    >
      {children}
    </div>
  )
})
