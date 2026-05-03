// TODO: replace placeholder mark with the real VolumeArc app icon SVG.
// Lives at App/Assets.xcassets/AppIcon.appiconset/ — export 40px artwork to SVG and inline here.

export function Logomark(props: React.ComponentPropsWithoutRef<'svg'>) {
  return (
    <svg viewBox="0 0 40 40" aria-hidden="true" {...props}>
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M20 0c11.046 0 20 8.954 20 20s-8.954 20-20 20S0 31.046 0 20 8.954 0 20 0Zm0 6a14 14 0 0 0-13.86 12h6.193a8 8 0 0 1 15.334 0h6.193A14 14 0 0 0 20 6Zm-7.667 16a8 8 0 0 0 15.334 0h-6.193a2 2 0 0 1-2.948 0h-6.193Z"
      />
    </svg>
  )
}

export function Logo(props: React.ComponentPropsWithoutRef<'svg'>) {
  return (
    <svg viewBox="0 0 168 40" aria-hidden="true" {...props}>
      <Logomark width="40" height="40" className="fill-cyan-500" />
      <text
        x="52"
        y="27"
        className="fill-gray-900"
        style={{
          fontFamily:
            'var(--font-inter), -apple-system, BlinkMacSystemFont, system-ui, sans-serif',
          fontSize: 22,
          fontWeight: 600,
          letterSpacing: '-0.02em',
        }}
      >
        VolumeArc
      </text>
    </svg>
  )
}
