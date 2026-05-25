#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Profile tab — user settings, preferences, subscription status.
public struct ProfileView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @State private var isEditingProfile = false
    @State private var isShowingPaywall = false
    @State private var isShowingCoachMemory = false
    /// VOL-176: feedback sheet visibility. Only rendered when the
    /// caller supplies a non-nil `onSendFeedback` closure (i.e., the
    /// App layer wired Sentry + telemetry submission). The model
    /// module + previews can omit the closure and the row hides.
    @State private var isShowingFeedback = false

    /// VOL-176: optional App-layer hook. Called with the user-selected
    /// category + free-text description when the sheet's submit button
    /// is tapped. The App layer assembles a `FeedbackBundle`, encodes
    /// it as JSON, forwards to `SentrySDK.captureUserFeedback(_:)`, and
    /// records a `feedback.submitted` telemetry event.
    private let onSendFeedback: ((FeedbackBundle.Category, String) -> Void)?

    public init(
        model: WorkoutDashboardModel,
        onSendFeedback: ((FeedbackBundle.Category, String) -> Void)? = nil
    ) {
        self.model = model
        self.onSendFeedback = onSendFeedback
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.xl) {
                profileTitle
                profileHero
                trainingSection
                subscriptionCard
                accountSection
                statusSection
            }
            .padding(VA.Space.lg)
            .padding(.bottom, VA.Space.xxl)
        }
        .background(VA.Colors.surfaceGrouped)
        .accessibilityIdentifier("profile.root")
        .navigationTitle(DashboardTab.profile.title)
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $isShowingFeedback) {
            FeedbackView(isPresented: $isShowingFeedback) { category, description in
                onSendFeedback?(category, description)
            }
        }
        .sheet(isPresented: $isShowingCoachMemory) {
            CoachMemoryView(model: model)
        }
    }

    private var profileTitle: some View {
        Text(DashboardTab.profile.title)
            .font(VA.Typography.title)
            .foregroundStyle(VA.Colors.textPrimary)
            .padding(.top, VA.Space.sm)
    }

    private var profileHero: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VA.Gradients.sunriseHero
                Circle()
                    .fill(VA.Colors.textOnPrimary.opacity(0.18))
                    .frame(width: 160, height: 160)
                    .offset(x: 42, y: -48)
                    .accessibilityHidden(true)

                HStack(spacing: VA.Space.md) {
                    Text(initials)
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.primaryDeep)
                        .frame(width: 56, height: 56)
                        .background(VA.Colors.textOnPrimary.opacity(0.96), in: Circle())
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(displayName)
                            .font(VA.Typography.title2)
                            .foregroundStyle(VA.Colors.textOnPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(model.athlete.advancementLevel.lifterPhrase)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.84))
                    }
                    Spacer()
                    Text(String(localized: "PREMIUM", comment: "Profile membership badge"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.primaryDeep)
                        .padding(.horizontal, VA.Space.sm)
                        .frame(height: 28)
                        .background(VA.Colors.textOnPrimary.opacity(0.96), in: Capsule())
                }
                .padding(VA.Space.xl)
            }

            HStack(spacing: 0) {
                ProfileStat(value: "\(model.recentSessions.count)", label: String(localized: "sessions", comment: "Profile stat label"))
                Divider()
                ProfileStat(value: compactTotalVolume, label: String(localized: "lb total", comment: "Profile stat label"))
                Divider()
                ProfileStat(value: weeklyTrainingDaysMultiplier, label: String(localized: "weekly", comment: "Profile stat label"))
            }
            .padding(.vertical, VA.Space.lg)
            .background(VA.Colors.surfacePrimary)
        }
        .clipShape(RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous))
        .vaShadow(.md)
    }

    private var trainingSection: some View {
        ProfileCardSection(title: String(localized: "Training", comment: "Profile training section title")) {
            profileRow(
                label: String(localized: "Coaching style", comment: "Profile row label"),
                value: model.athlete.coachingStyle.displayName,
                icon: "bubble.left.and.bubble.right.fill"
            ) {
                VAHaptics.tap()
                isEditingProfile = true
            }
            // VOL-200 P4: stable identifier so the `profile.edit-profile`
            // and `profile.coaching-style` journey tests can tap this
            // row reliably to open the Edit Profile sheet.
            .accessibilityIdentifier("profile.coachingStyleRow")
            profileRow(
                label: String(localized: "Advancement", comment: "Profile row label"),
                value: model.athlete.advancementLevel.displayName,
                icon: "chart.line.uptrend.xyaxis"
            ) {
                VAHaptics.tap()
                isEditingProfile = true
            }
            profileRow(
                label: String(localized: "Equipment", comment: "Profile row label"),
                value: model.athlete.availableEquipment.count == 1
                    ? String(localized: "1 type", comment: "Singular equipment count on Profile row")
                    : String(localized: "\(model.athlete.availableEquipment.count) types", comment: "Plural equipment count on Profile row"),
                icon: "dumbbell.fill"
            ) {
                VAHaptics.tap()
                isEditingProfile = true
            }
            profileRow(
                label: String(localized: "Time / session", comment: "Profile row label"),
                value: "\(model.athlete.sessionTimeBudgetMinutes) min",
                icon: "clock.fill"
            ) {
                VAHaptics.tap()
                isEditingProfile = true
            }
            profileRow(
                label: String(localized: "Coach memory", comment: "Profile row label"),
                value: model.coachMemory.isEmpty
                    ? String(localized: "Empty", comment: "Profile coach memory empty value")
                    : coachMemoryCountText,
                icon: "brain.head.profile"
            ) {
                VAHaptics.tap()
                isShowingCoachMemory = true
            }
            .accessibilityIdentifier("profile.coachMemory")
        }
    }

    private var coachMemoryCountText: String {
        let count = model.coachMemory.entries.count
        if count == 1 {
            return String(localized: "1 note", comment: "Profile coach memory single count value")
        }
        return String(localized: "\(count) notes", comment: "Profile coach memory plural count value")
    }

    private var subscriptionCard: some View {
        VACard(style: .glass) {
            HStack(spacing: VA.Space.md) {
                Image(systemName: "sparkles")
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.primary)
                    .frame(width: 36, height: 36)
                    .background(VA.Colors.primary.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(String(localized: "Premium", comment: "Profile subscription title"))
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(String(localized: "Monthly / Yearly", comment: "Profile subscription subtitle"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
                Button {
                    VAHaptics.tap()
                    isShowingPaywall = true
                } label: {
                    Text(String(localized: "Manage", comment: "Profile manage subscription action"))
                        .font(VA.Typography.button)
                        .foregroundStyle(VA.Colors.primary)
                        .padding(.horizontal, VA.Space.md)
                        .frame(height: 34)
                        .background(VA.Colors.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.upgrade")
        .accessibilityLabel(String(localized: "Upgrade to Premium", comment: "VoiceOver label for the upgrade row"))
        .accessibilityHint(String(
            localized: "Opens the paywall to start or manage a Premium subscription",
            comment: "VoiceOver hint for the upgrade row"
        ))
        .accessibilityAddTraits(.isButton)
    }

    private var accountSection: some View {
        ProfileCardSection(title: String(localized: "Account", comment: "Profile account section title")) {
            NavigationLink {
                DiagnosticsView()
            } label: {
                profileRowLabel(
                    label: String(localized: "Diagnostics", comment: "Profile row label"),
                    value: "",
                    icon: "stethoscope"
                )
            }
            .buttonStyle(.plain)
            // VOL-200 P4: stable identifier so the `profile.diagnostics`
            // journey test can resolve this row without depending on
            // the localized "Diagnostics" string.
            .accessibilityIdentifier("profile.diagnostics")

            let bundledWatchFaces = WatchFacePack.bundledPresets()
            if !bundledWatchFaces.isEmpty {
                NavigationLink {
                    WatchFacePackView(model: model)
                } label: {
                    profileRowLabel(
                        label: String(localized: "Watch Faces", comment: "Profile watch faces row label"),
                        value: bundledWatchFaces.count == 1
                            ? String(localized: "1 preset", comment: "Profile watch faces singular row value")
                            : String(
                                localized: "\(bundledWatchFaces.count) presets",
                                comment: "Profile watch faces plural row value"
                            ),
                        icon: "applewatch"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.watchFaces")
            }

            profileRow(
                label: model.isHealthAuthorized
                    ? String(localized: "Apple Health", comment: "Profile Apple Health row label")
                    : String(localized: "Connect Apple Health", comment: "Profile Apple Health row label"),
                value: model.isHealthAuthorized
                    ? String(localized: "Connected", comment: "Profile Apple Health connected value")
                    : String(localized: "Not connected", comment: "Profile Apple Health disconnected value"),
                icon: "heart.text.square.fill"
            ) {
                Task {
                    VAHaptics.tap()
                    await model.requestHealthKitAuthorization()
                }
            }
            .accessibilityIdentifier("profile.health.connect")
            .accessibilityLabel(healthAuthorizationAccessibilityLabel)
            .accessibilityValue(healthAuthorizationAccessibilityValue)

            // VOL-176: feedback entry. Only rendered when the App layer
            // wired a submission closure (Sentry + telemetry path).
            // Test targets / previews that omit the closure see no row.
            if onSendFeedback != nil {
                profileRow(
                    label: String(localized: "Send feedback", comment: "Profile feedback row label"),
                    value: "",
                    icon: "envelope.fill"
                ) {
                    VAHaptics.tap()
                    isShowingFeedback = true
                }
                .accessibilityIdentifier("profile.feedback")
                .accessibilityLabel(String(
                    localized: "Send feedback to the VolumeArc team",
                    comment: "VoiceOver label for the Send feedback row"
                ))
            }

            NavigationLink {
                Text(String(localized: "About VolumeArc", comment: "About VolumeArc screen placeholder title"))
                    .padding()
            } label: {
                profileRowLabel(
                    label: String(localized: "About", comment: "Profile row label"),
                    value: "",
                    icon: "info.circle.fill"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if !model.operationalSignals.isEmpty {
            ProfileCardSection(title: String(localized: "Status", comment: "Profile status section title")) {
                ForEach(model.operationalSignals, id: \.id) { signal in
                    profileRowLabel(label: signal.title, value: signal.severity.rawValue.capitalized, icon: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    private var displayName: String {
        model.athlete.name.isEmpty
            ? String(localized: "Set up your profile", comment: "Profile header when no name is set")
            : model.athlete.name
    }

    private var initials: String {
        model.athlete.initials
    }

    private var compactTotalVolume: String {
        let totalVolume = model.recentSessions.map(\.totalVolumeLoad).reduce(0, +)
        if totalVolume >= 1000 {
            return Int(totalVolume).formatted(.number.notation(.compactName))
        }
        return "\(Int(totalVolume))"
    }

    private var weeklyTrainingDaysMultiplier: String {
        String(
            localized: "\(model.athlete.weeklyTrainingDays)x",
            comment: "Profile stat weekly training days multiplier value"
        )
    }

    private var healthAuthorizationAccessibilityValue: String {
        if model.isHealthAuthorized {
            return String(localized: "Connected", comment: "VoiceOver value for Apple Health row")
        }

        if VolumeArcRuntimeFlags.shouldSurfacePermissionPrompts {
            return String(
                localized: "System permission prompt enabled",
                comment: "VoiceOver value when tapping will surface the system prompt"
            )
        }

        return String(localized: "Not connected", comment: "VoiceOver value for Apple Health row")
    }

    private var healthAuthorizationAccessibilityLabel: String {
        model.isHealthAuthorized
            ? String(
                localized: "Apple Health connected",
                comment: "VoiceOver label for the Apple Health row after connection"
            )
            : String(
                localized: "Connect to Apple Health",
                comment: "VoiceOver label for the Apple Health row before connection"
            )
    }

    private func profileRow(label: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            profileRowLabel(label: label, value: value, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func profileRowLabel(label: String, value: String, icon: String) -> some View {
        HStack(spacing: VA.Space.md) {
            Image(systemName: icon)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.primary)
                .frame(width: 30, height: 30)
                .background(VA.Colors.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous))
            Text(label)
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textPrimary)
            Spacer(minLength: VA.Space.sm)
            if !value.isEmpty {
                Text(value)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Image(systemName: "chevron.right")
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textTertiary)
        }
        .padding(.horizontal, VA.Space.lg)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

private struct ProfileCardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(title.uppercased())
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.4)
                .padding(.horizontal, VA.Space.xs)
            VStack(spacing: 0) {
                content
            }
            .background(VA.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous)
                    .stroke(VA.Colors.textTertiary.opacity(0.14), lineWidth: 0.5)
            }
        }
    }
}

private struct ProfileStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: VA.Space.xxs) {
            Text(value)
                .font(VA.Typography.title2)
                .foregroundStyle(VA.Colors.textPrimary)
                .monospacedDigit()
            Text(label.uppercased())
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textTertiary)
                .tracking(0.4)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
