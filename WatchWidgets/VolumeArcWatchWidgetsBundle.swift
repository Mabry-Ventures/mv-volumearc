#if os(watchOS)
import SwiftUI
import WidgetKit

/// Top-level widget bundle for the watchOS widget extension.
/// Registers every complication/widget this extension provides.
///
/// VOL-237: `VolumeArcSmartStackWidget` joined the bundle as the
/// wrist-flick (Smart Stack) surface. It's a distinct surface from
/// `VolumeArcWatchComplication` — complications live on the watch
/// face, Smart Stack widgets surface on the wrist-flick stack and
/// are ranked by `TimelineEntryRelevance` (active workout pushes
/// VolumeArc to the top of the stack).
@main
struct VolumeArcWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VolumeArcWatchComplication()
        VolumeArcSmartStackWidget()
    }
}
#endif
