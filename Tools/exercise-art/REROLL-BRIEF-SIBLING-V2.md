# Re-roll brief — 3 borderline sibling-collision fixes (Tier B v2)

The first sibling-collision pass (REROLL-BRIEF-SIBLING.md) re-rolled 12
illustrations. 9 hit the differentiating feature cleanly. 3 came in
borderline — the pose is recognizable but doesn't push hard enough on
the defining characteristic to differentiate from the sibling lift.

These 3 need a sharper second pass.

## Style continuity is non-negotiable

Match
`App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png`
on every non-pose axis:

- Same coach figure (short hair, athletic shorts, tank top, neutral
  build, no facial detail)
- Same monochrome line on off-white background
- Same line weight, same level of equipment detail
- 1024×1024 square

## Per-ID framing — make the differentiator visually inescapable

Replace each existing PNG at
`App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/<id>.png`.

| ID | Sibling collision | What was weak in v1 | Sharper v2 framing |
|---|---|---|---|
| `arnold-press` | overhead-press / standing-db-press | DBs at shoulder height with palms appearing pronated already — reads as a static start position | MID-press position — DBs at FOREHEAD HEIGHT (between shoulder and overhead). Palms in HALF-ROTATION: one palm visibly turned ~45° between supinated (toward face) and pronated (forward). Show the rotation **in progress** — the wrists must be visibly twisted, not flat. The half-rotation is the entire defining feature; if a viewer can't see the rotation, the gen has failed. Front view or 3/4 view, NOT side profile (rotation is invisible from the side). |
| `walking-lunge` | forward-lunge | Side profile with arms hanging at sides — reads like a static held forward lunge | MID-STRIDE with **clearly asymmetric arm swing**: one arm visibly forward (e.g., forward arm at chest height in front of body), the other arm visibly back behind the hip. The figure is captured at the moment of stepping, with weight transferring forward. Body has a slight forward lean suggesting locomotion — NOT a balanced stationary pose. Side profile. The asymmetric arm swing is the visual cue that this figure is *moving forward*, not holding a lunge. |
| `yates-row` | barbell-row / pendlay-row | Grip orientation ambiguous; could read as pronated | UNDERHAND (supinated) grip — both palms facing UP/FORWARD, knuckles facing DOWN. This is the entire defining feature vs barbell-row (pronated grip) and Pendlay row (pronated, parallel to floor). Torso angle ~30-40° from vertical (more upright than Pendlay's horizontal). Bar pulled to lower abdomen at hip level. Use a 3/4 angle that lets both wrists be clearly visible — the supinated grip MUST be unambiguous. The wrists/grip is the differentiator; if grip orientation is hard to read, the gen has failed. |

## Workflow

1. Read this brief.
2. Read `App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png` as anchor.
3. For each of the 3 IDs, generate via `image_generation` with the
   sharper framing. Save to
   `App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/<id>.png`,
   replacing the existing file.
4. After each gen, self-assess: is the differentiating feature
   (rotation / arm swing / supinated grip) **visually inescapable**, or
   is it subtle? If subtle, regenerate with even sharper framing.

## When done

Reply with: which IDs you re-rolled, your self-assessment of whether
the differentiator is now inescapable, and any IDs that still feel
borderline after this second pass.
