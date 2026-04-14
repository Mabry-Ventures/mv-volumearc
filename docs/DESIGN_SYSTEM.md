# Design System

VolumeArc's design system lives in `VolumeArcNative/Sources/VolumeArcUI/DesignSystem/`. It has two layers: **tokens** (the primitives) and **components** (composable views built from tokens).

## Tokens

All tokens are accessed through the `VA` namespace.

### Colors — `VA.Colors`

| Token | Usage |
|-------|-------|
| `primary` | Brand color. CTAs, active states, accent lines. |
| `secondary` | Secondary accent. Highlights, secondary actions. |
| `success` | Completions, confirmations, positive metrics. |
| `warning` | Deload recommendations, non-blocking alerts. |
| `error` | Failures, destructive actions. |
| `info` | Tips, neutral notices. |
| `surfacePrimary` | Main background. |
| `surfaceSecondary` | Card and grouped content background. |
| `surfaceTertiary` | Nested surfaces. |
| `textPrimary` | Main text. |
| `textSecondary` | Supporting text. |
| `textTertiary` | Placeholder, captions. |

All colors adapt to light/dark mode via `Color(light:dark:)`.

### Typography — `VA.Typography`

| Token | Size | Weight | Use |
|-------|------|--------|-----|
| `display` | 34pt | Bold | Hero numbers |
| `title` | 28pt | Bold | Screen titles |
| `title2` | 22pt | Semibold | Section titles, card headers |
| `headline` | 17pt | Semibold | Card titles |
| `body` | 17pt | Regular | Body text |
| `button` | 15pt | Semibold | Button labels |
| `footnote` | 13pt | Medium | Supporting text |
| `caption` | 11pt | Semibold | Captions, badges |
| `monoDigit` | 17pt | Regular | Aligned numeric values |
| `timerDisplay` | 44pt | Bold | Rest timer countdown |

### Spacing — `VA.Space`

4pt grid: `xxs: 2, xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32, xxxl: 48`.

### Radius — `VA.Radius`

`sm: 8, md: 12, lg: 16, xl: 24, full: 9999`.

### Shadow — `VA.Shadow`

Elevation scale: `none, sm, md, lg`. Apply with `.vaShadow(.md)`.

## Components

### `VACard`
Standard card with glass material and shadow. Four styles:
- `.flat` — no shadow, plain secondary surface
- `.elevated` — primary surface with medium shadow
- `.glass` — Liquid Glass material (default)
- `.accent` — gradient background with primary color wash

```swift
VACard(style: .glass) {
    Text("Content goes here")
}
```

### `VAButton`
Primary, secondary, destructive, ghost. Automatic press animation, loading state, haptic-ready.

```swift
VAButton("Log Set", icon: "checkmark.circle.fill", style: .primary) {
    VAHaptics.setLogged()
    await model.logRecommendedSet()
}
```

### `VAMetricDisplay`
Label + value + unit + optional trend indicator. Three sizes: compact, standard, hero.

```swift
VAMetricDisplay(
    label: "Volume Load",
    value: "12,450",
    unit: "lb",
    trend: .up,
    style: .hero
)
```

### `VAProgressRing`
Animated ring with configurable line width and color. Used for rest timer, readiness, workout completion.

### `VASectionHeader`
Title + optional subtitle + optional action button.

### `VAEmptyState`, `VALoadingState`, `VAErrorState`
Standard layouts for the three non-content states.

### `VACoachBubble`
Chat bubble with user/coach sender, typing indicator, coach avatar.

## Haptics — `VAHaptics`

Every action that deserves tactile confirmation should call through here:

```swift
VAHaptics.sessionStart()    // Workout starts
VAHaptics.setLogged()       // Set completed
VAHaptics.restComplete()    // Rest timer expired
VAHaptics.decisionMade()    // User picks Up/Hold/Down
VAHaptics.workoutComplete() // Session finished
VAHaptics.coachResponse()   // AI coach replied
VAHaptics.error()           // Something failed
VAHaptics.tap()             // Button press
VAHaptics.selection()       // Tab switch, picker change
```

watchOS and iOS have separate implementations with appropriate patterns per platform.

## Motion — `VAAnimation`

```swift
VAAnimation.quick     // 0.25s — button presses
VAAnimation.standard  // 0.35s — default (most transitions)
VAAnimation.slow      // 0.55s — hero transitions
VAAnimation.bouncy    // 0.4s with low damping — celebrations
VAAnimation.linear    // 0.3s — continuous updates
```

Apply with the `.vaAnimation()` helper or directly. `vaAppear()` gives any view a scale+fade entrance that respects Reduced Motion.

## Adding a new component

1. Put it in `VolumeArcNative/Sources/VolumeArcUI/DesignSystem/Components.swift`
2. Use only `VA.*` tokens — no hardcoded values
3. Support both light and dark mode via dynamic colors
4. Support Dynamic Type by using `VA.Typography` fonts
5. Respect `@Environment(\.accessibilityReduceMotion)` for animations
6. Add VoiceOver labels/hints on interactive elements
7. Document it in this file
