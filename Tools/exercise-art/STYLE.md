# VolumeArc exercise illustration — style reference

Used to brief Codex CLI's `image_generation` tool for the ~133 exercise
illustrations that ship with VOL-105 Phase 2.

## Style canon

- **Format:** clean technical line-drawing, single line weight (1.5-2px equivalent).
  Think instructional textbook anatomy, not stylized comic art.
- **Color:** monochrome grayscale. The line color is `#1F2937` (VolumeArc
  dark text token equivalent). The fill (when shading is needed for muscle
  emphasis) is a 15% opacity warm gray.
- **Background:** transparent, OR if format constraints force opaque, the
  app's `VA.Colors.surfaceSecondary` equivalent which is `#F4F2EE`.
- **Aspect ratio:** 1024×1024 square. The exercise pose is centered, with
  ~12% padding on every edge.
- **Subject:** a single androgynous human figure, neutral build (not
  bodybuilder-extreme, not minimal stick-figure). Same character across
  all 133 poses — short hair, athletic shorts, tank top, no face details
  beyond a simple suggestion. Treat the figure as a teaching mannequin,
  not a portrait.
- **Equipment:** drawn with the same line weight as the figure. Olympic
  barbells with plates, dumbbells, machines, cables — drawn schematically
  (recognizable but not photo-real).
- **Pose framing:** mid-rep position that best communicates the movement.
  For loaded movements, show the position of greatest tension (bottom of
  squat, lockout of deadlift). For machine work, include the relevant
  machine geometry. For bodyweight, show the working position.
- **Annotations:** none. No arrows, no labels, no numbers. Pure pose.

## Negative space

Things that do NOT appear in any illustration:

- Photo-realistic skin texture, faces, or musculature detail
- Background clutter (gym equipment behind the figure, dropped weights,
  motivational text)
- Color beyond the line + fill described above
- Multiple humans
- Stylized comic effects (motion lines, action sparks, sweat drops)
- Apple SF Symbols or other glyph references

## Pose framing rules

| Movement family | Camera angle | Pose |
|---|---|---|
| Squat / lunge family | Side profile | Bottom of rep, depth visible |
| Hinge family | Side profile | Hip flexion / extension visible |
| Horizontal push | 3/4 from foot end of bench | Bar at chest |
| Vertical push | Front-facing | Bar at top of overhead lockout |
| Horizontal pull | 3/4 from chest side | Bar at lower chest contact |
| Vertical pull | Side profile | Chin over the bar |
| Carry | Side profile | Mid-walk, equipment visible |
| Isolation (curls / extensions) | Side profile | Peak contraction |
| Core | Side profile or 3/4 | Held position |

## Per-pose prompt template

When generating a specific exercise, fill in the template:

```
A clean technical line-drawing illustration of a single androgynous
athletic figure performing [EXERCISE NAME]. [POSE FRAMING per table
above]. Equipment: [PRIMARY EQUIPMENT]. The figure is shown in [POSE
DESCRIPTION — bottom of squat, lockout, etc]. Style: monochrome
grayscale, single 2px line weight, transparent background. 1024×1024
square. The figure has short hair, athletic shorts, tank top, no facial
detail. Strict negative space — no annotations, no arrows, no
background clutter.
```

## Iteration discipline

- Generate one anchor pose first (back squat is the canonical anchor —
  every coach knows what a correctly-drawn back squat looks like).
- Review against the style canon above before proceeding.
- If anchor is approved, generate four more anchors covering the
  diversity of the catalog: deadlift (hinge), bench press (horizontal
  push), pull-up (vertical pull), Bulgarian split squat (lunge,
  unilateral). These five anchors prove the style holds across the
  taxonomy.
- Only after the five anchors are approved do we run the full 133.
- Per-pose reroll budget: if a generation fails the style canon, re-roll
  up to twice. If three attempts fail, log the exercise ID and move on.
  Hand-fix the failures in a final pass.
