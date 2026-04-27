# Re-roll brief — 12 sibling-collision fixes (Tier B)

Final-review pass flagged 17 illustrations as scoring 3 due to **sibling
collision** — they're indistinguishable from a related lift in static
frame. 3 of those are pure tempo/pause variants and will share their
parent's illustration in code (Tier A, no re-roll needed). The remaining
2 (`machine-hack-squat`, `deadlift`) are passive — they'll be spot-
checked after this round.

These **12 are required re-rolls** with stricter pose differentiation.
The previous gen captured a recognizable version of each lift, but
didn't push hard enough on the *defining* characteristic that
distinguishes it from its sibling.

## Style continuity is non-negotiable

Match the existing 121 acceptable illustrations on every non-pose axis.
Reference
`App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png`
as the character/style anchor for every generation:

- Same coach figure (short hair, athletic shorts, tank top, neutral
  build, no facial detail)
- Same monochrome line on off-white background
- Same line weight, same level of equipment detail
- 1024×1024 square

If the new generation regresses character or aesthetic, it's a worse
outcome than the current illustration. Don't ship it.

## Per-ID framing fix — push hard on the differentiating feature

Replace each existing PNG at
`App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/<id>.png`.

The "sibling" column tells you which lift the previous gen was
indistinguishable from — your job is to make this re-roll *visually
unambiguous* against that sibling.

| ID | Sibling collision | Required re-roll framing |
|---|---|---|
| `arnold-press` | overhead-press / db-press | MID-press position with palms VISIBLY rotating from supinated (palms toward face) to pronated (palms forward). Capture the rotation in progress at the midpoint — DBs at forehead height, palms at ~45° turn. NOT the lockout. The half-rotation is the entire defining feature of an Arnold press. |
| `push-press` | overhead-press | DIP phase: knees clearly flexed in a quarter-squat (~30-45° knee bend), bar still at front-rack at shoulders, torso upright. Figure is about to drive up but has not yet started the press. The dip-and-drive setup is the defining feature vs strict overhead press. |
| `burpee` | push-up | EXPLOSIVE STAND-UP / JUMP phase: figure mid-air with arms extended overhead, both feet clearly off the ground, body fully extended. NOT the floor / push-up bottom. Convey upward motion with body alignment (vertical figure, hands above head). |
| `curtsy-lunge` | lateral-lunge / forward-lunge | Front 3/4 view. Rear leg crosses DIAGONALLY BEHIND the standing leg (the curtsy-bow shape). Standing leg vertical, rear leg's knee dropping toward the floor on the opposite side. The diagonal cross is the defining feature — NO straight-back trail leg. |
| `reverse-lunge` | forward-lunge | Side profile. Trail leg is clearly BEHIND the body line — the rear knee is dropping toward the floor at the back of the figure. Front leg is the planted standing leg with weight on it. Different from forward-lunge which has the front leg extending out ahead of the torso. |
| `walking-lunge` | forward-lunge | Side profile, MID-STRIDE: figure is captured during a step, with one foot just landing in lunge stance and arms in asymmetric swing (one forward, one back). Suggest forward locomotion — the figure is moving through the lunge, not statically holding it. |
| `pendlay-row` | barbell-row | Side profile. Bar is RESTING ON THE FLOOR between reps (the pause-on-floor is the entire defining feature of Pendlay row). Torso is parallel to the floor — back angle near horizontal. Hands on bar with grip on the floor. NOT a standing or upright row. |
| `yates-row` | barbell-row | Side profile. UNDERHAND (supinated) grip — palms facing up/forward. Back angle is more upright, around 30-45° from vertical (NOT parallel to floor like Pendlay, NOT 45° pronated like barbell-row). Bar pulled to lower abdomen. The supinated grip + upright torso is the defining feature. |
| `reverse-curl` | barbell-curl | Front 3/4 view. Bar held with PRONATED (overhand) grip — palms facing DOWN throughout. Mid-curl position with elbows at sides. Make the palms-down hand orientation visually unambiguous — that's the entire defining feature vs a regular barbell curl (palms-up). |
| `dive-push-up` | push-up | Side profile. Hips PIKED HIGH, head ducking under as the body arcs through. Body forms a clear inverted-V → forward-arc shape, like the figure is "diving" forward through an arch. NOT a flat plank push-up — the piked-hip arc is the defining feature. |
| `hanging-leg-raise` | pull-up | Side profile. Figure hanging from overhead bar with ARMS STRAIGHT (not bent like in a pull-up), legs lifted to 90° HORIZONTAL — toes pointing forward, hips at a right angle. The straight arms + raised legs is the defining feature vs a pull-up which has bent arms + chin-over-bar. |
| `russian-twist` | decline-sit-up | Front 3/4 view. Figure seated with knees bent, torso reclined ~45°, hands holding a small weight (plate or DB) clearly off-center to ONE SIDE — the rotation/twist is captured. Different from decline-sit-up which has the torso moving up/down on a straight axis. The off-center weight + twisted torso is the defining feature. |

## Workflow

1. Read this brief.
2. Read `App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png` as anchor.
3. Read `Tools/exercise-art/STYLE.md` for general style.
4. For each of the 12 IDs above, look up the entry in
   `VolumeArcNative/Sources/VolumeArcCore/Workout/ExerciseCatalog+Entries.swift`
   to confirm `primaryEquipment` matches my framing notes.
5. Call `image_generation` with the specific framing requirement plus
   the global style anchor. Save to
   `App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/<id>.png`,
   replacing the existing file. Don't touch the imageset
   `Contents.json`.
6. Generate as many as your per-session limit allows.
7. If you hit the per-session limit, exit cleanly and report which IDs
   completed and which remain. The next session can resume.

## When done

Reply with: which IDs you re-rolled, which (if any) you couldn't finish,
and a one-line per-ID self-assessment — did the new generation push
hard enough on the differentiating feature that it's now visually
unambiguous against the sibling?
