import Image from 'next/image'
import clsx from 'clsx'

import iconLight from '@/images/logo-mark-light.png'
import iconDark from '@/images/logo-mark-dark.png'

// VolumeArc app icon — light and dark variants exported from
// App/Assets.xcassets/AppIcon.appiconset/. The icon's orange "arc"
// is literally the brand mark — match the iOS app exactly.

export function Logomark({
  className,
  variant = 'light',
  ...props
}: Omit<React.ComponentPropsWithoutRef<'div'>, 'children'> & {
  variant?: 'light' | 'dark'
}) {
  const src = variant === 'dark' ? iconDark : iconLight
  return (
    <div
      className={clsx('relative aspect-square overflow-hidden', className)}
      {...props}
    >
      <Image
        src={src}
        alt=""
        fill
        sizes="40px"
        className="object-contain"
        priority
      />
    </div>
  )
}

export function Logo({
  className,
  variant = 'light',
  ...props
}: Omit<React.ComponentPropsWithoutRef<'div'>, 'children'> & {
  variant?: 'light' | 'dark'
}) {
  return (
    <div
      className={clsx('flex items-center gap-2.5', className)}
      {...props}
    >
      <Logomark variant={variant} className="h-9 w-9 rounded-[20%]" />
      <span
        className={clsx(
          'font-display text-[20px] font-semibold tracking-tight',
          variant === 'dark' ? 'text-white' : 'text-gray-900',
        )}
      >
        VolumeArc
      </span>
    </div>
  )
}
