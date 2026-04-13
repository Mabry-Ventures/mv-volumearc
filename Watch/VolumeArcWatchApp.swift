import SwiftUI

@main
struct VolumeArcWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchWorkoutView(model: .live())
        }
    }
}
