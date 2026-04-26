# Re-roll brief — 14 illustrations flagged in validation passes

Both Pass B (Codex) and Pass A (Claude) reports identified 14 illustrations
that should be regenerated with stronger per-pose framing. The pattern: pure
"lockout" framings stripped away what makes each specific lift distinct.

## Style continuity is non-negotiable

The re-rolls must match the existing 119 acceptable illustrations on every
non-pose axis:

- Same character as `App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png`
  (short hair, athletic shorts, tank top, neutral build, no facial detail)
- Same monochrome line-on-off-white aesthetic
- Same line weight, same level of equipment detail
- 1024×1024 square

If you accidentally change the character or aesthetic, the re-roll regresses
the catalog. Every new generation should reference `back-squat.png` as the
character/style anchor.

## Per-ID framing fix

Replace each existing PNG at `App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/<id>.png`.

| ID | Specific framing the new generation MUST hit |
|---|---|
| `chin-up` | Figure hanging from a pull-up bar that is OVERHEAD (above figure's hands), supinated grip (palms toward face), chin clearly above the bar at the top of the rep. The bar is rendered with a visible support structure, not floating. |
| `pull-up` | Figure hanging from an overhead pull-up bar, pronated grip (palms forward), chin above bar. Same supported-bar treatment as `chin-up`. |
| `wide-grip-pull-up` | Same as `pull-up` but hands clearly wider than shoulder width. |
| `arnold-press` | MID-press position with palms visibly rotating from supinated (palms toward face) at chest start to pronated (palms forward) overhead. Show the rotation in progress, not the static lockout. Dumbbells in both hands. |
| `bulgarian-split-squat` | DUMBBELLS in both hands at sides (catalog primaryEquipment is `.dumbbell`). Rear foot elevated on bench, front leg in deep flexion. Same 3/4 view as before. |
| `jefferson-curl` | BARBELL or dumbbells in hands (whatever the catalog says — read the entry). Figure on a slight elevated platform, deep spinal flexion / segmental rounding pulling the load through the legs. |
| `block-pulls` | Bar still resting on raised blocks/plates, figure mid-pull (knees still flexed, hips not yet at lockout). Don't show the standing-tall lockout — show that we're pulling FROM the elevated start position. |
| `incline-db-curl` | Figure on an incline bench, dumbbells in hands at the bottom of the rep with arms FULLY EXTENDED behind the body line — the deep stretched bottom position, NOT the top contraction. This is the entire point of incline curls. |
| `push-press` | Dip phase: knees visibly flexed in a quarter-squat position, bar still at shoulder rack, about to drive up. Not the lockout. |
| `close-grip-bench` | Hands clearly INSIDE shoulder width on the bar, elbows tucked to ribs. Make the narrow grip visually obvious — that's the only thing distinguishing it from regular bench press. |
| `ghd-back-extension` | Glute-ham developer apparatus: a horizontal bench with FOOT ROLLERS at one end and THIGH PADS the figure rests against. Body position is parallel to the floor or slightly above. Different from a 45° back extension which has an angled pad. |
| `belt-squat` | Belt squat machine: figure standing on a raised platform with a thick LIFTING BELT around hips that connects via CHAIN/STRAP to a weight stack or plates hanging below. Show the belt + chain clearly. |
| `low-bar-squat` | Bar resting on the REAR DELTS (low on the upper back, below the scapular spine). More forward torso lean than `back-squat` (which shows the bar high on the traps). Visually emphasize the lower bar position and the more pronounced hip-back angle. |
| `burpee` | Mid-explosive-stand-up: figure transitioning from the floor to standing, OR at the top with arms extended overhead post-jump. NOT the static push-up bottom. Convey movement / kinetic energy. |

## Workflow

1. Read this brief.
2. Read `App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png` as your character/style anchor.
3. Read `Tools/exercise-art/STYLE.md` for general style rules.
4. For each of the 14 IDs above:
   - Look up the entry in `VolumeArcNative/Sources/VolumeArcCore/Workout/ExerciseCatalog+Entries.swift` to confirm `primaryEquipment` and `name` match my framing notes.
   - Call `image_generation` with the specific framing requirement above PLUS the global style anchor.
   - Save to `App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/<id>.png` — REPLACING the existing file.
   - Don't touch any other file in the imageset (the `Contents.json` is already correct).
5. Generate as many as your per-session limit allows. Exit cleanly when limit hits.

## When done

Reply with: which IDs you re-rolled this session, which (if any) you couldn't
finish, and a one-line per-ID self-assessment: did the new generation hit
the framing requirement vs the original failure mode?
