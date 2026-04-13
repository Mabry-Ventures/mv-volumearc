import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

struct VolumeArcWidgetController {
    func reloadTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
