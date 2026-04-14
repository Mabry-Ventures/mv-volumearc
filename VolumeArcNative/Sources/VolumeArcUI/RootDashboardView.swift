#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

public struct RootDashboardView: View {
    @ObservedObject private var navigation: DashboardNavigationModel
    @ObservedObject private var model: WorkoutDashboardModel

    public init(navigation: DashboardNavigationModel, model: WorkoutDashboardModel) {
        self.navigation = navigation
        self.model = model
    }

    public var body: some View {
        VStack {
            if let notice = model.startupNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Text("VolumeArc")
                .font(.largeTitle.bold())

            Text("Dashboard")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
