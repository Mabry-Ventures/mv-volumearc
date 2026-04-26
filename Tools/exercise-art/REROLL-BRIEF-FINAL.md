# Re-roll brief — 8 required fixes from final world-class review

The strict review pass (`Tools/exercise-art/validation-report-final.md`)
flagged 25 illustrations under world-class scoring. 17 are sibling
collisions inherent to single-frame static drawings (paused vs
non-paused, walking vs forward lunge, etc.) and we're accepting those.
The remaining **8 are required re-rolls** — genuine equipment errors,
anatomical glitches, or framing failures that introduced new sibling
collisions.

## Style continuity is non-negotiable

These re-rolls must match the existing 125 acceptable illustrations on
every non-pose axis. Reference
`App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png`
as the character/style anchor every single time:

- Same coach figure (short hair, athletic shorts, tank top, neutral
  build, no facial detail)
- Same monochrome line on off-white background
- Same line weight, same level of equipment detail
- 1024×1024 square

If the new generation regresses character or aesthetic, it's a worse
outcome than the current illustration. Don't ship it.

## Per-ID framing fix

Replace each existing PNG at
`App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/<id>.png`.

| ID | Current failure | Required re-roll |
|---|---|---|
| `decline-bench-press` | Figure tangle — overlapping limbs read as 2 figures | Clean side-profile view of a single figure on a DECLINE bench (head-end lower than foot-end, bench angled ~15-20° below horizontal). Bar at chest contact, both arms cleanly visible — no overlapping limbs. |
| `slider-ham-curl` | Sliders not visible; reads as a glute bridge | SUPINE figure (on back) with both heels resting on visible furniture-glide SLIDERS or small towels on a smooth floor. Hips elevated, knees bent and pulling heels TOWARD the body — mid-curl, with hamstrings activated. The sliders MUST be drawn beneath the heels. |
| `suitcase-carry` | Two dumbbells — defeats the unilateral load | ONE heavy dumbbell in ONE hand at the side (right side preferred). Other hand empty, hanging naturally. Figure walking forward, side profile. Posture shows the offset-load anti-lateral-flexion bracing — slight contralateral lean but core tight. Catalog `unilateral = true`. |
| `barbell-curl` | Empty bar — no plates | Standard barbell with VISIBLE PLATES on each end (~3-4 schematic plates per side, sized to look ~25-45 lbs each). Mid-curl position, elbows at sides. The plates and collars must be unambiguously present. |
| `chin-up` | Back view, supinated grip invisible — looks like pull-up | FRONT-QUARTER (~3/4) view showing the figure's torso and face direction toward the camera. Hands gripping the overhead bar with palms facing the figure (SUPINATED grip). The grip orientation MUST be visible — that's the entire defining feature of a chin-up vs pull-up. |
| `close-grip-bench` | Grip width not visibly narrower than bench-press | Side or 3/4 view of figure on a flat bench. Hands gripping the bar CLEARLY INSIDE shoulder width — distance between hands should be obviously narrower than the figure's shoulders. Elbows tucked tight to ribs (not flared). The narrow-grip position is the defining feature. |
| `kettlebell-swing` | Kettlebell hanging static — reads as deadlift | DYNAMIC mid-swing pose: kettlebell held in both hands at the END OF AN ARC, swung up to chest or eye height with arms straight. Figure is hip-hinged with knees slightly flexed, hips driven forward. Suggest motion — the kettlebell is clearly being SWUNG, not held. |
| `low-bar-squat` | Bar reads at trap line — looks like high-bar squat | Side profile. Bar visibly LOW on the rear delts (below the scapular spine, on the upper rear-delt shelf — about 2-3 inches lower than the high-bar position). Compared to the back-squat anchor, this figure has a more pronounced FORWARD TORSO LEAN with hips set back farther. The bar's lower position must be visually obvious. |

## Workflow

1. Read this brief.
2. Read `App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png` as anchor.
3. Read `Tools/exercise-art/STYLE.md` for general style.
4. For each of the 8 IDs above, look up the entry in
   `VolumeArcNative/Sources/VolumeArcCore/Workout/ExerciseCatalog+Entries.swift`
   to confirm `primaryEquipment` matches my framing notes.
5. Call `image_generation` with the specific framing requirement plus
   the global style anchor. Save to
   `App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/<id>.png`,
   replacing the existing file. Don't touch the imageset
   `Contents.json`.
6. Generate as many as your per-session limit allows.

## When done

Reply with: which IDs you re-rolled, which (if any) you couldn't finish,
and a one-line per-ID self-assessment — did the new generation hit the
framing requirement vs the old failure mode?
