import Link from 'next/link'
import clsx from 'clsx'

const baseStyles = {
  solid:
    'inline-flex justify-center rounded-lg py-2 px-3 text-sm font-semibold transition-colors',
  outline:
    'inline-flex justify-center rounded-lg border py-[calc(--spacing(2)-1px)] px-[calc(--spacing(3)-1px)] text-sm transition-colors',
}

const variantStyles = {
  solid: {
    // VolumeArc brand — sunrise orange. VOL-228 fix: original
    // `bg-sunrise-500` (#F26B33) on white text was 3.27:1 — below
    // the WCAG AA 4.5:1 threshold for `text-sm font-semibold`,
    // which axe-core flagged on every page that renders a CTA
    // button (homepage, /privacy, /terms, /support, /quality, etc.).
    // `bg-sunrise-700` (`#D14F1C`, the palette's `primaryDeep`
    // anchor) clocks at ~5.07:1 vs white — well clear of the AA
    // floor. The active state stays at `sunrise-800` (~6.5:1) so
    // the press feedback remains a darker shade.
    sunrise:
      'relative overflow-hidden bg-sunrise-700 text-white shadow-sm shadow-sunrise-700/25 before:absolute before:inset-0 active:before:bg-transparent hover:before:bg-white/10 active:bg-sunrise-800 active:text-white/80 before:transition-colors',
    // Inverted: white-on-dark hero CTA. Lands sunrise text on white pill.
    white:
      'bg-white text-sunrise-700 hover:bg-white/95 active:bg-white/90 active:text-sunrise-700/80',
    // Neutral fallback for secondary actions.
    gray: 'bg-gray-900 text-white hover:bg-gray-800 active:bg-gray-900 active:text-white/80',
  },
  outline: {
    gray: 'border-gray-300 text-gray-700 hover:border-gray-400 active:bg-gray-100 active:text-gray-700/80',
    sunrise:
      'border-sunrise-200 text-sunrise-700 hover:border-sunrise-400 hover:text-sunrise-800 active:bg-sunrise-50',
  },
}

type ButtonProps = (
  | {
      variant?: 'solid'
      color?: keyof typeof variantStyles.solid
    }
  | {
      variant: 'outline'
      color?: keyof typeof variantStyles.outline
    }
) &
  (
    | Omit<React.ComponentPropsWithoutRef<typeof Link>, 'color'>
    | (Omit<React.ComponentPropsWithoutRef<'button'>, 'color'> & {
        href?: undefined
      })
  )

export function Button({ className, ...props }: ButtonProps) {
  props.variant ??= 'solid'
  // Default to brand sunrise for solid CTAs, neutral gray for outline.
  if (props.variant === 'solid' && !props.color) props.color = 'sunrise'
  if (props.variant === 'outline' && !props.color) props.color = 'gray'

  className = clsx(
    baseStyles[props.variant],
    props.variant === 'outline'
      ? variantStyles.outline[props.color as keyof typeof variantStyles.outline]
      : variantStyles.solid[props.color as keyof typeof variantStyles.solid],
    className,
  )

  return typeof props.href === 'undefined' ? (
    <button className={className} {...props} />
  ) : (
    <Link className={className} {...props} />
  )
}
