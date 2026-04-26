# Final review brief — all 133 illustrations against world-class standards

This is the final QA pass on the VolumeArc exercise illustration catalog
before launch. Two earlier validation passes ran with a "v1 acceptable"
bar; 14 illustrations were re-rolled. This pass holds **all 133** to
**world-class standards** — comparable to what ships in Strong, Hevy,
Future, Caliber, or top-tier instructional anatomy textbooks.

## What "world-class" means here

Each illustration must clear all three bars:

### 1. Anatomical correctness — does the pose communicate the lift?

- Body angles match the named exercise's mechanical reality
- Equipment is present, correctly geometrically constructed, and
  positioned per the lift (e.g., a low-bar squat shows the bar low on
  rear delts, not at the trap line)
- Pose framing differentiates the lift from related variants (a
  close-grip bench must look distinctly different from a regular bench;
  a Pendlay row must look distinctly different from a barbell row)
- Hands, feet, and joints render cleanly — no extra fingers, distorted
  wrists, broken knee angles
- The pose communicates the **distinguishing characteristic** of the
  lift, not just a generic version

### 2. Visual consistency — does the catalog feel like a single product?

- Same coach character across every illustration: short hair, athletic
  shorts, tank top, neutral build, no facial detail (use the
  `back-squat` anchor as ground truth)
- Same line weight, line color (`#1F2937`-equivalent dark gray),
  background tone (off-white `#F4F2EE`-equivalent or transparent)
- Same level of equipment detail across the catalog
- No stylistic outliers (one suddenly looking comic-book vs the rest
  being technical-illustration)
- 1024×1024 square format

### 3. World-class polish

- Negative space respected — no annotations, arrows, motion lines,
  background clutter, multiple humans, sweat drops
- Composition feels intentional — the figure is placed in the frame
  with appropriate breathing room
- Equipment connects to the body believably (hands gripping bars
  correctly; feet planted on platforms; cables attached to attachment
  points)
- A reviewer who tracks the strength industry would say "this looks
  shippable" without any "but…"

## Scoring rubric (1-5)

| Score | Meaning |
|---|---|
| 5 | World-class. Indistinguishable from a hand-illustrated catalog by a strength specialist. No concerns. |
| 4 | Clean and recognizable. Minor stylistic drift but ships without comment. |
| 3 | Visibly imperfect. A reviewer would notice and flag it. |
| 2 | Wrong on a meaningful axis (different character, missing required equipment, anatomical glitch). |
| 1 | Fundamentally broken. Unrecognizable, missing figure, wildly off-style. |

**Be strict.** Most decent illustrations should land 4. A 5 should be
rare and earned. Anything that an experienced strength coach would
hesitate over gets a 3 or below. World-class bar means: would *you*
ship this in a paid product without flinching?

## Inputs

1. **Catalog source of truth** —
   `VolumeArcNative/Sources/VolumeArcCore/Workout/ExerciseCatalog+Entries.swift`.
   For every entry: `id`, `name`, `pattern`, `primaryEquipment`,
   `cues`, `unilateral`, `lengthenedPositionEmphasis`,
   `primaryMuscles`. Use these to know what each illustration MUST
   depict.

2. **Style anchor** —
   `App/Assets.xcassets/ExerciseIllustrations/back-squat.imageset/back-squat.png`.
   Pin this as the character/style reference before scoring anything.

3. **Style canon** — `Tools/exercise-art/STYLE.md`. Defines line weight,
   color, character, pose framing per movement family.

4. **Prior validation reports** (read AFTER scoring as a calibration
   check, not before):
   - `Tools/exercise-art/validation-report-codex.md` (Pass B)
   - `Tools/exercise-art/validation-report-claude.md` (Pass A)
   - `Tools/exercise-art/REROLL-BRIEF.md` (the 14 re-rolls done in #79)

## Workflow

1. Read this brief end-to-end.
2. Read `Tools/exercise-art/STYLE.md` for general style rules.
3. Read the catalog source. Know what every ID is supposed to show.
4. Read the anchor PNG. Pin it as your character reference.
5. **Sample 6-8 random IDs from across the catalog and view them
   side-by-side with the anchor before scoring anything.** This
   calibrates your rubric — what does "4" look like in practice on this
   set, what does "3" look like.
6. For every imageset under `App/Assets.xcassets/ExerciseIllustrations/*.imageset/`,
   view the PNG and score it on the three axes:
   - `style_score` (1-5) — line weight, background, level of detail
     match the canon?
   - `character_score` (1-5) — same coach figure as anchor?
   - `pose_score` (1-5) — pose anatomically correct + communicates the
     distinguishing characteristic of the named lift + equipment per
     catalog `primaryEquipment` is present and well-rendered?
7. Process in batches of 12-15 to avoid blowing context. Append rows to
   the report file as you go; don't try to keep all 133 scores in
   memory.
8. After scoring all 133, read the prior reports and add a section
   comparing your findings to them: where did you agree, where did you
   diverge, did the 14 re-rolls actually fix what was flagged?

## Output target

`Tools/exercise-art/validation-report-final.md` with this structure:

```markdown
# Final review — VOL-105 illustration catalog

## Summary
- Total reviewed: 133
- Score distribution: <5: N, 4: N, 3: N, 2: N, 1: N> (counts of
  min(scores) per row)
- World-class verdict: <X / 133 ship-ready as-is>
- Recommended re-roll list: <N IDs whose min(scores) <= 3>

## Re-roll table (worst first)
| id | style | character | pose | concern | reroll? |
|---|---:|---:|---:|---|---|
... sorted ascending by min(scores) ...

## Full catalog table (all 133, same columns, sorted by ID for diffability)
...

## Calibration vs prior passes
- Where this pass agrees with Pass A / Pass B
- Where it diverges (and why)
- Did the 14 re-rolls in #79 actually fix the flagged issues?
- Any of the re-rolls that introduced NEW regressions?

## World-class verdict
- One paragraph on whether the catalog as a whole feels shippable as v1
  for a paid app
- Top 3-5 issues that would block "world-class" claim if not fixed
- Top 3-5 strengths
```

## Don't modify

- Don't regenerate any illustrations
- Don't modify the catalog source
- Don't read the prior validation reports BEFORE you've finished
  scoring — they'll bias your calibration

## When done

Reply with:
- Total reviewed
- The 10 lowest-scoring IDs in ascending min-score order
- World-class verdict (one sentence: ship as-is / re-roll list size N)
- Absolute path to the report

This is the only deliverable. No PR, no edits to anything other than
the report file.
