# Claude Design Parity

Last updated: 2026-06-06

Design source: `/Users/jaredmabry/Downloads/VolumeArc.zip`.

The supplied Claude export is authoritative for iOS and watchOS parity. It does not include a marketing-site export, so marketing parity is judged against app tokens, product positioning, and current product voice.

## Source Map

| Claude source | Product surface | Implementation owner | Required proof |
|---|---|---|---|
| `tokens.css` | Shared tokens, light, dark, warm modes | Design system | `VADesignTokenParityTests` verifies Claude warm-personality brand colors against native `VA.Colors` in light/dark, and dashboard snapshots gate the warm brand personality plus glass paths across light/dark/warm-brand. Remaining proof: contrast table and watch/marketing token signoff. |
| `app.jsx`, `ios-frame.jsx` | iOS shell and tab chrome | iOS UI | `DashboardSurfaceSnapshotTests` now gates Today, Workouts idle, Workouts active, Coach planning, Signals, and Profile in light/dark/warm-brand, light `.accessibility5` Dynamic Type, and reduce-transparency-off glass variants across light/dark/warm-brand. Remaining proof: native tab chrome accepted-drift note and watch/marketing parity. |
| `screen-today.jsx` | Today | iOS UI | Light/dark/warm-brand, light `.accessibility5`, and light/dark/warm-brand glass dashboard snapshots exist; remaining proof: additional readiness states. |
| `screen-workouts.jsx` | Workouts and active session | iOS UI/watchOS | Idle and active snapshots exist across light/dark/warm-brand, light `.accessibility5`, and light/dark/warm-brand glass; remaining proof: rest/edit/complete/interruption/resume snapshots and UAT. |
| `screen-coach.jsx` | Coach | AI/UI/copy | Co-design planning snapshots exist across light/dark/warm-brand, light `.accessibility5`, and light/dark/warm-brand glass, and coach bubble component snapshots cover transcript states; remaining proof: fallback/safety/empty/error screen states and copy review. |
| `screen-signals.jsx` | Signals | iOS UI | Seeded Signals snapshots exist across light/dark/warm-brand, light `.accessibility5`, and light/dark/warm-brand glass; remaining proof: recovery detail, no-permission, empty, and trend-interpretation states. |
| `screen-profile.jsx` | Profile/settings/paywall/watch faces | iOS UI/marketing/legal | Seeded Profile snapshots exist across light/dark/warm-brand, light `.accessibility5`, and light/dark/warm-brand glass; paywall snapshots also exist. Remaining proof: settings, legal/pricing, and watch-face installability states. |
| `screen-codesign.jsx` | Co-design/planning | Product/iOS/AI | Schedule persistence, edited exercise prescription persistence, and row swap/move/remove proof are implemented and tested from Today into Workouts. Remaining proof: template decision, dedicated-screen parity decision, start, and Watch sync. |
| `VolumeArc Watch Faces*.html`, `watchface-styles.css` | Watch faces and watch-face previews | watchOS/design | Preview parity plus launch decision on bundled `.watchface` files. |

## Required Modes

| Mode | Required surfaces |
|---|---|
| Light | iOS app surface snapshots now cover the six launch-critical dashboard surfaces. WatchOS, widgets, and marketing pages still require final signoff. |
| Dark | iOS app surface snapshots now cover the six launch-critical dashboard surfaces. WatchOS, widgets, and marketing pages still require final signoff. |
| Warm | Covered for iOS dashboard surfaces as the production brand personality: Claude's `personality: "warm"` token values match native `VA.Colors`, and `testClaudeParityWarmBrandSurfaceSnapshots` compares the six launch-critical dashboard surfaces. Warm is not a separate user-selectable theme for v1; teal, mono, and density controls from the prototype are treated as non-productized design tools unless Jared reopens that scope. |
| Accessibility | Covered for iOS dashboard surfaces with a light-mode `.accessibility5` Dynamic Type snapshot pass. Physical-device review still needs to confirm the highest-risk screen/body combinations. |
| Glass / transparency | Covered for iOS dashboard surfaces with reduce-transparency-off snapshot passes across light, dark, and warm-brand. |

## Accepted Drift Policy

Any intentional deviation from Claude Design must record:

1. Source file.
2. Product surface.
3. Difference.
4. Reason.
5. Owner.
6. Test or screenshot proof.
7. Whether the drift is permanent or temporary.

No unrecorded drift can pass release signoff.

## Open Drift Decisions

| Source | Surface | Difference | Reason | Owner | Required proof | Status |
|---|---|---|---|---|---|---|
| `app.jsx`, `ios-frame.jsx` | iOS app shell | Claude renders a floating Liquid Glass tab pill; native iOS currently uses SwiftUI `TabView` with platform tab-bar accessibility and `VA.Colors.primary` tint. | The native tab bar preserves stable `UITabBar` semantics used by existing XCUITests and platform assistive technology. Replacing it with a custom overlay would be a product-navigation change, not a cosmetic swap. | Design systems / iOS UI | Jared/design signoff on native tab bar as intentional platform drift, or an implementation ticket for a custom floating pill plus updated accessibility/UI tests. | Open |
| `tokens.css` | Color personality | Claude exposes prototype controls for `warm`, `teal`, and `mono`; v1 product ships warm as the only brand personality. | The release plan requires light, dark, and warm alignment, not a user-facing theme/personality picker. Alternate personalities would add product scope and copy/support complexity. | Product / design systems | `VADesignTokenParityTests` and light/dark/warm-brand dashboard snapshots stay green; Jared accepts alternate personalities as non-v1. | Proposed accepted drift |
| `tweaks-panel.jsx`, `tokens.css` | Density | Claude exposes `dense`, `balanced`, and `spacious` prototype controls; v1 product ships the tuned app density only. | Density was a design-exploration control, not a surfaced product preference. Dynamic Type remains the accessibility path for text scale. | Product / iOS UI | The `.accessibility5` dashboard matrix and reduce-transparency-off dashboard matrix pass; Jared accepts density controls as non-v1. | Proposed accepted drift |
