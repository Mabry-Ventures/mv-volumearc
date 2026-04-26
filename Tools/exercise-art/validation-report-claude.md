# Exercise illustration validation — Pass A (Claude)

## Summary

- **Total reviewed:** 133 imagesets
- **Lowest-score distribution (min of style/character/pose per row):**
  - `min == 1`: 2 illustrations (fundamentally broken)
  - `min == 3`: 12 illustrations (visibly imperfect; reroll candidate)
  - `min == 4`: 118 illustrations (clean, recognizable, minor stylistic drift)
  - `min == 5`: 1 illustration (the anchor)
- **Recommended re-roll list (any row whose `min(scores) <= 3`):** 14 illustrations

  Severe (`min == 1`):
  - `chin-up`
  - `pull-up`

  Moderate (`min == 3`):
  - `arnold-press`
  - `belt-squat`
  - `block-pulls`
  - `bulgarian-split-squat`
  - `burpee`
  - `close-grip-bench`
  - `ghd-back-extension`
  - `incline-db-curl`
  - `jefferson-curl`
  - `low-bar-squat`
  - `push-press`
  - `wide-grip-pull-up`

## Scoring notes

- Anchor: `back-squat.png` — short tousled hair, athletic tank + shorts,
  side profile, ~2px line weight, monochrome on warm cream
  (`#F4F2EE`-ish) background. Pinned as the character reference for
  every other illustration.
- The character was remarkably consistent across the catalog —
  short hair, tank top, athletic shorts, sneakers, slim-athletic build
  appeared in essentially every figure. I did not find a single image
  that was meaningfully off-character (no hair changes, no clothing
  changes, no build changes), so `character_score` is 4 across the
  board for non-anchor entries (5 reserved for the anchor itself).
- Style was likewise uniform — all imagesets used the same line
  weight, the same warm cream background, no shading drift, no
  comic effects, no backgrounds beyond the figure + equipment.
  `style_score` is 4 across the board, except where pose problems
  also pulled style down (the two pull-up / chin-up images had a
  loose, sketchy figure rendering that compounded the broken pose).
- Most lost points came from `pose_score` — either equipment that
  the catalog says should be present is missing or hard to read, the
  pose framing chose a position that doesn't differentiate the lift
  from a more generic relative (e.g., paused/close-grip/push-press
  rendered identically to their non-paused/wide-grip/strict-press
  counterpart), or — for the two worst cases — the figure isn't
  actually performing the named movement at all.

## Per-exercise table

Sorted ascending by `min(scores)` so the worst illustrations are at the top.

| id | style | character | pose | concern | reroll? |
|---|---|---|---|---|---|
| chin-up | 3 | 4 | 1 | Figure standing with bar across shoulders, not hanging; not recognizable as a chin-up | yes |
| pull-up | 3 | 4 | 1 | Bar appears to rest behind head at trap level, not above with figure hanging; not recognizable as a pull-up | yes |
| arnold-press | 4 | 4 | 3 | Static overhead lockout — does not show the palms-rotation midpoint that defines Arnold press | yes |
| belt-squat | 4 | 4 | 3 | Belt/chain attachment to load is faint — machine reads as generic squat platform | yes |
| block-pulls | 4 | 4 | 3 | Shows lockout standing tall, not the active pull from blocks; ambiguous as a hinge variant | yes |
| bulgarian-split-squat | 4 | 4 | 3 | No dumbbells in hands; catalog primary equipment is dumbbell, BSS shown bodyweight | yes |
| burpee | 4 | 4 | 3 | Static push-up bottom only; ambiguous vs push-up since burpee is multi-phase | yes |
| close-grip-bench | 4 | 4 | 3 | Indistinct from regular bench press; close grip not visually emphasized | yes |
| ghd-back-extension | 4 | 4 | 3 | Looks like horizontal back-extension bench rather than GHD; ambiguous vs back-extension-45 | yes |
| incline-db-curl | 4 | 4 | 3 | Pose at top contraction, not the stretched bottom that defines incline curl | yes |
| jefferson-curl | 4 | 4 | 3 | No dumbbell shown; loaded spinal flexion not communicated, reads as passive forward fold | yes |
| low-bar-squat | 4 | 4 | 3 | Bar position not visibly distinct from high-bar squat | yes |
| push-press | 4 | 4 | 3 | Static lockout indistinguishable from overhead press; dip-and-drive not communicated | yes |
| wide-grip-pull-up | 4 | 4 | 3 | Bar position ambiguous; figure appears partially suspended but framing reads more like holding bar than hanging from it | yes |
| ab-wheel-rollout | 4 | 4 | 4 | none | no |
| assisted-pull-up | 4 | 4 | 4 | none | no |
| b-stance-hip-thrust | 4 | 4 | 4 | none | no |
| back-extension-45 | 4 | 4 | 4 | none | no |
| barbell-curl | 4 | 4 | 4 | none | no |
| barbell-hip-thrust | 4 | 4 | 4 | none | no |
| barbell-row | 4 | 4 | 4 | none | no |
| bench-press | 4 | 4 | 4 | none | no |
| box-squat | 4 | 4 | 4 | none | no |
| cable-crunch | 4 | 4 | 4 | none | no |
| cable-curl | 4 | 4 | 4 | none | no |
| cable-fly | 4 | 4 | 4 | none | no |
| cable-glute-kickback | 4 | 4 | 4 | none | no |
| cable-lateral-raise | 4 | 4 | 4 | none | no |
| cable-pullover | 4 | 4 | 4 | none | no |
| cable-rear-delt-fly | 4 | 4 | 4 | none | no |
| cable-row | 4 | 4 | 4 | none | no |
| chest-supported-row | 4 | 4 | 4 | none | no |
| curtsy-lunge | 4 | 4 | 4 | none | no |
| db-bench-press | 4 | 4 | 4 | none | no |
| db-lateral-raise | 4 | 4 | 4 | none | no |
| db-rdl | 4 | 4 | 4 | none | no |
| db-rear-delt-fly | 4 | 4 | 4 | none | no |
| deadlift | 4 | 4 | 4 | none | no |
| decline-bench-press | 4 | 4 | 4 | none | no |
| decline-sit-up | 4 | 4 | 4 | none | no |
| deficit-deadlift | 4 | 4 | 4 | none | no |
| deficit-push-up | 4 | 4 | 4 | none | no |
| dive-push-up | 4 | 4 | 4 | none | no |
| donkey-calf-raise | 4 | 4 | 4 | none | no |
| dumbbell-curl | 4 | 4 | 4 | none | no |
| dumbbell-fly | 4 | 4 | 4 | none | no |
| dumbbell-pullover | 4 | 4 | 4 | none | no |
| face-pull | 4 | 4 | 4 | none | no |
| farmers-walk | 4 | 4 | 4 | none | no |
| forward-lunge | 4 | 4 | 4 | none | no |
| front-raise | 4 | 4 | 4 | none | no |
| front-squat | 4 | 4 | 4 | none | no |
| goblet-squat | 4 | 4 | 4 | none | no |
| good-morning | 4 | 4 | 4 | none | no |
| hack-squat | 4 | 4 | 4 | none | no |
| hammer-curl | 4 | 4 | 4 | none | no |
| hanging-leg-raise | 4 | 4 | 4 | none | no |
| high-bar-squat | 4 | 4 | 4 | none | no |
| incline-bench-press | 4 | 4 | 4 | none | no |
| incline-db-fly | 4 | 4 | 4 | none | no |
| incline-db-press | 4 | 4 | 4 | none | no |
| inverted-row | 4 | 4 | 4 | none | no |
| jump-rope | 4 | 4 | 4 | none | no |
| kettlebell-swing | 4 | 4 | 4 | none | no |
| kneeling-cable-pulldown | 4 | 4 | 4 | none | no |
| landmine-press | 4 | 4 | 4 | none | no |
| lat-pulldown | 4 | 4 | 4 | none | no |
| lateral-lunge | 4 | 4 | 4 | none | no |
| leaning-cable-lateral-raise | 4 | 4 | 4 | none | no |
| leg-press | 4 | 4 | 4 | none | no |
| lying-leg-curl | 4 | 4 | 4 | none | no |
| machine-chest-press | 4 | 4 | 4 | none | no |
| machine-glute-kickback | 4 | 4 | 4 | none | no |
| machine-hack-squat | 4 | 4 | 4 | none | no |
| machine-hip-thrust | 4 | 4 | 4 | none | no |
| machine-lateral-raise | 4 | 4 | 4 | none | no |
| machine-pec-deck | 4 | 4 | 4 | none | no |
| machine-shoulder-press | 4 | 4 | 4 | none | no |
| meadows-row | 4 | 4 | 4 | none | no |
| neutral-grip-pull-up | 4 | 4 | 4 | none | no |
| nordic-ham-curl | 4 | 4 | 4 | none | no |
| overhead-press | 4 | 4 | 4 | none | no |
| overhead-tricep-extension | 4 | 4 | 4 | none | no |
| pallof-press | 4 | 4 | 4 | none | no |
| paused-back-squat | 4 | 4 | 4 | none | no |
| paused-bench-press | 4 | 4 | 4 | none | no |
| paused-deadlift | 4 | 4 | 4 | none | no |
| pendlay-row | 4 | 4 | 4 | none | no |
| pendulum-squat | 4 | 4 | 4 | none | no |
| pin-squat | 4 | 4 | 4 | none | no |
| pjr-pullover | 4 | 4 | 4 | none | no |
| plank | 4 | 4 | 4 | none | no |
| preacher-curl | 4 | 4 | 4 | none | no |
| push-up | 4 | 4 | 4 | none | no |
| reverse-curl | 4 | 4 | 4 | none | no |
| reverse-lunge | 4 | 4 | 4 | none | no |
| reverse-pec-deck | 4 | 4 | 4 | none | no |
| romanian-deadlift | 4 | 4 | 4 | none | no |
| rope-pushdown | 4 | 4 | 4 | none | no |
| russian-twist | 4 | 4 | 4 | none | no |
| seal-row | 4 | 4 | 4 | none | no |
| seated-calf-raise | 4 | 4 | 4 | none | no |
| seated-db-press | 4 | 4 | 4 | none | no |
| seated-leg-curl | 4 | 4 | 4 | none | no |
| side-plank | 4 | 4 | 4 | none | no |
| single-arm-db-row | 4 | 4 | 4 | none | no |
| single-arm-lat-pulldown | 4 | 4 | 4 | none | no |
| single-leg-hip-thrust | 4 | 4 | 4 | none | no |
| single-leg-rdl | 4 | 4 | 4 | none | no |
| sissy-squat | 4 | 4 | 4 | none | no |
| skullcrusher | 4 | 4 | 4 | none | no |
| slider-ham-curl | 4 | 4 | 4 | none | no |
| smith-bench-press | 4 | 4 | 4 | none | no |
| smith-squat | 4 | 4 | 4 | none | no |
| standing-calf-raise | 4 | 4 | 4 | none | no |
| standing-db-press | 4 | 4 | 4 | none | no |
| step-up | 4 | 4 | 4 | none | no |
| stiff-leg-deadlift | 4 | 4 | 4 | none | no |
| straight-arm-pulldown | 4 | 4 | 4 | none | no |
| suitcase-carry | 4 | 4 | 4 | none | no |
| sumo-deadlift | 4 | 4 | 4 | none | no |
| t-bar-row | 4 | 4 | 4 | none | no |
| tibialis-raise | 4 | 4 | 4 | none | no |
| trap-bar-deadlift | 4 | 4 | 4 | none | no |
| tricep-pushdown | 4 | 4 | 4 | none | no |
| upright-row | 4 | 4 | 4 | none | no |
| walking-lunge | 4 | 4 | 4 | none | no |
| wood-chop | 4 | 4 | 4 | none | no |
| wrist-curl | 4 | 4 | 4 | none | no |
| yates-row | 4 | 4 | 4 | none | no |
| z-press | 4 | 4 | 4 | none | no |
| zercher-squat | 4 | 4 | 4 | none | no |
| back-squat | 5 | 5 | 5 | none (anchor reference) | no |
