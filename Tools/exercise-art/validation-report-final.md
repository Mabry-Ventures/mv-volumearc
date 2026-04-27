# Final review — VOL-105 illustration catalog

Strict, world-class QA pass against the brief in
`Tools/exercise-art/FINAL-REVIEW-BRIEF.md`. Anchor: `back-squat.png`
(short-haired androgynous figure in tank top + athletic shorts +
sneakers, off-white background, single ~2px line weight, schematic
plates with hub detail, depth-of-squat pose visible).

Calibration sample (viewed before scoring): back-squat (anchor),
deadlift, bench-press, leg-press, pull-up, cable-fly,
bulgarian-split-squat, burpee, skullcrusher. Establishes the bar:

- A clean, on-style, anatomically-correct illustration with the right
  equipment is a **4**.
- A **5** has all of the above PLUS communicates the distinguishing
  characteristic of the lift — bar position on low-bar vs high-bar,
  pause depth, lockout overload — well enough that a coach would not
  ask for a second illustration. Should be rare.
- A **3** has a real flaw (anatomical glitch, missing or weak
  equipment, under-differentiated from a sibling lift, character drift).
- A **2** is broken on a meaningful axis.

## Summary

- **Total reviewed:** 133
- **Score distribution (min(style, character, pose) per row):**
  - 5: 1 (the anchor)
  - 4: 107
  - 3: 22
  - 2: 3
  - 1: 0
- **World-class verdict:** 108 / 133 ship-ready as-is at the 4-or-better
  bar (~81%).
- **Recommended re-roll list (min(scores) <= 3):** 25 IDs total. Of
  those, **8 are required re-rolls** (genuine anatomy/equipment errors
  or strong sibling-collision); the other **17 are optional** —
  variant-vs-variant differentiation that a static frame cannot
  realistically distinguish (e.g., paused- vs non-paused, walking- vs
  forward-lunge). A pragmatic launch could ship with the 8 required
  fixes and accept the 17 optional collisions as inherent limits of
  the medium.

### Required re-rolls (8)

`decline-bench-press`, `slider-ham-curl`, `suitcase-carry`,
`barbell-curl`, `chin-up`, `close-grip-bench`, `kettlebell-swing`,
`low-bar-squat`.

(`reverse-curl` and `pendlay-row` and `yates-row` are borderline — see
the table notes. If we want a full strict cleanup, push N to 11.)

### Optional re-rolls (17)

`arnold-press`, `burpee`, `curtsy-lunge`, `deadlift`, `dive-push-up`,
`hanging-leg-raise`, `machine-hack-squat`, `paused-back-squat`,
`paused-bench-press`, `paused-deadlift`, `pendlay-row`, `push-press`,
`reverse-curl`, `reverse-lunge`, `russian-twist`, `walking-lunge`,
`yates-row`.

## Re-roll table (worst first, then sibling collisions)

| id | style | character | pose | concern | reroll? |
|---|---:|---:|---:|---|---|
| decline-bench-press | 4 | 3 | 2 | Body looks tangled — additional limbs / overlapping arms reading like a second figure or anatomical glitch. Required. | yes |
| slider-ham-curl | 4 | 4 | 2 | Sliders not visible; pose reads as a glute bridge hold. Equipment fail. Required. | yes |
| suitcase-carry | 4 | 4 | 2 | Two dumbbells visible — defeats the unilateral suitcase load. Required. | yes |
| barbell-curl | 4 | 4 | 3 | Bar held mid-curl but plates/collars are absent — empty bar. Required. | yes |
| chin-up | 4 | 4 | 3 | Indistinguishable from `pull-up` (back view, no grip visible). Required. | yes |
| close-grip-bench | 4 | 4 | 3 | Grip width does not visibly differ from `bench-press`. Required. | yes |
| kettlebell-swing | 4 | 4 | 3 | Reads as a kettlebell deadlift / dumbbell standing-hold; no swing motion. Required. | yes |
| low-bar-squat | 4 | 4 | 3 | Bar reads at trap line, not rear-delt shelf. Indistinguishable from `high-bar-squat`. Required. | yes |
| arnold-press | 4 | 4 | 3 | Mid-rotation pose ambiguous; no clear palms-rotating signal. | optional |
| burpee | 4 | 4 | 3 | Single-frame burpee unavoidable; reads as a star-jump. | optional |
| curtsy-lunge | 4 | 4 | 3 | Cross-behind step is too subtle from this 3/4 angle. | optional |
| deadlift | 4 | 4 | 3 | Lockout looks underloaded / static — bar tipped. | optional |
| dive-push-up | 4 | 4 | 3 | Reads as a basic up-dog / mid push-up. | optional |
| hanging-leg-raise | 4 | 4 | 3 | Knees-only at hip flexion — should be at-or-above parallel. | optional |
| machine-hack-squat | 4 | 4 | 3 | Visually overlaps with `hack-squat`. | optional |
| paused-back-squat | 4 | 4 | 3 | Indistinguishable from `back-squat` anchor. | optional |
| paused-bench-press | 4 | 4 | 3 | Indistinguishable from `bench-press`. | optional |
| paused-deadlift | 4 | 4 | 3 | Reads as generic deadlift mid-pull. | optional |
| pendlay-row | 4 | 4 | 3 | Bar in mid-air, not floor-reset (the Pendlay defining trait). | optional |
| push-press | 4 | 4 | 3 | Catches the dip pose; reads as front-rack squat. | optional |
| reverse-curl | 4 | 4 | 3 | Bar shows minimal/no plates; pronated grip barely readable. | optional |
| reverse-lunge | 4 | 4 | 3 | Reads as a generic split-stance lunge. | optional |
| russian-twist | 4 | 4 | 3 | No twist, no load — passive seated lean-back. | optional |
| walking-lunge | 4 | 4 | 3 | Identical to `forward-lunge`; no walking context. | optional |
| yates-row | 4 | 4 | 3 | Underhand grip + ~45° torso (Yates differentiator) doesn't read. | optional |

## Full catalog table

| id | style | character | pose | concern | reroll? |
|---|---:|---:|---:|---|---|
| back-squat | 5 | 5 | 5 | Anchor. Crisp depth, plates with hub detail, gripping bar correctly. | no |
| front-squat | 4 | 4 | 4 | Front-rack reads OK; torso could be slightly more vertical to differentiate further from back-squat, but elbows are up. | no |
| goblet-squat | 4 | 4 | 4 | Dumbbell at chest, depth clean. | no |
| low-bar-squat | 4 | 4 | 3 | Bar position reads more like high-bar/trap line than "rear delt shelf" — does not visually differentiate from `high-bar-squat`. | yes |
| high-bar-squat | 4 | 4 | 4 | Bar high on traps, knees forward, vertical-ish torso. | no |
| zercher-squat | 4 | 4 | 4 | Bar threaded through elbow crooks, depth visible. Reads cleanly. | no |
| box-squat | 4 | 4 | 4 | Figure seated on box, bar racked — distinctive. | no |
| paused-back-squat | 4 | 4 | 3 | Indistinguishable from `back-squat` anchor; nothing in the frame communicates "pause". Probably an unavoidable static-image limitation. | optional |
| pin-squat | 4 | 4 | 4 | Pins clearly visible inside the rack — strong differentiation. | no |
| smith-squat | 4 | 4 | 4 | Smith rails clearly drawn, figure squatting in track. | no |
| pendulum-squat | 4 | 4 | 4 | Pendulum machine geometry visible with stack. | no |
| belt-squat | 4 | 4 | 4 | Belt-loaded machine with hanging plate visible — distinctive. | no |
| hack-squat | 4 | 4 | 4 | Sled-style hack squat machine with plate. | no |
| machine-hack-squat | 4 | 4 | 3 | Visually overlaps heavily with `hack-squat`; the catalog distinction (plate-loaded vs sled) does not read in the illustration. | optional |
| leg-press | 4 | 4 | 4 | Sled, plate, feet on platform — strong machine geometry. | no |
| sissy-squat | 4 | 4 | 4 | Knee-forward lean, support post present. Slightly small support but reads. | no |
| bulgarian-split-squat | 4 | 4 | 4 | Rear foot on bench, front knee in lunge, dumbbells at sides. | no |
| step-up | 4 | 4 | 4 | Dumbbells at sides, stepping onto box. Mid-step but reads. | no |
| deadlift | 4 | 4 | 3 | Lockout pose, but bar is held mid-thigh / oddly tipped — reads more like a "standing with bar" than a deadlift mid-rep or true lockout. Underweighted feel. | optional |
| romanian-deadlift | 4 | 4 | 4 | Hinge with bar at mid-shin, knees soft, back flat. Clean. | no |
| sumo-deadlift | 4 | 4 | 4 | Wide stance, knees flared, arms inside legs — sumo reads. | no |
| trap-bar-deadlift | 4 | 4 | 4 | Hex/trap bar around the figure, handles at sides. Standing tall — could be at start, but the bar geometry is unmistakable. | no |
| deficit-deadlift | 4 | 4 | 4 | Figure stands on raised platform with bar below — deficit clearly communicated. | no |
| block-pulls | 4 | 4 | 4 | Plates resting on stacked blocks — bar above-knee position visible. | no |
| paused-deadlift | 4 | 4 | 3 | Reads as a generic mid-pull deadlift; nothing in the static frame communicates the pause. | optional |
| stiff-leg-deadlift | 4 | 4 | 4 | Knees nearly straight, deep hip hinge. Differentiates from RDL with stiffer-knee read. | no |
| single-leg-rdl | 4 | 4 | 4 | One leg back parallel to floor, dumbbells reaching down. SLRDL clearly. | no |
| db-rdl | 4 | 4 | 4 | Hinge with two dumbbells brushing thigh line. | no |
| kettlebell-swing | 4 | 4 | 3 | Figure stands holding kettlebell at thigh height — reads more like "kettlebell deadlift" than a swing in motion. No hike or hip-snap pose. | yes |
| back-extension-45 | 4 | 4 | 4 | 45° hyper bench, figure prone with arms crossed at chest. Strong machine read. | no |
| ghd-back-extension | 4 | 4 | 4 | GHD apparatus with hip pad and ankle rollers, prone position. | no |
| good-morning | 4 | 4 | 4 | Bar on traps, deep hip hinge. Reads cleanly. | no |
| barbell-hip-thrust | 4 | 4 | 4 | Upper back on bench, bar across hips, knees bent — textbook hip thrust at lockout. | no |
| single-leg-hip-thrust | 4 | 4 | 4 | One leg extended, one foot planted, hips locked out. | no |
| b-stance-hip-thrust | 4 | 4 | 4 | Working foot flat, supporting heel only — B-stance reads. | no |
| machine-hip-thrust | 4 | 4 | 4 | Machine with seat back, weight stack, foot platform. | no |
| machine-glute-kickback | 4 | 4 | 4 | Cable machine with extended leg, working knee. Distinctive. | no |
| cable-glute-kickback | 4 | 4 | 4 | Standing at cable column, ankle strap, leg back. | no |
| nordic-ham-curl | 4 | 4 | 4 | Knees on pad, ankles secured, torso lowered with arms forward. Strong nordic pose. | no |
| slider-ham-curl | 4 | 4 | 2 | **Sliders are not visible.** Pose looks like a glute bridge / hip thrust hold, not a slider ham curl. Equipment fail per catalog `primaryEquipment`. | yes |
| seated-leg-curl | 4 | 4 | 4 | Seated machine with thigh pad and leg roller, weight stack. | no |
| lying-leg-curl | 4 | 4 | 4 | Prone on machine, ankles in roller pad. | no |
| walking-lunge | 4 | 4 | 3 | Visually identical to `forward-lunge`; carrying dumbbells doesn't communicate "walking" — no second step / movement context. | optional |
| reverse-lunge | 4 | 4 | 3 | Reads as a generic split-stance lunge; back foot on toe is correct but does not differentiate from forward-lunge. | optional |
| forward-lunge | 4 | 4 | 4 | Strong split with front knee stacked, back knee just off floor. Reads cleanly. | no |
| curtsy-lunge | 4 | 4 | 3 | The cross-behind step is subtle — angle from front-quarter view makes it hard to see the curtsy crossover. | optional |
| lateral-lunge | 4 | 4 | 4 | One leg loaded with deep side-bend, other leg straight. Lateral movement reads. | no |
| bench-press | 4 | 4 | 4 | (Calibration) Bar at chest, foot of bench view, hands gripping. | no |
| db-bench-press | 4 | 4 | 4 | Two dumbbells at chest level on flat bench. | no |
| incline-bench-press | 4 | 4 | 4 | Incline bench at ~30°, bar lockout near upper chest. | no |
| incline-db-press | 4 | 4 | 4 | Bench inclined, two dumbbells at shoulder height. | no |
| decline-bench-press | 4 | 3 | 2 | Body looks tangled — additional limbs / overlapping arms reading like a second figure or anatomical glitch. Bench rest angle hard to parse. | yes |
| close-grip-bench | 4 | 4 | 3 | Grip width does not visibly differ from regular `bench-press` — no clear narrow-hands read. Hands appear to overlap on bar. | yes |
| paused-bench-press | 4 | 4 | 3 | Indistinguishable from `bench-press` — no static signal of pause. | optional |
| machine-chest-press | 4 | 4 | 4 | Selectorized machine with handles at chest; weight stack visible. | no |
| smith-bench-press | 4 | 4 | 4 | Smith rack with bar on rails, figure benching inside. | no |
| cable-fly | 4 | 4 | 4 | Two cable columns, figure standing in the middle, arms in fly position. | no |
| machine-pec-deck | 4 | 4 | 4 | Pec-deck handles, seated figure, weight stack visible. | no |
| dumbbell-fly | 4 | 4 | 4 | Bench-side view, both dumbbells stretched wide with soft elbows. | no |
| incline-db-fly | 4 | 4 | 4 | Incline bench, dumbbells out to sides — fly position. | no |
| push-up | 4 | 4 | 4 | Plank, mid push-up. Body straight, hands flat. | no |
| deficit-push-up | 4 | 4 | 4 | Hands on parallettes/risers visible, deeper chest position. | no |
| dive-push-up | 4 | 4 | 3 | Pose reads as a basic up-dog / mid push-up; does not communicate the dive-bomber transition (down-dog → forward dive arc). | optional |
| overhead-press | 4 | 4 | 4 | Front view, bar locked overhead, plates clear. | no |
| seated-db-press | 4 | 4 | 4 | Bench seat, two dumbbells locked overhead. Bench backrest visible. | no |
| standing-db-press | 4 | 4 | 4 | Standing front view, dumbbells locked overhead. Differentiates from seated. | no |
| machine-shoulder-press | 4 | 4 | 4 | Machine seat with handle arms above shoulders, weight stack. | no |
| arnold-press | 4 | 4 | 3 | Mid-rotation pose at shoulder height — could be confused with hammer curl/start of press. The "rotation through the press" is hard to read in a single frame. | optional |
| push-press | 4 | 4 | 3 | Catches the dip pose, but reads more like a front-squat-with-bar than a push-press lockout. The drive phase / overhead lockout doesn't show. | optional |
| z-press | 4 | 4 | 4 | Seated on floor with legs straight, bar locked overhead — distinctive Z-press silhouette. | no |
| landmine-press | 4 | 4 | 4 | Bar pivoting at landmine base, plate at top — figure pressing up and out. Strong machine read. | no |
| db-lateral-raise | 4 | 4 | 4 | Front view, dumbbells out at shoulder height. | no |
| cable-lateral-raise | 4 | 4 | 4 | Single column with stack, cable across body to working arm at shoulder height. | no |
| leaning-cable-lateral-raise | 4 | 4 | 4 | Figure leans away from column, supporting hand on column, working arm raises with cable across body. Differentiates from straight cable raise. | no |
| machine-lateral-raise | 4 | 4 | 4 | Seated machine with elbow pads, arms abducted at shoulder height. | no |
| front-raise | 4 | 4 | 4 | Side view, dumbbells raised in front to eye level. | no |
| upright-row | 4 | 4 | 4 | Bar at chest level with elbows above hands. Clean. | no |
| barbell-row | 4 | 4 | 4 | Bent-over hinge, bar at lower chest, plates visible. | no |
| pendlay-row | 4 | 4 | 3 | Reads as a generic bent-over row; bar is in mid-air, not resetting on the floor each rep. Pendlay = dead-stop on floor. | yes |
| yates-row | 4 | 4 | 3 | Pose nearly identical to `barbell-row`; underhand grip and ~45° torso (Yates differentiator) does not read. | yes |
| t-bar-row | 4 | 4 | 4 | T-bar landmine setup with plates loaded, V-handle. | no |
| meadows-row | 4 | 4 | 4 | Perpendicular to landmine, single-arm grip, plate loaded. | no |
| seal-row | 4 | 4 | 4 | Prone on raised bench, bar hanging below, arms pulling up. Distinctive. | no |
| chest-supported-row | 4 | 4 | 4 | Inclined chest pad, figure pulling handles. Machine read clear. | no |
| single-arm-db-row | 4 | 4 | 4 | One knee on bench, supporting hand, dumbbell at hip. Textbook. | no |
| cable-row | 4 | 4 | 4 | Seated low cable row station with foot platform, V-handle, weight stack. | no |
| inverted-row | 4 | 4 | 4 | Body horizontal under fixed bar, hands gripping. Reads cleanly. | no |
| face-pull | 4 | 4 | 4 | Cable column, rope handle pulled to face with elbows high. | no |
| cable-rear-delt-fly | 4 | 4 | 4 | Two cables crossing in front, arms in rear-delt fly position. | no |
| db-rear-delt-fly | 4 | 4 | 4 | Hinged-over with dumbbells out to sides — bent-over reverse fly. | no |
| reverse-pec-deck | 4 | 4 | 4 | Seated facing pad, arms out to sides on machine handles. | no |
| pull-up | 4 | 4 | 4 | (Calibration) Back view at top of pull, full pull-up rig. | no |
| lat-pulldown | 4 | 4 | 4 | Selectorized lat-pulldown station, bar at upper chest, weight stack. | no |
| chin-up | 4 | 4 | 3 | Visually identical to `pull-up` — supinated/underhand grip is not visible from this back-view, and grip width is identical. Without the grip cue, indistinguishable from a pull-up. | yes |
| neutral-grip-pull-up | 4 | 4 | 4 | Two parallel handles visible, palms facing — neutral grip reads. | no |
| wide-grip-pull-up | 4 | 4 | 4 | Visibly wider hand spacing on bar. Differentiates. | no |
| assisted-pull-up | 4 | 4 | 4 | Assist platform / knee pad with pulley below. Machine reads. | no |
| straight-arm-pulldown | 4 | 4 | 4 | Standing facing column, arms straight pulling bar to thighs. | no |
| kneeling-cable-pulldown | 4 | 4 | 4 | Kneeling at column, bar pulled to chest. | no |
| single-arm-lat-pulldown | 4 | 4 | 4 | Seated at column, single-handle pulldown. Differentiates from two-arm. | no |
| barbell-curl | 4 | 4 | 3 | **Bar held mid-curl but no plates/collars on the bar** — looks like an empty technique bar. Fails the "loaded barbell" expectation for a barbell exercise. | yes |
| dumbbell-curl | 4 | 4 | 4 | Standing, dumbbells curled at chest height with supinated grip. | no |
| incline-db-curl | 4 | 4 | 4 | Reclined on incline bench, dumbbells hanging behind body for stretch. | no |
| hammer-curl | 4 | 4 | 4 | Neutral grip, dumbbells curled at shoulder height. | no |
| preacher-curl | 4 | 4 | 4 | Preacher bench with arm pad, EZ-curl/straight bar at top of curl. | no |
| cable-curl | 4 | 4 | 4 | Standing at low-cable column, bar curled to chest. | no |
| tricep-pushdown | 4 | 4 | 4 | Standing at high-cable column, straight bar pushed down with elbows at sides. | no |
| rope-pushdown | 4 | 4 | 4 | Rope attachment with split at bottom — distinctive vs straight-bar pushdown. | no |
| overhead-tricep-extension | 4 | 4 | 4 | Standing with both arms overhead, dumbbells lowered behind head. Bilateral two-DB read; acceptable. | no |
| skullcrusher | 4 | 4 | 4 | (Calibration) Lying on bench, bar lowered behind head, knees up. | no |
| pjr-pullover | 4 | 4 | 4 | Lying on bench, dumbbell behind head with elbows bent — PJR pose with the elbow-soft / lat-loaded look. | no |
| dumbbell-pullover | 4 | 4 | 4 | Lying perpendicular-ish on bench, dumbbell stretched overhead with both hands cupping it. | no |
| cable-pullover | 4 | 4 | 4 | Hinged-over standing at high cable, straight arms pulling bar to thighs. | no |
| standing-calf-raise | 4 | 4 | 4 | Standing calf machine with shoulder pads and platform — figure on toes. | no |
| seated-calf-raise | 4 | 4 | 4 | Seated machine with thigh pads and toes on platform, plate loaded. | no |
| donkey-calf-raise | 4 | 4 | 4 | Hinged-over with upper-back pad loaded, feet on platform. Distinctive donkey-style geometry. | no |
| wrist-curl | 4 | 4 | 4 | Forearm on knee, dumbbell at wrist for wrist flexion. | no |
| reverse-curl | 4 | 4 | 3 | **Bar shows minimal/no plates** — looks like a near-empty bar. Pronated grip is barely readable. Visually overlaps with `barbell-curl`. | yes |
| farmers-walk | 4 | 4 | 4 | Walking pose with two dumbbells at sides — clean carry. | no |
| suitcase-carry | 4 | 4 | 2 | **Two dumbbells visible** (one at front-side, one trailing behind body). Suitcase carry is single-side loaded — the second dumbbell defeats the lift. | yes |
| plank | 4 | 4 | 4 | Forearm plank, body straight, side view. Clean. | no |
| side-plank | 4 | 4 | 4 | Side plank on forearm, hips stacked. | no |
| hanging-leg-raise | 4 | 4 | 3 | Knees only at ~90° / hip flexion — should show legs raised to parallel or higher to communicate the contraction. Reads more like a passive hang with knees up. | optional |
| cable-crunch | 4 | 4 | 4 | Kneeling at high cable, rope attachment, torso curled into flexion. | no |
| ab-wheel-rollout | 4 | 4 | 4 | Extended position with ab wheel out, body horizontal. | no |
| pallof-press | 4 | 4 | 4 | Perpendicular to cable column, arms pressed straight out. | no |
| wood-chop | 4 | 4 | 4 | Cable column, arms in mid-rotation diagonal pull. Reads as rotational chop. | no |
| russian-twist | 4 | 4 | 3 | Figure seated leaned-back with hands clasped — no twist visible (mid-position). Static frame doesn't communicate rotation. No load (catalog allows bodyweight). | optional |
| decline-sit-up | 4 | 4 | 4 | Decline bench with foot anchors, figure mid-sit-up. | no |
| tibialis-raise | 4 | 4 | 4 | Heels at wall base, toes lifted with shins flexed. Distinctive tibialis pose. | no |
| jefferson-curl | 4 | 4 | 4 | Standing on platform, deeply rounded spinal flexion, light load reaching down. | no |
| burpee | 4 | 4 | 3 | (Calibration) Shows the jump phase with arms overhead — clean — but a single-frame burpee is hard. Reads more like a star-jump than a burpee specifically. | optional |
| jump-rope | 4 | 4 | 4 | Figure with rope arc visible around body, hands at sides. | no |

## Calibration vs prior passes

### Where this pass agrees with Pass A (Claude) / Pass B (Codex)

- **Anchor at 5/5/5.** All three passes treat `back-squat` as the
  reference and give it the only 5.
- **Style and character are uniform.** All three passes converge on
  4/4 across the catalog for the non-pose axes — the character (short
  hair, tank top, athletic shorts, sneakers) and the line-on-cream
  aesthetic are remarkably consistent. No catalog-wide style/character
  drift was found by any pass.
- **The "pure-lockout-loses-the-lift" pattern is real.** Pass A flagged
  it on `arnold-press`, `block-pulls`, `paused-X`, `push-press`, and
  the original `chin-up`/`pull-up`/`wide-grip-pull-up`. Pass B flagged
  the same on `arnold-press`, `burpee`, the pull-up trio. This pass
  finds the same mechanic on `paused-X` and `arnold-press`, plus
  several siblings Pass A and B graded leniently (paused/non-paused
  collisions, walking/forward/reverse lunge collisions).
- **`arnold-press` and `burpee` are flagged by all three passes.**
  Strong signal — those two should remain on the watch list even after
  one re-roll.

### Where this pass diverges (and why)

This pass is **stricter** and surfaces a class of issues the earlier
passes did not flag:

- **Equipment-rendering errors that earlier passes missed.** Pass A
  and B both gave `barbell-curl` a clean 4/4/4. This pass downgrades
  to 4/4/3 because the bar in the illustration has no plates / collars
  on it — it's an empty technique-bar, not a loaded barbell curl. Same
  story on `reverse-curl`. A "barbell-X" illustration with no plates
  is a soft equipment fail.
- **Multi-figure / extra-equipment glitches.** Pass A and B did not
  flag `suitcase-carry` (both gave 4/4/4); this pass downgrades to
  4/4/2 because there appear to be two dumbbells visible (one trailing
  behind the body line) — which directly contradicts the unilateral
  premise of the lift.
- **`slider-ham-curl` equipment fail.** Pass A and B gave it 4/4/4.
  This pass scores 4/4/2: the illustration shows what reads as a glute
  bridge hold — sliders are not visible, the heels are not on
  anything, the pose is at lockout, not mid-curl.
- **`decline-bench-press` figure tangle.** Pass A and B gave it
  4/4/4. This pass scores 4/3/2 because the limbs overlap in a way
  that almost reads as two figures and the bench rest angle is hard to
  parse.
- **Sibling collisions.** This pass is much stricter on
  `paused-back-squat`, `paused-bench-press`, `paused-deadlift`,
  `walking-lunge`/`reverse-lunge`/`forward-lunge`, `pendlay-row`,
  `yates-row`, `machine-hack-squat`, and `kettlebell-swing` because
  it holds them to the "communicate the distinguishing characteristic
  of the lift" bar — most are visually identical to a more generic
  sibling. Pass A and B were content if the figure-and-equipment looked
  recognizable in isolation; this pass requires that the catalog read
  cohesively when adjacent variants are seen side-by-side.
- **`low-bar-squat` is back on the list.** Pass A flagged this for
  the same reason; Pass B cleared it. This pass agrees with Pass A —
  the bar is at the trap line, not the rear-delt shelf, so the lift
  doesn't read as differentiated from `high-bar-squat`.

### Did the 14 re-rolls in #79 actually fix the flagged issues?

Reviewing the ~14 IDs that the re-roll brief targeted against what's
in the catalog now:

- **Fixed cleanly:**
  - `bulgarian-split-squat` — dumbbells now in hands, rear foot on
    bench, deep flexion. **Fixed.** (4/4/4.)
  - `block-pulls` — bar resting on stacked plates, mid-pull pose with
    knees flexed. **Fixed.** (4/4/4.)
  - `belt-squat` — belt + chain + hanging plate clearly visible on a
    distinctive belt-squat machine. **Fixed.** (4/4/4.)
  - `ghd-back-extension` — GHD apparatus with foot rollers and thigh
    pads, prone position. **Fixed.** (4/4/4.)
  - `incline-db-curl` — figure on incline bench with arms hanging
    behind body line for stretched-bottom position. **Fixed.** (4/4/4.)
  - `jefferson-curl` — figure on platform with dumbbell, deep spinal
    flexion. **Fixed.** (4/4/4.)
  - `wide-grip-pull-up` — visibly wider grip on supported bar with full
    rig structure. **Fixed.** (4/4/4.)
  - `pull-up` — properly hanging from supported overhead bar. **Fixed.**
    (4/4/4.)

- **Partially fixed:**
  - `chin-up` — the bar is now properly overhead with structure, but
    the back-view framing makes the supinated grip invisible, so the
    image is now indistinguishable from `pull-up`. The fix solved the
    "broken bar" problem but introduced a sibling-collision problem.
    **Re-roll list still includes `chin-up`.** (4/4/3.)
  - `low-bar-squat` — pose updated, but bar position still reads at
    the trap line rather than the rear-delt shelf. The "more forward
    torso lean" instruction wasn't fully picked up either.
    **Re-roll list still includes `low-bar-squat`.** (4/4/3.)
  - `close-grip-bench` — still indistinguishable from regular bench
    press; hands appear to overlap on the bar but width is not visibly
    narrower than the `bench-press` anchor. **Re-roll list still
    includes `close-grip-bench`.** (4/4/3.)
  - `arnold-press` — re-rolled to a mid-rotation pose with both
    dumbbells at shoulder height (palms-in start), but the rotation
    is still ambiguous in a single frame; reads partway between curl
    and press. **Re-roll list still includes `arnold-press`.** (4/4/3.)
  - `push-press` — captures the dip pose, but reads as a front-rack
    squat rather than a clearly-pre-launch push-press. **Still 4/4/3.**
  - `burpee` — moved to the post-jump arms-overhead pose (better than
    the static push-up bottom Pass B saw), but a single frame can't
    convey the multi-phase movement; now reads as a vertical jump.
    **Still 4/4/3.**

- **No NEW regressions introduced.** None of the re-rolled
  illustrations broke style or character continuity, and none
  introduced anatomical glitches that weren't there before. The
  re-rolls landed cleanly on the visual canon.

**Net:** the re-rolls fixed 8 of 14 cleanly; the remaining 6 (chin-up,
low-bar-squat, close-grip-bench, arnold-press, push-press, burpee)
are at the inherent limit of what a single-frame technical drawing
can communicate, plus a couple of cases where the re-roll didn't quite
hit the framing the brief asked for.

## World-class verdict

The catalog **reads as a coherent product**. Style and character
consistency across 133 illustrations is excellent — there is not a
single style outlier, no character drift, no shading regression, no
comic-book intrusions. As a v1 paid-app catalog, it's defensible.

**However,** at the strict "ship without flinching" bar, ~25 of 133
illustrations would draw a comment from a strength specialist
reviewing the catalog, mostly because related lifts visually
collide (paused vs non-paused, walking vs forward lunge, chin-up vs
pull-up, low-bar vs high-bar squat). The 8 required-re-roll IDs are
genuine errors — empty bar on `barbell-curl`, two dumbbells on
`suitcase-carry`, sliders missing on `slider-ham-curl`, body tangle
on `decline-bench-press`, and four sibling-differentiation failures.

### Top issues that would block a "world-class" claim if not fixed

1. **Equipment errors on three illustrations** — empty barbell on
   `barbell-curl`, missing sliders on `slider-ham-curl`, two
   dumbbells on `suitcase-carry`. These are the kind of thing that
   reviews and refund threads catch.
2. **`decline-bench-press` figure-tangle.** Reads as anatomically
   off; needs a re-roll regardless of the framing question.
3. **Sibling collisions across paused / non-paused / walking-vs-
   forward / low-vs-high.** Coaches who scan side-by-side will see
   them as duplicates.
4. **`chin-up` is now indistinguishable from `pull-up`** post-re-roll
   — supinated grip needs to be visible (front-quarter view, not back
   view).
5. **`low-bar-squat` bar position** still doesn't read on the rear
   delts; that's the singular feature that makes the lift the lift.

### Top strengths

1. **Style and character consistency.** Across 133 illustrations the
   coach is the same person — same body, same hair, same kit. No drift.
2. **Equipment rendering is generally strong.** Hex-bar, leg-press
   sled, GHD, pendulum-squat, belt-squat machine, landmine, hack-squat
   sled — all schematic but unambiguous.
3. **Hand and finger rendering is clean** across the catalog. Despite
   the AI-image-gen reputation for hand glitches, I did not find a
   single illustration with extra fingers or visibly broken wrists.
4. **Plate detail** (hub, ring, schematic spokes) reads consistently
   and reads as Olympic plates without over-detailing.
5. **Single-figure discipline.** Of 133 illustrations only one
   (`decline-bench-press`) has any "is that two figures?" ambiguity,
   and that's the limb-overlap issue, not an actual extra figure.
