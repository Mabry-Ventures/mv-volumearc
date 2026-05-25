# Watch Face Pack (VOL-238)

VolumeArc ships three designed Apple Watch face presets:

| Preset | Family | Complications |
|---|---|---|
| VolumeArc Modular | Modular Duo | Readiness, Next Workout, Last Session, Streak |
| VolumeArc Infograph | Infograph | Readiness bezel, Next Workout, Last Session, Streak |
| VolumeArc Photo | Photos | Readiness and Streak over a user-photo layout |

## Install Path

Once at least one export is bundled, the iOS app exposes the pack under Profile -> Watch Faces. Each preset resolves a bundled `.watchface` file from `App/WatchFaces/` and passes the file URL to `CLKWatchFaceLibrary.addWatchFace(at:)`. Successful installs record telemetry as:

- category: `watch.face_pack`
- name: `installed`
- metadata: `preset=<modular|infograph|photo>`

Failed attempts record `watch.face_pack/install_failed` with a reason.

## Export Contract

Apple's face-sharing flow produces the installable `.watchface` containers. Do not hand-author placeholder files; the system rejects invalid containers.

Expected bundled filenames:

- `App/WatchFaces/VolumeArc-Modular.watchface`
- `App/WatchFaces/VolumeArc-Infograph.watchface`
- `App/WatchFaces/VolumeArc-Photo.watchface`

Export steps:

1. Recreate each preset in Apple's Watch app on iPhone or in the watchOS simulator using the manifest below.
2. Share the face via the Watch app's Face Sharing flow.
3. Save the `.watchface` file.
4. Add the file under `App/WatchFaces/` with the exact filename above.
5. Run `ruby scripts/generate_xcode_project.rb`.

Apple's documentation says bundled faces must use complications from apps with a valid App Store ID, such as an App Store or TestFlight build. Re-export the final files from a build that has VolumeArc's real app identity before App Store submission.

## Manifest

### VolumeArc Modular

- Family: Modular Duo
- Style: black background, sunrise time tint
- Top: Readiness, graphic rectangular
- Middle: Next Workout, graphic rectangular
- Bottom left: Last Session, graphic bezel/text
- Bottom right: Streak, graphic circular/open gauge

### VolumeArc Infograph

- Family: Infograph
- Style: dark or ivory, sunrise hand color
- Bezel: Readiness, 0-100 arc
- Top right: Next Workout, two-line corner
- Bottom left: Last Session
- Bottom right: Streak

### VolumeArc Photo

- Family: Photos
- Style: user photo, full bleed, subdued overlay
- Top left: Readiness
- Top right: Streak
- Time: bottom center
