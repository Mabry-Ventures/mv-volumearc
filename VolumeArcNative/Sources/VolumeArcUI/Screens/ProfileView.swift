#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Profile tab — user settings, preferences, subscription status.
public struct ProfileView: View {
    @ObservedObject var model: WorkoutDashboardModel

    public init(model: WorkoutDashboardModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                profileHeader
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())

            Section("Training") {
                row(label: "Advancement", value: model.athlete.advancementLevel.rawValue.capitalized, icon: "chart.line.uptrend.xyaxis")
                row(label: "Weekly days", value: "\(model.athlete.weeklyTrainingDays)", icon: "calendar")
                row(label: "Rep range", value: "\(model.athlete.preferredRepRange.lowerBound)-\(model.athlete.preferredRepRange.upperBound)", icon: "number")
                row(label: "Equipment", value: "\(model.athlete.availableEquipment.count) types", icon: "dumbbell.fill")
            }

            Section("App") {
                NavigationLink {
                    SignalsDetailPlaceholder()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                NavigationLink {
                    Text("About VolumeArc")
                        .padding()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }

            if !model.operationalSignals.isEmpty {
                Section("Status") {
                    ForEach(model.operationalSignals, id: \.id) { signal in
                        Label(signal.title, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(VA.Colors.warning)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DashboardTab.profile.title)
        .navigationBarTitleDisplayMode(.large)
    }

    private var profileHeader: some View {
        VACard(style: .accent) {
            HStack(spacing: VA.Space.md) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [VA.Colors.primary, VA.Colors.primary.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 64, height: 64)
                    Text(initials)
                        .font(VA.Typography.title2)
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(model.athlete.name.isEmpty ? "Set up your profile" : model.athlete.name)
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(model.athlete.advancementLevel.rawValue.capitalized + " lifter")
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, VA.Space.sm)
    }

    private var initials: String {
        let parts = model.athlete.name.split(separator: " ").prefix(2)
        if parts.isEmpty { return "VA" }
        return parts.compactMap { $0.first }.map(String.init).joined()
    }

    private func row(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(VA.Colors.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(VA.Colors.textSecondary)
        }
    }
}

private struct SignalsDetailPlaceholder: View {
    var body: some View {
        VAEmptyState(
            icon: "chart.xyaxis.line",
            title: "Diagnostics",
            message: "Detailed system diagnostics will appear here."
        )
        .navigationTitle("Diagnostics")
    }
}
#endif
