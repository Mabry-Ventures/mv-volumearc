#if os(watchOS)
import SwiftUI
import WidgetKit

/// Top-level widget bundle for the watchOS widget extension.
/// Registers every complication/widget this extension provides.
@main
struct VolumeArcWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        VolumeArcWatchComplication()
    }
}
#endif
