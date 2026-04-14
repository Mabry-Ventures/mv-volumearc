#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Profile tab — user settings, preferences, subscription status.
public struct ProfileView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @State private var isEditingProfile = false
    @State private var isShowingPaywall = false

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

            Section(String(localized: "Training", comment: "Profile tab section header — training settings")) {
                row(
                    label: String(localized: "Advancement", comment: "Profile row — advancement level"),
                    value: model.athlete.advancementLevel.displayName,
                    icon: "chart.line.uptrend.xyaxis"
                )
                row(
                    label: String(localized: "Weekly days", comment: "Profile row — weekly training days"),
                    value: "\(model.athlete.weeklyTrainingDays)",
                    icon: "calendar"
                )
                row(
                    label: String(localized: "Rep range", comment: "Profile row — preferred rep range"),
                    value: "\(model.athlete.preferredRepRange.lowerBound)-\(model.athlete.preferredRepRange.upperBound)",
                    icon: "number"
                )
                row(
                    label: String(localized: "Equipment", comment: "Profile row — equipment count"),
                    value: String(
                        localized: "^[\(model.athlete.availableEquipment.count) types](inflect: true)",
                        comment: "Profile row value — pluralized count of equipment types"
                    ),
                    icon: "dumbbell.fill"
                )
                Button {
                    VAHaptics.tap()
                    isEditingProfile = true
                } label: {
                    Label(
                        String(localized: "Edit profile", comment: "Profile button — open edit profile sheet"),
                        systemImage: "pencil"
                    )
                    .foregroundStyle(VA.Colors.primary)
                }
            }

            Section(String(localized: "Premium", comment: "Profile tab section header — subscription")) {
                Button {
                    VAHaptics.tap()
                    isShowingPaywall = true
                } label: {
                    HStack {
                        Label(
                            String(localized: "Upgrade", comment: "Profile button — open the paywall"),
                            systemImage: "sparkles"
                        )
                        .foregroundStyle(VA.Colors.primary)
                        Spacer()
                        Text(String(
                            localized: "Monthly / Yearly",
                            comment: "Profile upgrade row subtitle — available billing periods"
                        ))
                        .font(.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                    }
                    // Combine the row contents into a single accessibility
                    // element with a stable label and identifier. SwiftUI Form
                    // wraps the Button as a Cell in the XCUITest hierarchy, and
                    // identifiers attached only to the Button can fail to
                    // propagate to the cell. Combining the children inside the
                    // Button label and pinning the identifier here makes the
                    // element reachable via app.buttons["profile.upgrade"] and
                    // app.cells["profile.upgrade"] regardless of which type
                    // SwiftUI exposes it as.
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("profile.upgrade")
                    .accessibilityLabel(String(
                        localized: "Upgrade to Premium",
                        comment: "VoiceOver label for the upgrade row"
                    ))
                    .accessibilityAddTraits(.isButton)
                }
            }

            Section(String(localized: "App", comment: "Profile tab section header — app-level settings")) {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label(
                        String(localized: "Diagnostics", comment: "Profile row — open diagnostics screen"),
                        systemImage: "stethoscope"
                    )
                }
                NavigationLink {
                    Text(String(
                        localized: "About VolumeArc",
                        comment: "About VolumeArc screen placeholder title"
                    ))
                    .padding()
                } label: {
                    Label(
                        String(localized: "About", comment: "Profile row — open about screen"),
                        systemImage: "info.circle"
                    )
                }
            }

            if !model.operationalSignals.isEmpty {
                Section(String(localized: "Status", comment: "Profile tab section header — operational status signals")) {
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
        .sheet(isPresented: $isEditingProfile) {
            EditProfileView(
                isPresented: $isEditingProfile,
                athlete: model.athlete,
                coachingStyle: model.athlete.coachingStyle,
                privacyMode: model.athlete.privacyMode,
                sessionMinutes: model.athlete.sessionTimeBudgetMinutes
            ) { defaults in
                Task {
                    await model.updateProfile(defaults)
                }
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            Group {
                if let subscriptionStore = model.subscriptionStore {
                    PaywallView(
                        subscriptionStore: subscriptionStore,
                        isPresented: $isShowingPaywall
                    )
                }
            }
        }
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
                    Text(model.athlete.name.isEmpty
                         ? String(localized: "Set up your profile", comment: "Profile header when no name is set")
                         : model.athlete.name)
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(model.athlete.advancementLevel.lifterPhrase)
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
#endif
