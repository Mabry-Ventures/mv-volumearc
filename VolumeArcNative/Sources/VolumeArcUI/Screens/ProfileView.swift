#if canImport(SwiftUI)
// swiftlint:disable file_length
import Foundation
import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import VolumeArcCore

/// The Profile tab — user settings, preferences, subscription status.
public struct ProfileView: View { // swiftlint:disable:this type_body_length
    @ObservedObject var model: WorkoutDashboardModel
    @Environment(\.openURL) private var openURL
    @AppStorage(VolumeArcAppearancePreference.storageKey)
    private var appearancePreferenceRawValue = VolumeArcAppearancePreference.system.rawValue
    @AppStorage("volumearc.sessionProfiles.active")
    private var activeSessionProfileName = WorkoutSessionProfile.defaultProfile.rawValue
    @AppStorage(ProfileAvatarStorage.storageKey)
    private var profileAvatarImageData: Data?
    @State private var activeModal: ProfileModal?
    @State private var notificationStatus = ProfileNotificationStatus.unknown
    @State private var accountStatusMessage: String?

    /// VOL-176: optional App-layer hook. Called with the user-selected
    /// category + free-text description when the sheet's submit button
    /// is tapped. The App layer assembles a `FeedbackBundle`, encodes
    /// it as JSON, forwards to `SentrySDK.captureUserFeedback(_:)`, and
    /// records a `feedback.submitted` telemetry event.
    private let onSendFeedback: ((FeedbackBundle.Category, String) -> Void)?
    private let onRequestNotifications: (() async -> Bool)?

    public init(
        model: WorkoutDashboardModel,
        onRequestNotifications: (() async -> Bool)? = nil,
        onSendFeedback: ((FeedbackBundle.Category, String) -> Void)? = nil
    ) {
        self.model = model
        self.onRequestNotifications = onRequestNotifications
        self.onSendFeedback = onSendFeedback
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.xl) {
                profileTitle
                profileHero
                subscriptionCard
                accountSection
                appearanceSection
                trainingSection
                statusSection
            }
            .padding(VA.Space.lg)
            .padding(.bottom, VA.Space.xxl)
        }
        .background(VA.Colors.surfaceGrouped)
        .accessibilityIdentifier("profile.root")
        .navigationTitle(DashboardTab.profile.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeModal) { modal in
            profileModalDestination(modal)
        }
        .task {
            guard onRequestNotifications != nil else { return }
            await refreshNotificationStatus()
        }
    }

    private var profileTitle: some View {
        Text(DashboardTab.profile.title)
            .font(VA.Typography.title)
            .foregroundStyle(VA.Colors.textPrimary)
            .padding(.top, VA.Space.sm)
    }

    private var profileHero: some View {
        Button {
            VAHaptics.tap()
            activeModal = .editProfile
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VA.Gradients.sunriseHero
                    Circle()
                        .fill(VA.Colors.textOnPrimary.opacity(0.18))
                        .frame(width: 160, height: 160)
                        .offset(x: 42, y: -48)
                        .accessibilityHidden(true)

                    HStack(spacing: VA.Space.md) {
                        ProfileAvatarImage(
                            imageData: profileAvatarImageData,
                            initials: initials,
                            size: 56,
                            foreground: VA.Colors.primaryDeep,
                            background: VA.Colors.textOnPrimary.opacity(0.96)
                        )
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
                        Text(subscriptionBadgeText)
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.primaryDeep)
                            .padding(.horizontal, VA.Space.sm)
                            .frame(height: 28)
                            .background(VA.Colors.textOnPrimary.opacity(0.96), in: Capsule())
                        Image(systemName: "chevron.right")
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.82))
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
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.hero.edit")
        .accessibilityLabel(String(localized: "Edit profile", comment: "VoiceOver label for tappable profile header"))
    }

    @ViewBuilder
    private func profileModalDestination(_ modal: ProfileModal) -> some View {
        switch modal {
        case .editProfile:
            EditProfileView(
                isPresented: modalPresentedBinding(.editProfile),
                athlete: model.athlete,
                coachingStyle: model.athlete.coachingStyle,
                privacyMode: model.athlete.privacyMode,
                sessionMinutes: model.athlete.sessionTimeBudgetMinutes
            ) { defaults in
                Task {
                    await model.updateProfile(defaults)
                }
            }
        case .paywall:
            Group {
                if let subscriptionStore = model.subscriptionStore {
                    PaywallView(
                        subscriptionStore: subscriptionStore,
                        isPresented: modalPresentedBinding(.paywall)
                    )
                }
            }
        case .coachMemory:
            CoachMemoryView(model: model)
        case .accountDetails:
            AppleAccountDetailsSheet(
                session: model.accountSession,
                editProfile: {
                    activeModal = .editProfile
                },
                disconnect: {
                    model.clearAccountSession()
                    activeModal = nil
                }
            )
        case .notificationRationale:
            NotificationRationaleSheet(
                status: notificationStatus,
                requestAuthorization: {
                    await requestNotificationAuthorization()
                }
            )
        case let .training(sheet):
            trainingPreferenceDestination(sheet)
        }
    }

    private func modalPresentedBinding(_ modal: ProfileModal) -> Binding<Bool> {
        Binding(
            get: { activeModal == modal },
            set: { isPresented in
                if isPresented {
                    activeModal = modal
                } else if activeModal == modal {
                    activeModal = nil
                }
            }
        )
    }

    private var trainingSection: some View {
        ProfileCardSection(title: String(localized: "Training", comment: "Profile training section title")) {
            profileRow(
                label: String(localized: "Coaching style", comment: "Profile row label"),
                value: model.athlete.coachingStyle.displayName,
                icon: "bubble.left.and.bubble.right.fill"
            ) {
                VAHaptics.tap()
                activeModal = .training(.coaching)
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
                activeModal = .training(.advancement)
            }
            .accessibilityIdentifier("profile.advancementRow")
            profileRow(
                label: String(localized: "Equipment", comment: "Profile row label"),
                value: profileLocalizedTypeCount(model.athlete.availableEquipment.count),
                icon: "dumbbell.fill"
            ) {
                VAHaptics.tap()
                activeModal = .training(.equipment)
            }
            .accessibilityIdentifier("profile.equipmentRow")
            profileRow(
                label: String(localized: "Session profiles", comment: "Profile row label"),
                value: sessionProfilesRowValue,
                icon: "clock.fill"
            ) {
                VAHaptics.tap()
                activeModal = .training(.sessionProfiles)
            }
            .accessibilityIdentifier("profile.sessionProfilesRow")
            profileRow(
                label: String(localized: "Coach memory", comment: "Profile row label"),
                value: model.coachMemory.isEmpty
                    ? String(localized: "Empty", comment: "Profile coach memory empty value")
                    : coachMemoryCountText,
                icon: "brain.head.profile"
            ) {
                VAHaptics.tap()
                activeModal = .coachMemory
            }
            .accessibilityIdentifier("profile.coachMemory")
        }
    }

    private var coachMemoryCountText: String {
        let count = model.coachMemory.entries.count
        return profileLocalizedNoteCount(count)
    }

    private var subscriptionCard: some View {
        Button {
            handleSubscriptionAction()
        } label: {
            VACard(style: .glass) {
                HStack(spacing: VA.Space.md) {
                    Image(systemName: hasPremiumEntitlement ? "checkmark.seal.fill" : "sparkles")
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: 36, height: 36)
                        .background(VA.Colors.primary.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(subscriptionTitle)
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(subscriptionSubtitle)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                    }
                    Spacer()
                    Text(subscriptionActionTitle)
                        .font(VA.Typography.button)
                        .foregroundStyle(VA.Colors.primary)
                        .padding(.horizontal, VA.Space.md)
                        .frame(height: 34)
                        .background(VA.Colors.primary.opacity(0.12), in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.subscription")
        .accessibilityLabel(subscriptionAccessibilityLabel)
        .accessibilityHint(subscriptionAccessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var appleAccountControl: some View {
        #if canImport(AuthenticationServices)
        if model.accountSession != nil {
            profileRow(
                label: String(localized: "Apple ID", comment: "Profile Apple account connected row label"),
                value: appleAccountDisplayValue,
                icon: "person.crop.circle.badge.checkmark"
            ) {
                VAHaptics.tap()
                activeModal = .accountDetails
            }
            .accessibilityIdentifier("profile.appleSignIn.connected")
        } else {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .accessibilityIdentifier("profile.appleSignIn")

                if let accountStatusMessage {
                    Text(accountStatusMessage)
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(
                        localized: """
                            Use Apple ID to seed your profile and keep your account identity stable. \
                            Training data still syncs through your private iCloud database.
                            """,
                        comment: "Profile Sign in with Apple explanatory copy"
                    ))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.md)
        }
        #else
        EmptyView()
        #endif
    }

    private var accountSection: some View {
        ProfileCardSection(title: String(localized: "Account", comment: "Profile account section title")) {
            appleAccountControl

            if onRequestNotifications != nil {
                profileRow(
                    label: String(localized: "Workout notifications", comment: "Profile notification row label"),
                    value: notificationStatus.displayName,
                    icon: "bell.badge.fill"
                ) {
                    VAHaptics.tap()
                    activeModal = .notificationRationale
                }
                .accessibilityIdentifier("profile.notifications")
            }

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
                        value: vaInflectedString(
                            "^[\(bundledWatchFaces.count) preset](inflect: true)",
                            comment: "Profile watch faces preset count row value"
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
                NavigationLink {
                    FeedbackNavigationDestination { category, description in
                        onSendFeedback?(category, description)
                    }
                } label: {
                    profileRowLabel(
                        label: String(localized: "Send feedback", comment: "Profile feedback row label"),
                        value: "",
                        icon: "envelope.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.feedback")
                .accessibilityLabel(String(
                    localized: "Send feedback to the VolumeArc team",
                    comment: "VoiceOver label for the Send feedback row"
                ))
            }

            NavigationLink {
                AboutVolumeArcView()
            } label: {
                profileRowLabel(
                    label: String(localized: "About", comment: "Profile row label"),
                    value: "",
                    icon: "info.circle.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.about")
        }
    }

    private var appearanceSection: some View {
        ProfileCardSection(title: String(localized: "Appearance", comment: "Profile appearance section title")) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(spacing: VA.Space.md) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: 30, height: 30)
                        .background(
                            VA.Colors.primary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
                        )
                    Text(String(localized: "App appearance", comment: "Profile appearance setting label"))
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Spacer(minLength: VA.Space.sm)
                }

                Picker(
                    String(localized: "App appearance", comment: "Profile appearance picker accessibility label"),
                    selection: $appearancePreferenceRawValue
                ) {
                    ForEach(VolumeArcAppearancePreference.userSelectableCases) { preference in
                        Text(preference.displayName).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("profile.appearance.picker")
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.md)
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

    @ViewBuilder
    private func trainingPreferenceDestination(_ sheet: ProfileTrainingSheet) -> some View {
        switch sheet {
        case .coaching:
            CoachingPreferencesSheet(
                coachingStyle: model.athlete.coachingStyle,
                privacyMode: model.athlete.privacyMode
            ) { coachingStyle, privacyMode in
                saveProfileDefaults(coachingStyle: coachingStyle, privacyMode: privacyMode)
            }
        case .advancement:
            AdvancementPreferencesSheet(
                advancementLevel: model.athlete.advancementLevel,
                weeklyTrainingDays: model.athlete.weeklyTrainingDays
            ) { advancementLevel, weeklyTrainingDays in
                saveProfileDefaults(advancementLevel: advancementLevel, weeklyTrainingDays: weeklyTrainingDays)
            }
        case .equipment:
            EquipmentPreferencesSheet(selectedEquipment: model.athlete.availableEquipment) { equipment in
                saveProfileDefaults(availableEquipment: Array(equipment))
            }
        case .sessionProfiles:
            SessionProfilesSheet(
                athlete: model.athlete,
                activeProfileName: $activeSessionProfileName,
                saveDefaults: { sessionMinutes, weeklyDays in
                    saveProfileDefaults(sessionTimeBudgetMinutes: sessionMinutes, weeklyTrainingDays: weeklyDays)
                }
            )
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

    private var sessionProfilesRowValue: String {
        String(
            localized: "\(localizedSessionProfileName(activeSessionProfileName)), \(model.athlete.sessionTimeBudgetMinutes) min",
            comment: "Profile session profiles row value"
        )
    }

    private func localizedSessionProfileName(_ profile: String) -> String {
        localizedSessionProfileDisplayName(profile)
    }

    private var hasPremiumEntitlement: Bool {
        #if canImport(StoreKit)
        model.subscriptionStore?.isPremium ?? false
        #else
        false
        #endif
    }

    private var subscriptionBadgeText: String {
        hasPremiumEntitlement
            ? String(localized: "PREMIUM", comment: "Profile membership badge for active Premium")
            : String(localized: "FREE", comment: "Profile membership badge for free tier")
    }

    private var subscriptionTitle: String {
        hasPremiumEntitlement
            ? String(localized: "Premium Active", comment: "Profile subscription title for active Premium")
            : String(localized: "VolumeArc Premium", comment: "Profile subscription title for free users")
    }

    private var subscriptionSubtitle: String {
        hasPremiumEntitlement
            ? String(localized: "Manage billing with Apple", comment: "Profile subscription subtitle for active Premium")
            : String(localized: "Monthly / Yearly", comment: "Profile subscription subtitle for free users")
    }

    private var subscriptionActionTitle: String {
        hasPremiumEntitlement
            ? String(localized: "Manage", comment: "Profile manage subscription action")
            : String(localized: "Upgrade", comment: "Profile upgrade subscription action")
    }

    private var subscriptionAccessibilityLabel: String {
        hasPremiumEntitlement
            ? String(localized: "Manage Premium subscription", comment: "VoiceOver label for active Premium row")
            : String(localized: "Upgrade to Premium", comment: "VoiceOver label for the upgrade row")
    }

    private var subscriptionAccessibilityHint: String {
        hasPremiumEntitlement
            ? String(
                localized: "Opens Apple subscription management.",
                comment: "VoiceOver hint for the Premium manage row"
            )
            : String(
                localized: "Opens the paywall to start Premium.",
                comment: "VoiceOver hint for the upgrade row"
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

    private var appleAccountDisplayValue: String {
        let name = model.accountSession?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? String(localized: "Connected", comment: "Profile Apple account connected value")
            : name
    }

    private func profileRow(label: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            profileRowLabel(label: label, value: value, icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profileRowAccessibilityLabel(label: label, value: value))
        .accessibilityValue(value)
    }

    private func profileRowAccessibilityLabel(label: String, value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return label }
        return String(
            localized: "\(label), \(trimmedValue)",
            comment: "Profile row accessibility label with current setting value"
        )
    }

    private func saveProfileDefaults(
        name: String? = nil,
        coachingStyle: CoachingStyle? = nil,
        privacyMode: PrivacyMode? = nil,
        advancementLevel: AdvancementLevel? = nil,
        availableEquipment: [Equipment]? = nil,
        sessionTimeBudgetMinutes: Int? = nil,
        weeklyTrainingDays: Int? = nil
    ) {
        let defaults = UserProfileDefaults(
            name: name ?? model.athlete.name,
            coachingStyle: coachingStyle ?? model.athlete.coachingStyle,
            privacyMode: privacyMode ?? model.athlete.privacyMode,
            advancementLevel: advancementLevel ?? model.athlete.advancementLevel,
            availableEquipment: availableEquipment ?? Array(model.athlete.availableEquipment),
            preferredRepRangeLower: model.athlete.preferredRepRange.lowerBound,
            preferredRepRangeUpper: model.athlete.preferredRepRange.upperBound,
            sessionTimeBudgetMinutes: sessionTimeBudgetMinutes ?? model.athlete.sessionTimeBudgetMinutes,
            weeklyTrainingDays: weeklyTrainingDays ?? model.athlete.weeklyTrainingDays
        )
        Task {
            await model.updateProfile(defaults)
        }
    }

    private func handleSubscriptionAction() {
        VAHaptics.tap()
        guard hasPremiumEntitlement else {
            activeModal = .paywall
            return
        }

        model.recordSubscriptionManageOpened(source: "profile")
        guard !VolumeArcRuntimeFlags.suppressSubscriptionManageExternalURL else { return }
        guard let subscriptionManagementURL = Self.subscriptionManagementURL else { return }
        openURL(subscriptionManagementURL)
    }

    @MainActor
    private func refreshNotificationStatus() async {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = ProfileNotificationStatus(settings.authorizationStatus)
        #else
        notificationStatus = .unavailable
        #endif
    }

    @MainActor
    private func requestNotificationAuthorization() async -> Bool {
        guard let onRequestNotifications else { return false }
        let granted = await onRequestNotifications()
        await refreshNotificationStatus()
        if granted {
            activeModal = nil
        }
        return granted
    }

    #if canImport(AuthenticationServices)
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                accountStatusMessage = String(
                    localized: "Apple sign-in did not return a usable identity.",
                    comment: "Profile Apple sign-in unusable credential message"
                )
                return
            }
            let resolvedName = appleDisplayName(from: credential.fullName)
            accountStatusMessage = String(
                localized: "Apple ID connected.",
                comment: "Profile Apple sign-in success message"
            )
            Task {
                await model.connectAppleAccount(
                    userID: credential.user,
                    displayName: resolvedName,
                    email: credential.email
                )
            }
            VAHaptics.setLogged()
        case .failure:
            accountStatusMessage = String(
                localized: "Apple sign-in was canceled or could not complete.",
                comment: "Profile Apple sign-in failure message"
            )
            VAHaptics.warning()
        }
    }

    private func appleDisplayName(from components: PersonNameComponents?) -> String {
        guard let components else { return "" }
        return PersonNameComponentsFormatter.localizedString(from: components, style: .medium)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    private static let subscriptionManagementURL = URL(
        string: "https://apps.apple.com/account/subscriptions"
    )

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

struct ProfileAvatarImage: View {
    let imageData: Data?
    let initials: String
    let size: CGFloat
    let foreground: Color
    let background: Color

    var body: some View {
        ZStack {
            avatarContent
        }
        .frame(width: size, height: size)
        .background(background, in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatarContent: some View {
        #if canImport(UIKit)
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else {
            initialsContent
        }
        #else
        initialsContent
        #endif
    }

    private var initialsContent: some View {
        Text(initials)
            .font(VA.Typography.title2)
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
    }
}

enum ProfileAvatarStorage {
    static let storageKey = "volumearc.profileAvatar.imageData"

    static func normalizedAvatarData(from data: Data) -> Data? {
        #if canImport(UIKit)
        guard let sourceImage = UIImage(data: data) else { return nil }
        let side: CGFloat = 512
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let rendered = renderer.image { _ in
            let scale = max(side / sourceImage.size.width, side / sourceImage.size.height)
            let drawSize = CGSize(
                width: sourceImage.size.width * scale,
                height: sourceImage.size.height * scale
            )
            let origin = CGPoint(
                x: (side - drawSize.width) / 2,
                y: (side - drawSize.height) / 2
            )
            sourceImage.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
        #else
        return data
        #endif
    }
}

private struct AppleAccountDetailsSheet: View {
    let session: AccountSession?
    let editProfile: () -> Void
    let disconnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.xl) {
                    VACard(style: .glass) {
                        VStack(alignment: .leading, spacing: VA.Space.md) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(VA.Typography.display)
                                .foregroundStyle(VA.Colors.primary)
                                .accessibilityHidden(true)
                            Text(String(localized: "Apple ID connected", comment: "Apple account details title"))
                                .font(VA.Typography.title2)
                                .foregroundStyle(VA.Colors.textPrimary)
                            Text(String(
                                localized: """
                                    VolumeArc uses this identity for account continuity. Your training history \
                                    remains in your private iCloud data store.
                                    """,
                                comment: "Apple account details explanatory copy"
                            ))
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VACard(style: .flat) {
                        VStack(spacing: 0) {
                            detailRow(
                                title: String(localized: "Name", comment: "Apple account details name row"),
                                value: displayName
                            )
                            Divider()
                            detailRow(
                                title: String(localized: "Email", comment: "Apple account details email row"),
                                value: emailDisplay
                            )
                        }
                    }

                    VStack(spacing: VA.Space.md) {
                        VAButton(
                            String(localized: "Edit Profile", comment: "Apple account details edit profile action"),
                            icon: "person.crop.circle",
                            style: .primary,
                            accessibilityIdentifier: "profile.appleSignIn.editProfile"
                        ) {
                            editProfile()
                        }
                        VAButton(
                            String(localized: "Disconnect Apple ID", comment: "Apple account details disconnect action"),
                            icon: "xmark",
                            style: .destructive,
                            accessibilityIdentifier: "profile.appleSignIn.disconnect"
                        ) {
                            disconnect()
                        }
                    }
                }
                .padding(VA.Space.lg)
                .padding(.bottom, VA.Space.xxl)
            }
            .background(VA.Colors.surfaceGrouped)
            .navigationTitle(String(localized: "Account", comment: "Apple account details navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", comment: "Dismiss Apple account details")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("profile.appleSignIn.sheet")
    }

    private var displayName: String {
        let name = session?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? String(localized: "Not shared", comment: "Apple account details missing name")
            : name
    }

    private var emailDisplay: String {
        let email = session?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty
            ? String(localized: "Not shared", comment: "Apple account details missing email")
            : email
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VA.Space.md) {
            Text(title)
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textPrimary)
            Spacer(minLength: VA.Space.md)
            Text(value)
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, VA.Space.md)
    }
}

private enum ProfileNotificationStatus: Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case provisional
    case unavailable

    #if canImport(UserNotifications)
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional, .ephemeral:
            self = .provisional
        @unknown default:
            self = .unknown
        }
    }
    #endif

    var displayName: String {
        switch self {
        case .unknown:
            return String(localized: "Checking", comment: "Profile notification status")
        case .notDetermined:
            return String(localized: "Set up", comment: "Profile notification status")
        case .authorized:
            return String(localized: "Enabled", comment: "Profile notification status")
        case .denied:
            return String(localized: "Off", comment: "Profile notification status")
        case .provisional:
            return String(localized: "Quiet", comment: "Profile notification status")
        case .unavailable:
            return String(localized: "Unavailable", comment: "Profile notification status")
        }
    }
}

private struct FeedbackNavigationDestination: View {
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (FeedbackBundle.Category, String) -> Void

    var body: some View {
        FeedbackView(
            isPresented: Binding(
                get: { true },
                set: { isPresented in
                    if !isPresented {
                        dismiss()
                    }
                }
            ),
            onSubmit: onSubmit
        )
    }
}

private enum ProfileModal: Identifiable, Equatable {
    case editProfile
    case paywall
    case coachMemory
    case accountDetails
    case notificationRationale
    case training(ProfileTrainingSheet)

    var id: String {
        switch self {
        case .editProfile:
            return "editProfile"
        case .paywall:
            return "paywall"
        case .coachMemory:
            return "coachMemory"
        case .accountDetails:
            return "accountDetails"
        case .notificationRationale:
            return "notificationRationale"
        case let .training(sheet):
            return "training.\(sheet.rawValue)"
        }
    }
}

private enum ProfileTrainingSheet: String, Identifiable, Equatable {
    case coaching
    case advancement
    case equipment
    case sessionProfiles

    var id: String { rawValue }
}

private struct CoachingPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var coachingStyle: CoachingStyle
    @State private var privacyMode: PrivacyMode
    let save: (CoachingStyle, PrivacyMode) -> Void

    init(
        coachingStyle: CoachingStyle,
        privacyMode: PrivacyMode,
        save: @escaping (CoachingStyle, PrivacyMode) -> Void
    ) {
        _coachingStyle = State(initialValue: coachingStyle)
        _privacyMode = State(initialValue: privacyMode)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Coaching Style", comment: "Coaching preferences section title")) {
                    Picker(
                        String(localized: "Coaching style", comment: "Coaching style picker label"),
                        selection: $coachingStyle
                    ) {
                        ForEach(CoachingStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("profile.coaching.stylePicker")
                }

                Section(String(localized: "Privacy", comment: "Coaching privacy section title")) {
                    Picker(
                        String(localized: "Privacy mode", comment: "Privacy mode picker label"),
                        selection: $privacyMode
                    ) {
                        ForEach(PrivacyMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("profile.coaching.privacyPicker")
                    Text(privacyMode.footerDescription)
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
            }
            .navigationTitle(String(localized: "Coaching", comment: "Coaching preferences navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel coaching preferences")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("profile.coaching.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", comment: "Save coaching preferences")) {
                        save(coachingStyle, privacyMode)
                        VAHaptics.setLogged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("profile.coaching.save")
                }
            }
        }
        .accessibilityIdentifier("profile.coaching.sheet")
    }
}

private struct AdvancementPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var advancementLevel: AdvancementLevel
    @State private var weeklyTrainingDays: Int
    let save: (AdvancementLevel, Int) -> Void

    init(
        advancementLevel: AdvancementLevel,
        weeklyTrainingDays: Int,
        save: @escaping (AdvancementLevel, Int) -> Void
    ) {
        _advancementLevel = State(initialValue: advancementLevel)
        _weeklyTrainingDays = State(initialValue: weeklyTrainingDays)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Experience", comment: "Advancement preferences section title")) {
                    Picker(
                        String(localized: "Experience", comment: "Advancement level picker label"),
                        selection: $advancementLevel
                    ) {
                        ForEach(AdvancementLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section(String(localized: "Training Week", comment: "Training week section title")) {
                    Stepper(
                        String(
                            localized: "Training days: \(weeklyTrainingDays)",
                            comment: "Weekly training days stepper"
                        ),
                        value: $weeklyTrainingDays,
                        in: 1...7
                    )
                }
            }
            .navigationTitle(String(localized: "Advancement", comment: "Advancement preferences navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel advancement preferences")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", comment: "Save advancement preferences")) {
                        save(advancementLevel, weeklyTrainingDays)
                        VAHaptics.setLogged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier("profile.advancement.sheet")
    }
}

private struct EquipmentPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEquipment: Set<Equipment>
    let save: (Set<Equipment>) -> Void

    init(selectedEquipment: Set<Equipment>, save: @escaping (Set<Equipment>) -> Void) {
        _selectedEquipment = State(initialValue: selectedEquipment)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Available Equipment", comment: "Equipment preferences section title")) {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        Toggle(equipment.displayName, isOn: Binding(
                            get: { selectedEquipment.contains(equipment) },
                            set: { isOn in
                                if isOn {
                                    selectedEquipment.insert(equipment)
                                } else {
                                    selectedEquipment.remove(equipment)
                                }
                                VAHaptics.selection()
                            }
                        ))
                    }
                }
            }
            .navigationTitle(String(localized: "Equipment", comment: "Equipment preferences navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel equipment preferences")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", comment: "Save equipment preferences")) {
                        save(selectedEquipment.isEmpty ? [.bodyweight] : selectedEquipment)
                        VAHaptics.setLogged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier("profile.equipment.sheet")
    }
}

private struct SessionProfilesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var persistedActiveProfileName: String
    @AppStorage("volumearc.sessionProfiles.customNames")
    private var persistedCustomProfileNamesRaw = ""
    @AppStorage("volumearc.sessionProfiles.legDayRule")
    private var persistedIsLegDayRuleEnabled = false
    @AppStorage("volumearc.sessionProfiles.shortSessionRule")
    private var persistedIsShortSessionRuleEnabled = false
    @State private var activeProfileName = WorkoutSessionProfile.defaultProfile.rawValue
    @State private var customProfileNamesRaw = ""
    @State private var isLegDayRuleEnabled = false
    @State private var isShortSessionRuleEnabled = false
    @State private var newProfileName = ""
    @State private var sessionMinutes: Int
    @State private var weeklyTrainingDays: Int
    let saveDefaults: (Int, Int) -> Void

    private let builtInProfileNames = WorkoutSessionProfile.allCases.map(\.rawValue)

    init(
        athlete: AthleteProfile,
        activeProfileName: Binding<String>,
        saveDefaults: @escaping (Int, Int) -> Void
    ) {
        _persistedActiveProfileName = activeProfileName
        _sessionMinutes = State(initialValue: athlete.sessionTimeBudgetMinutes)
        _weeklyTrainingDays = State(initialValue: athlete.weeklyTrainingDays)
        self.saveDefaults = saveDefaults
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Active Profile", comment: "Session profile active section title")) {
                    Picker(
                        String(localized: "Active profile", comment: "Session profile picker label"),
                        selection: $activeProfileName
                    ) {
                        ForEach(profileNames, id: \.self) { profile in
                            Text(localizedProfileName(profile)).tag(profile)
                        }
                    }
                }

                Section(String(localized: "Profiles", comment: "Session profiles custom profile section title")) {
                    HStack(spacing: VA.Space.sm) {
                        TextField(
                            String(localized: "Profile name", comment: "Session profile new profile placeholder"),
                            text: $newProfileName
                        )
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("profile.sessionProfiles.newName")

                        Button {
                            addCustomProfile()
                        } label: {
                            Label(
                                String(localized: "Add profile", comment: "Session profile add button"),
                                systemImage: "plus.circle.fill"
                            )
                            .labelStyle(.iconOnly)
                        }
                        .disabled(!canAddCustomProfile)
                        .accessibilityLabel(String(localized: "Add profile", comment: "Session profile add button"))
                        .accessibilityIdentifier("profile.sessionProfiles.add")
                    }

                    ForEach(customProfileNames, id: \.self) { profile in
                        HStack(spacing: VA.Space.md) {
                            Text(profile)
                                .foregroundStyle(VA.Colors.textPrimary)
                            Spacer()
                            if profile == activeProfileName {
                                Text(String(localized: "Active", comment: "Session profile active custom marker"))
                                    .font(VA.Typography.caption)
                                    .foregroundStyle(VA.Colors.primary)
                            }
                            Button(role: .destructive) {
                                deleteCustomProfile(profile)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(String(
                                localized: "Delete \(profile)",
                                comment: "Session profile delete custom profile accessibility label"
                            ))
                            .accessibilityIdentifier("profile.sessionProfiles.delete")
                        }
                    }
                }

                Section(String(localized: "Default Session", comment: "Default session section title")) {
                    Picker(
                        String(localized: "Session length", comment: "Session profile length picker label"),
                        selection: $sessionMinutes
                    ) {
                        Text(String(localized: "30 min", comment: "Session length option")).tag(30)
                        Text(String(localized: "45 min", comment: "Session length option")).tag(45)
                        Text(String(localized: "60 min", comment: "Session length option")).tag(60)
                        Text(String(localized: "75 min", comment: "Session length option")).tag(75)
                        Text(String(localized: "90 min", comment: "Session length option")).tag(90)
                    }
                    Stepper(
                        String(
                            localized: "Training days: \(weeklyTrainingDays)",
                            comment: "Session profiles weekly days stepper"
                        ),
                        value: $weeklyTrainingDays,
                        in: 1...7
                    )
                }

                Section(String(localized: "Rules", comment: "Session profile rules section title")) {
                    Toggle(
                        String(localized: "Leg Day on Tuesday and Friday", comment: "Session profile weekday rule"),
                        isOn: $isLegDayRuleEnabled
                    )
                    .accessibilityIdentifier("profile.sessionProfiles.rule.legDay")
                    Toggle(
                        String(localized: "Short Session below 45 minutes", comment: "Session profile time rule"),
                        isOn: $isShortSessionRuleEnabled
                    )
                    .accessibilityIdentifier("profile.sessionProfiles.rule.shortSession")
                }
            }
            .navigationTitle(String(localized: "Session Profiles", comment: "Session profiles navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel session profiles")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", comment: "Save session profiles")) {
                        persistDrafts()
                        saveDefaults(sessionMinutes, weeklyTrainingDays)
                        VAHaptics.setLogged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier("profile.sessionProfiles.sheet")
        .onAppear {
            loadDrafts()
            normalizeActiveProfileName()
        }
    }

    private var profileNames: [String] {
        builtInProfileNames + customProfileNames.filter { !builtInProfileNames.contains($0) }
    }

    private var customProfileNames: [String] {
        customProfileNamesRaw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var normalizedNewProfileName: String {
        newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddCustomProfile: Bool {
        !normalizedNewProfileName.isEmpty
    }

    private func addCustomProfile() {
        guard canAddCustomProfile else { return }
        if let existingName = profileNames.first(where: { $0.caseInsensitiveCompare(normalizedNewProfileName) == .orderedSame }) {
            activeProfileName = existingName
            newProfileName = ""
            VAHaptics.tap()
            return
        }
        var names = customProfileNames
        names.append(normalizedNewProfileName)
        customProfileNamesRaw = names.joined(separator: "\n")
        activeProfileName = normalizedNewProfileName
        newProfileName = ""
        VAHaptics.setLogged()
    }

    private func deleteCustomProfile(_ profile: String) {
        let names = customProfileNames.filter { $0 != profile }
        customProfileNamesRaw = names.joined(separator: "\n")
        if activeProfileName == profile {
            activeProfileName = WorkoutSessionProfile.defaultProfile.rawValue
        }
        VAHaptics.warning()
    }

    private func localizedProfileName(_ profile: String) -> String {
        localizedSessionProfileDisplayName(profile)
    }

    private func loadDrafts() {
        activeProfileName = persistedActiveProfileName
        customProfileNamesRaw = persistedCustomProfileNamesRaw
        isLegDayRuleEnabled = persistedIsLegDayRuleEnabled
        isShortSessionRuleEnabled = persistedIsShortSessionRuleEnabled
    }

    private func persistDrafts() {
        persistedActiveProfileName = activeProfileName
        persistedCustomProfileNamesRaw = customProfileNamesRaw
        persistedIsLegDayRuleEnabled = isLegDayRuleEnabled
        persistedIsShortSessionRuleEnabled = isShortSessionRuleEnabled
    }

    private func normalizeActiveProfileName() {
        let parsed = WorkoutSessionProfile.parse(activeProfileName)
        if isBuiltInSessionProfileName(activeProfileName), activeProfileName != parsed.rawValue {
            activeProfileName = parsed.rawValue
        }
    }
}

private func localizedSessionProfileDisplayName(_ profile: String) -> String {
    let trimmedProfile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedProfile.isEmpty else {
        return WorkoutSessionProfile.defaultProfile.displayName
    }
    if isBuiltInSessionProfileName(trimmedProfile) {
        return WorkoutSessionProfile.parse(trimmedProfile).displayName
    }
    return trimmedProfile
}

private func isBuiltInSessionProfileName(_ profile: String) -> Bool {
    let normalized = profile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let builtInValues = WorkoutSessionProfile.allCases.map(\.rawValue)
    let legacyLabels = ["Default", "Leg Day", "Upper Strength", "Short Session"]
    return (builtInValues + legacyLabels).contains { $0.lowercased() == normalized }
}

private struct NotificationRationaleSheet: View {
    let status: ProfileNotificationStatus
    let requestAuthorization: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false
    @State private var requestFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.xl) {
                    VACard(style: .accent) {
                        VStack(alignment: .leading, spacing: VA.Space.md) {
                            Image(systemName: "bell.badge.fill")
                                .font(VA.Typography.display)
                                .foregroundStyle(VA.Colors.primary)
                                .accessibilityHidden(true)
                            Text(String(
                                localized: "Useful workout alerts only",
                                comment: "Notification rationale sheet title"
                            ))
                            .font(VA.Typography.title2)
                            .foregroundStyle(VA.Colors.textPrimary)
                            Text(String(
                                localized: """
                                    VolumeArc uses notifications for rest timers, scheduled-workout reminders, \
                                    and safety-relevant session status. It does not send pressure streaks or \
                                    generic marketing pushes.
                                    """,
                                comment: "Notification rationale sheet body"
                            ))
                            .font(VA.Typography.body)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: VA.Space.md) {
                        notificationUseRow(
                            icon: "timer",
                            title: String(localized: "Rest timers", comment: "Notification use row title"),
                            detail: String(
                                localized: "Know when a rest period is over without watching the screen.",
                                comment: "Notification use row detail"
                            )
                        )
                        notificationUseRow(
                            icon: "calendar.badge.clock",
                            title: String(localized: "Scheduled sessions", comment: "Notification use row title"),
                            detail: String(localized: "Get a reminder when a planned lift is ready today.", comment: "Notification use row detail")
                        )
                        notificationUseRow(
                            icon: "exclamationmark.shield.fill",
                            title: String(localized: "Session state", comment: "Notification use row title"),
                            detail: String(
                                localized: "Keep live workout state clear if the app is backgrounded.",
                                comment: "Notification use row detail"
                            )
                        )
                    }

                    if status == .denied {
                        Text(String(
                            localized: "Notifications are off in iOS Settings. Re-enable them there if you want workout alerts.",
                            comment: "Notification denied guidance"
                        ))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.warning)
                    } else {
                        VAButton(
                            isRequesting
                                ? String(localized: "Requesting", comment: "Notification request button loading label")
                                : String(localized: "Allow Notifications", comment: "Notification request button label"),
                            icon: "bell.fill",
                            style: .primary,
                            isLoading: isRequesting,
                            accessibilityIdentifier: "profile.notifications.allow"
                        ) {
                            Task {
                                isRequesting = true
                                requestFailed = !(await requestAuthorization())
                                isRequesting = false
                            }
                        }
                    }

                    if requestFailed {
                        Text(String(
                            localized: "Notifications were not enabled.",
                            comment: "Notification request failure message"
                        ))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.error)
                    }
                }
                .padding(VA.Space.lg)
            }
            .background(VA.Colors.surfaceGrouped)
            .navigationTitle(String(localized: "Notifications", comment: "Notification rationale navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done", comment: "Dismiss notification rationale sheet")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func notificationUseRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: VA.Space.md) {
            Image(systemName: icon)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.primary)
                .frame(width: 34, height: 34)
                .background(VA.Colors.primary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                Text(title)
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(detail)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
            }
        }
    }
}

private struct AboutVolumeArcView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VA.Space.xl) {
                heroCard
                privacyCard
                supportSection
                versionCard
            }
            .padding(VA.Space.lg)
            .padding(.bottom, VA.Space.xxl)
        }
        .background(VA.Colors.surfaceGrouped)
        .navigationTitle(String(localized: "About", comment: "About VolumeArc navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("profile.about.root")
    }

    private var heroCard: some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(VA.Typography.display)
                    .foregroundStyle(VA.Colors.primary)
                    .accessibilityHidden(true)
                Text(String(localized: "VolumeArc", comment: "About screen product name"))
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(String(
                    localized: "Apple-native strength coaching for iPhone and Apple Watch.",
                    comment: "About screen product description"
                ))
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyCard: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.lg) {
                Text(String(localized: "Privacy posture", comment: "About privacy card title"))
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)

                AboutFactRow(
                    icon: "heart.text.square.fill",
                    title: String(localized: "Health data", comment: "About privacy fact title"),
                    detail: String(
                        localized: "Raw Apple Health data stays in Apple Health. VolumeArc uses computed training signals.",
                        comment: "About privacy fact detail"
                    )
                )
                AboutFactRow(
                    icon: "brain.head.profile",
                    title: String(localized: "Cloud Coach", comment: "About privacy fact title"),
                    detail: String(
                        localized: "Strict privacy mode redacts profile and free-text details before coach prompts leave the device.",
                        comment: "About privacy fact detail"
                    )
                )
                AboutFactRow(
                    icon: "camera.viewfinder",
                    title: String(localized: "Form Check", comment: "About privacy fact title"),
                    detail: String(
                        localized: "Camera form analysis uses on-device Vision landmarks and lift heuristics.",
                        comment: "About privacy fact detail"
                    )
                )
            }
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(String(localized: "Support", comment: "About support section title").uppercased())
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.4)
                .padding(.horizontal, VA.Space.xs)

            VStack(spacing: 0) {
                if let supportURL = URL(string: "https://volumearc.app/support") {
                    AboutActionRow(
                        icon: "lifepreserver.fill",
                        title: String(localized: "Support", comment: "About support link title"),
                        detail: String(localized: "Get help or send feedback", comment: "About support link detail")
                    ) {
                        openURL(supportURL)
                    }
                    Divider()
                }
                AboutActionRow(
                    icon: "hand.raised.fill",
                    title: String(localized: "Privacy Policy", comment: "About privacy link title"),
                    detail: String(localized: "How VolumeArc handles data", comment: "About privacy link detail")
                ) {
                    openURL(LegalLinks.privacyPolicy)
                }
                Divider()
                AboutActionRow(
                    icon: "doc.text.fill",
                    title: String(localized: "Terms of Service", comment: "About terms link title"),
                    detail: String(localized: "Subscription and service terms", comment: "About terms link detail")
                ) {
                    openURL(LegalLinks.termsOfService)
                }
            }
            .background(VA.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous)
                    .stroke(VA.Colors.textTertiary.opacity(0.14), lineWidth: 0.5)
            }
        }
    }

    private var versionCard: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "Build", comment: "About build card title"))
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(versionDisplay)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                Text(bundleIdentifierDisplay)
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textTertiary)
                    .textSelection(.enabled)
            }
        }
    }

    private var versionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return String(localized: "Version \(version) (\(build))", comment: "About screen app version and build")
    }

    private var bundleIdentifierDisplay: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mabryventures.VolumeArc"
        return String(localized: "Bundle \(bundleID)", comment: "About screen app bundle identifier")
    }
}

private struct AboutFactRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: VA.Space.md) {
            Image(systemName: icon)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.primary)
                .frame(width: 34, height: 34)
                .background(VA.Colors.primary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                Text(title)
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(detail)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AboutActionRow: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VA.Space.md) {
                Image(systemName: icon)
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        VA.Colors.primary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(title)
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(detail)
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer(minLength: VA.Space.sm)
                Image(systemName: "arrow.up.right")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, VA.Space.lg)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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

private func profileLocalizedTypeCount(_ count: Int) -> String {
    vaInflectedString("^[\(count) type](inflect: true)", comment: "Profile equipment type count")
}

private func profileLocalizedNoteCount(_ count: Int) -> String {
    vaInflectedString("^[\(count) note](inflect: true)", comment: "Profile coach memory note count")
}
#endif
