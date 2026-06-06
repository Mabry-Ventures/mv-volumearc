#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
import VolumeArcCore

// swiftlint:disable file_length

/// First-run onboarding experience.
/// 6 steps: welcome → profile → preferences → coaching style → permissions → done.
public struct OnboardingView: View { // swiftlint:disable:this type_body_length
    @Binding var isPresented: Bool
    let onComplete: (OnboardingResult) -> Void
    /// VOL-109: callback that fires the Apple Health authorization
    /// prompt when the user taps "Connect Apple Health" on the
    /// permissions step. Returns `true` if the system reported a
    /// successful authorization request (regardless of which scopes the
    /// user toggled on; HealthKit doesn't disclose per-type grant
    /// state). Optional so existing call sites that don't yet wire the
    /// callback keep compiling — a missing callback degrades the step
    /// to "informational only, just tap Continue to advance".
    let onRequestHealthAuthorization: (() async -> Bool)?
    let onRequestNotificationAuthorization: (() async -> Bool)?
    let onConnectAppleAccount: ((OnboardingAppleAccount) async -> Void)?
    let onResumeFromSavedProgress: ((Int) -> Void)?

    @State private var step: Step
    @State private var result: OnboardingResult
    /// VOL-109: tracked locally so the permissions step can show a
    /// "Connected" affordance after the prompt closes. Doesn't drive
    /// any business logic — Continue advances unconditionally — so a
    /// "false" value just means we don't change the button label.
    @State private var healthAuthorizationDidComplete: Bool
    @State private var notificationAuthorizationDidComplete: Bool
    @State private var appleAccountDidConnect = false
    @State private var appleAccountStatusMessage: String?
    @State private var didRecordResumeTelemetry = false

    public init(
        isPresented: Binding<Bool>,
        onComplete: @escaping (OnboardingResult) -> Void,
        onRequestHealthAuthorization: (() async -> Bool)? = nil,
        onRequestNotificationAuthorization: (() async -> Bool)? = nil,
        onConnectAppleAccount: ((OnboardingAppleAccount) async -> Void)? = nil,
        onResumeFromSavedProgress: ((Int) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.onComplete = onComplete
        self.onRequestHealthAuthorization = onRequestHealthAuthorization
        self.onRequestNotificationAuthorization = onRequestNotificationAuthorization
        self.onConnectAppleAccount = onConnectAppleAccount
        self.onResumeFromSavedProgress = onResumeFromSavedProgress
        self._step = State(initialValue: Self.initialStep())
        self._result = State(initialValue: OnboardingResult())
        self._healthAuthorizationDidComplete = State(initialValue: false)
        self._notificationAuthorizationDidComplete = State(initialValue: false)
    }

    @_spi(Testing) public init(
        isPresented: Binding<Bool>,
        onComplete: @escaping (OnboardingResult) -> Void,
        onRequestHealthAuthorization: (() async -> Bool)? = nil,
        onRequestNotificationAuthorization: (() async -> Bool)? = nil,
        onConnectAppleAccount: ((OnboardingAppleAccount) async -> Void)? = nil,
        onResumeFromSavedProgress: ((Int) -> Void)? = nil,
        snapshotStep: OnboardingSnapshotStep,
        snapshotResult: OnboardingResult = OnboardingResult(),
        snapshotHealthAuthorizationDidComplete: Bool = false,
        // swiftlint:disable:next identifier_name
        snapshotNotificationAuthorizationDidComplete: Bool = false
    ) {
        self._isPresented = isPresented
        self.onComplete = onComplete
        self.onRequestHealthAuthorization = onRequestHealthAuthorization
        self.onRequestNotificationAuthorization = onRequestNotificationAuthorization
        self.onConnectAppleAccount = onConnectAppleAccount
        self.onResumeFromSavedProgress = onResumeFromSavedProgress
        self._step = State(initialValue: Step(snapshotStep: snapshotStep))
        self._result = State(initialValue: snapshotResult)
        self._healthAuthorizationDidComplete = State(initialValue: snapshotHealthAuthorizationDidComplete)
        self._notificationAuthorizationDidComplete = State(initialValue: snapshotNotificationAuthorizationDidComplete)
    }

    public var body: some View {
        VStack(spacing: 0) {
            onboardingRootMarker
            currentStepMarker
            progressBar
            // VOL-115: wrap the step content in a ScrollView so that text
            // fields inside the profile step can be scrolled past the
            // keyboard, and the action row stays reachable. Pinning the
            // action row outside the ScrollView keeps Continue / Get
            // Started always-visible regardless of step content height.
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: VA.Space.xl)
                    stepContent
                        .padding(VA.Space.xl)
                    Spacer(minLength: VA.Space.xl)
                }
                .frame(maxWidth: .infinity)
            }
            // VOL-115: pin the action row's background through the VA
            // design-system Liquid Glass token (`vaGlassBackground`)
            // instead of a hardcoded `.ultraThinMaterial`. Hits the same
            // visual result on iOS 26 (`Glass.regular`) but routes through
            // the shared modifier that handles
            // `accessibilityReduceTransparency` fallback to a solid VA
            // surface fill — keeps the design-system contract intact.
            actionRow
                .padding(VA.Space.lg)
                .vaGlassBackground(in: Rectangle())
        }
        .background(
            LinearGradient(
                colors: [
                    VA.Colors.primary.opacity(0.15),
                    VA.Colors.surfaceSecondary
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .task {
            guard !didRecordResumeTelemetry,
                  let savedStepRaw = OnboardingProgressStore.loadStepRaw(),
                  let savedStep = Step(rawValue: savedStepRaw),
                  savedStep != .welcome else { return }
            didRecordResumeTelemetry = true
            onResumeFromSavedProgress?(savedStep.rawValue)
        }
    }

    // MARK: - Progress bar

    private var onboardingRootMarker: some View {
        // VOL-122 CI hardening: keep the root identifier on a dedicated
        // semantic marker. Attaching it to the outer VStack propagates the
        // identifier to buttons on some SwiftUI runtimes; attaching it to
        // the 4pt progress bar can disappear from the accessibility tree
        // at AX5 on CI.
        Text(String(localized: "Onboarding", comment: "Accessibility label for the onboarding root marker"))
            .font(.caption2)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("onboarding.root")
            .accessibilityLabel(String(localized: "Onboarding", comment: "Accessibility label for the onboarding root marker"))
    }

    private var currentStepMarker: some View {
        Text(verbatim: "\(step.rawValue)")
            .font(.caption2)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("onboarding.step.\(step.rawValue)")
            .accessibilityLabel(Text(verbatim: "\(step.rawValue)"))
    }

    private var progressBar: some View {
        HStack(spacing: VA.Space.xs) {
            ForEach(Step.allCases, id: \.self) { s in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(s.rawValue <= step.rawValue ? VA.Colors.primary : VA.Colors.surfaceTertiary)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, VA.Space.lg)
        .padding(.top, VA.Space.lg)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .profile: profileStep
        case .preferences: preferencesStep
        case .coachingStyle: coachingStyleStep
        case .permissions: permissionsStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: VA.Space.xl) {
            onboardingHeroPanel
                .vaAppear()

            VStack(spacing: VA.Space.md) {
                Text(String(localized: "Welcome to VolumeArc", comment: "Onboarding welcome step title"))
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                // VOL-247 (copy pass): tightened the prior 19-word verbose
                // copy to 11-word coach-voice — same promise, less padding.
                Text(String(
                    localized: "A strength coach that adapts to your recovery and guides every set.",
                    comment: "Onboarding welcome step description"
                ))
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: VA.Space.onboardingMaxWidth)
            }

            onboardingProofPanel
        }
    }

    private var onboardingProofPanel: some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                OnboardingProofRow(
                    icon: "applewatch",
                    title: String(localized: "Watch-first execution", comment: "Onboarding proof row title"),
                    detail: String(localized: "Start, log, rest, and recover without breaking focus.", comment: "Onboarding proof row detail")
                )
                OnboardingProofRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: String(localized: "Readiness-aware training", comment: "Onboarding proof row title"),
                    detail: String(localized: "Your plan adapts when recovery says to back off.", comment: "Onboarding proof row detail")
                )
                OnboardingProofRow(
                    icon: "lock.shield.fill",
                    title: String(localized: "Private by design", comment: "Onboarding proof row title"),
                    detail: String(localized: "Health data stays on-device unless you choose Cloud Coach.", comment: "Onboarding proof row detail")
                )
            }
        }
        .frame(maxWidth: VA.Space.onboardingMaxWidth)
    }

    private var onboardingHeroPanel: some View {
        ZStack(alignment: .topLeading) {
            VA.Gradients.sunriseHero
            VStack(alignment: .leading, spacing: VA.Space.lg) {
                HStack(alignment: .center, spacing: VA.Space.md) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(VA.Typography.title)
                        .foregroundStyle(VA.Colors.textOnPrimary)
                        .frame(width: VA.Space.ctaIllustration, height: VA.Space.ctaIllustration)
                        .background(VA.Colors.textOnPrimary.opacity(VA.Opacity.iconPanelPrimary), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(String(localized: "Today", comment: "Onboarding hero mini dashboard label"))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textOnPrimary.opacity(VA.Opacity.textMutedOnPrimary))
                        Text(String(localized: "Upper Strength", comment: "Onboarding hero sample workout title"))
                            .font(VA.Typography.title2)
                            .foregroundStyle(VA.Colors.textOnPrimary)
                    }
                    Spacer(minLength: VA.Space.sm)
                    Text(String(localized: "84", comment: "Onboarding hero sample readiness score"))
                        .font(VA.Typography.display)
                        .foregroundStyle(VA.Colors.textOnPrimary)
                        .monospacedDigit()
                }

                HStack(spacing: VA.Space.sm) {
                    onboardingHeroStat(
                        title: String(localized: "Next set", comment: "Onboarding hero stat title"),
                        value: String(localized: "Back Squat", comment: "Onboarding hero stat value")
                    )
                    onboardingHeroStat(
                        title: String(localized: "Target", comment: "Onboarding hero stat title"),
                        value: String(localized: "225 x 5", comment: "Onboarding hero stat value")
                    )
                    onboardingHeroStat(
                        title: String(localized: "Watch", comment: "Onboarding hero stat title"),
                        value: String(localized: "Ready", comment: "Onboarding hero stat value")
                    )
                }
            }
            .padding(VA.Space.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous)
                .stroke(VA.Colors.textOnPrimary.opacity(VA.Opacity.strokeOnPrimary), lineWidth: VA.Space.border)
        }
        .vaShadow(.lg)
        .frame(maxWidth: VA.Space.onboardingMaxWidth)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "VolumeArc sample training dashboard. Readiness 84. Upper Strength. Back Squat 225 by 5.",
            comment: "Onboarding hero accessibility summary"
        ))
    }

    private func onboardingHeroStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(title)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textOnPrimary.opacity(VA.Opacity.textMutedOnPrimary))
                .lineLimit(1)
            Text(value)
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textOnPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VA.Space.sm)
        .padding(.vertical, VA.Space.xs)
        .background(
            VA.Colors.textOnPrimary.opacity(VA.Opacity.iconPanelPrimary),
            in: RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
        )
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: VA.Space.xl) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "Tell me about you", comment: "Onboarding profile step title"))
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(String(
                    localized: "I'll use this to personalize your training.",
                    comment: "Onboarding profile step subtitle"
                ))
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "Your name", comment: "Onboarding profile step — name field label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                TextField(
                    String(localized: "First name", comment: "Onboarding profile step — name field placeholder"),
                    text: $result.name
                )
                    .textFieldStyle(.plain)
                    .font(VA.Typography.title2)
                    .padding(VA.Space.md)
                    .vaInteractiveGlassBackground(
                        in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                    )
            }

            appleAccountCard

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "Experience level", comment: "Onboarding profile step — experience level label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                ForEach(AdvancementLevel.allCases, id: \.self) { level in
                    selectionRow(
                        title: level.displayName,
                        subtitle: levelDescription(level),
                        isSelected: result.advancementLevel == level
                    ) {
                        result.advancementLevel = level
                        VAHaptics.selection()
                    }
                }
            }
        }
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: VA.Space.xl) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "Training preferences", comment: "Onboarding preferences step title"))
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(String(localized: "How often can you train?", comment: "Onboarding preferences step subtitle"))
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "Days per week", comment: "Onboarding preferences — days per week field label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                HStack(spacing: VA.Space.sm) {
                    ForEach(2...6, id: \.self) { days in
                        Button {
                            result.weeklyDays = days
                            VAHaptics.selection()
                        } label: {
                            Text("\(days)")
                                .font(VA.Typography.title2)
                                .foregroundStyle(result.weeklyDays == days ? VA.Colors.textOnPrimary : VA.Colors.textPrimary)
                                .frame(width: 56, height: 56)
                                .background(result.weeklyDays == days ? VA.Colors.primary : Color.clear)
                                .overlay {
                                    Circle().stroke(VA.Colors.primary.opacity(0.4), lineWidth: 2)
                                }
                                .clipShape(Circle())
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "Session time budget", comment: "Onboarding preferences — session length field label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                Picker("", selection: $result.sessionMinutes) {
                    Text(String(localized: "30 min", comment: "Session length option — 30 minutes")).tag(30)
                    Text(String(localized: "45 min", comment: "Session length option — 45 minutes")).tag(45)
                    Text(String(localized: "60 min", comment: "Session length option — 60 minutes")).tag(60)
                    Text(String(localized: "75 min", comment: "Session length option — 75 minutes")).tag(75)
                    Text(String(localized: "90 min", comment: "Session length option — 90 minutes")).tag(90)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var coachingStyleStep: some View {
        VStack(alignment: .leading, spacing: VA.Space.xl) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "Pick a coaching voice", comment: "Onboarding coaching style step title"))
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(String(
                    localized: "You can change this anytime in settings.",
                    comment: "Onboarding coaching style step subtitle"
                ))
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "Coach voice", comment: "Onboarding coaching style section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                ForEach(CoachingStyle.allCases, id: \.self) { style in
                    selectionRow(
                        title: style.displayName,
                        subtitle: style.displayDescription,
                        isSelected: result.coachingStyle == style
                    ) {
                        result.coachingStyle = style
                        VAHaptics.selection()
                    }
                }
            }

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "Cloud coach privacy", comment: "Onboarding privacy mode section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                ForEach(PrivacyMode.allCases, id: \.self) { mode in
                    selectionRow(
                        title: mode.displayName,
                        subtitle: mode.footerDescription,
                        isSelected: result.privacyMode == mode
                    ) {
                        result.privacyMode = mode
                        VAHaptics.selection()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appleAccountCard: some View {
        #if canImport(AuthenticationServices)
        if onConnectAppleAccount != nil {
            VACard(style: .glass) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    HStack(alignment: .top, spacing: VA.Space.sm) {
                        Image(systemName: appleAccountDidConnect ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                            .font(VA.Typography.title2)
                            .foregroundStyle(VA.Colors.primary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: VA.Space.xxs) {
                            Text(String(
                                localized: "Keep your profile in sync",
                                comment: "Onboarding Apple account card title"
                            ))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                            Text(appleAccountSupportingCopy)
                                .font(VA.Typography.footnote)
                                .foregroundStyle(VA.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if appleAccountDidConnect {
                        Label {
                            Text(String(
                                localized: "Apple ID connected",
                                comment: "Onboarding Apple account connected status"
                            ))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .accessibilityHidden(true)
                        }
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.success)
                        .accessibilityIdentifier("onboarding.appleSignIn.connected")
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                        .accessibilityIdentifier("onboarding.appleSignIn")
                    }

                    if let appleAccountStatusMessage {
                        Text(appleAccountStatusMessage)
                            .font(VA.Typography.caption)
                            .foregroundStyle(appleAccountDidConnect ? VA.Colors.success : VA.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboarding.appleSignIn.status")
                    }
                }
            }
            .frame(maxWidth: VA.Space.onboardingMaxWidth)
        }
        #endif
    }

    private var appleAccountSupportingCopy: String {
        if appleAccountDidConnect {
            return String(
                localized: "Profile identity is ready. Training data and preferences sync through your private iCloud database.",
                comment: "Onboarding Apple account connected supporting copy"
            )
        }
        return String(
            localized: "Use Apple ID to seed your profile. Training data and preferences sync through your private iCloud database.",
            comment: "Onboarding Apple account supporting copy"
        )
    }

    #if canImport(AuthenticationServices)
    private func handleAppleSignIn(_ authorizationResult: Result<ASAuthorization, Error>) {
        switch authorizationResult {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleAccountStatusMessage = String(
                    localized: "Apple sign-in did not return a usable identity.",
                    comment: "Onboarding Apple sign-in unusable credential message"
                )
                VAHaptics.warning()
                return
            }

            let displayName = appleDisplayName(from: credential.fullName)
            if result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               displayName.isEmpty == false {
                result.name = displayName
            }

            appleAccountStatusMessage = String(
                localized: "Apple ID connected.",
                comment: "Onboarding Apple sign-in success message"
            )
            appleAccountDidConnect = true
            Task {
                await onConnectAppleAccount?(OnboardingAppleAccount(
                    userID: credential.user,
                    displayName: displayName,
                    email: credential.email
                ))
            }
            VAHaptics.setLogged()
        case .failure:
            appleAccountStatusMessage = String(
                localized: "Apple sign-in was canceled or could not complete.",
                comment: "Onboarding Apple sign-in failure message"
            )
            appleAccountDidConnect = false
            VAHaptics.warning()
        }
    }

    private func appleDisplayName(from components: PersonNameComponents?) -> String {
        guard let components else { return "" }
        return PersonNameComponentsFormatter.localizedString(from: components, style: .medium)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    /// VOL-109 + VOL-127: Apple Health permission step that doubles
    /// as the custom rationale screen presented BEFORE the system
    /// prompt fires. Optional connect — the Continue button advances
    /// to `.done` regardless of grant state. The "Connect Apple
    /// Health" button triggers the system prompt via
    /// `onRequestHealthAuthorization` (when wired by the host);
    /// after HealthKit reports a successful authorization request
    /// the button shows "Connected" and is disabled. Denial /
    /// failure leaves the button available so the user can retry or
    /// continue without connecting.
    ///
    /// VOL-127 expanded the rationale body to break out the four
    /// facts a user needs to make an informed decision: what is
    /// read, why we read it, what stays on-device, and what syncs
    /// to iCloud (Apple's private database — not our cloud). The
    /// audit's UAT-readiness checklist required this content
    /// surface before tester invitation.
    private var permissionsStep: some View {
        VStack(spacing: VA.Space.xl) {
            Image(systemName: "heart.text.square.fill")
                .font(VA.Typography.onboardingIcon)
                .foregroundStyle(VA.Colors.primary)
                .vaAppear()

            VStack(spacing: VA.Space.md) {
                Text(String(
                    localized: "Connect Apple Health",
                    comment: "Onboarding permissions step title"
                ))
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
                .multilineTextAlignment(.center)

                // VOL-127: structured rationale per the audit's UAT
                // criteria. Four bullets cover: data read, why, on-
                // device storage guarantee, iCloud sync destination.
                VStack(alignment: .leading, spacing: VA.Space.sm) {
                    healthRationaleBullet(
                        symbol: "figure.strengthtraining.traditional",
                        text: String(
                            localized: """
                            Reads workouts, heart rate variability (HRV), sleep, Workout \
                            Effort, wrist temperature, respiratory rate, and Apple Watch \
                            session signals to chart your training history.
                            """,
                            comment: "Onboarding permissions step — what HealthKit data VolumeArc reads"
                        )
                    )
                    healthRationaleBullet(
                        symbol: "sparkles",
                        // VOL-247 (copy pass): replaced "Coach prescription"
                        // jargon with everyday language.
                        text: String(
                            localized: """
                            Your coach uses your recent workouts and recovery \
                            signals to suggest the next session.
                            """,
                            comment: "Onboarding permissions step — why VolumeArc needs the HealthKit data"
                        )
                    )
                    healthRationaleBullet(
                        symbol: "iphone.gen3",
                        text: String(
                            localized: """
                            Raw HealthKit data stays in Apple Health on this device. \
                            If you use Cloud Coach, only computed aggregates leave \
                            with your consent.
                            """,
                            comment: "Onboarding permissions step — on-device storage guarantee"
                        )
                    )
                    healthRationaleBullet(
                        symbol: "icloud",
                        text: String(
                            localized: """
                            Workouts you save sync to your private iCloud database \
                            (not ours). Revoke anytime in Settings → Privacy → Health.
                            """,
                            comment: "Onboarding permissions step — CloudKit private database + revocation guidance"
                        )
                    )
                }
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textSecondary)
                .frame(maxWidth: VA.Space.onboardingMaxWidth, alignment: .leading)
            }

            if onRequestHealthAuthorization != nil {
                healthConnectButton
                    .frame(maxWidth: VA.Space.onboardingMaxWidth)
                    .disabled(healthAuthorizationDidComplete)
            }

            if onRequestNotificationAuthorization != nil {
                VACard(style: .glass) {
                    VStack(alignment: .leading, spacing: VA.Space.md) {
                        HStack(alignment: .top, spacing: VA.Space.sm) {
                            Image(systemName: "bell.badge.fill")
                                .font(VA.Typography.title2)
                                .foregroundStyle(VA.Colors.primary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                                Text(String(
                                    localized: "Workout reminders",
                                    comment: "Onboarding notification permission card title"
                                ))
                                .font(VA.Typography.headline)
                                .foregroundStyle(VA.Colors.textPrimary)
                                Text(String(
                                    localized: """
                                    VolumeArc can send rest-timer alerts and scheduled-workout nudges. \
                                    No streak guilt, no marketing pushes.
                                    """,
                                    comment: "Onboarding notification permission rationale"
                                ))
                                .font(VA.Typography.footnote)
                                .foregroundStyle(VA.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        VAButton(
                            notificationAuthorizationDidComplete
                                ? String(
                                    localized: "Notifications Enabled",
                                    comment: "Onboarding notification permission enabled button label"
                                )
                                : String(
                                    localized: "Allow Workout Notifications",
                                    comment: "Onboarding notification permission request button label"
                                ),
                            icon: notificationAuthorizationDidComplete ? "checkmark.circle.fill" : "bell.fill",
                            style: notificationAuthorizationDidComplete ? .ghost : .secondary,
                            accessibilityIdentifier: "onboarding.permissions.notifications"
                        ) {
                            Task {
                                VAHaptics.tap()
                                let granted = await onRequestNotificationAuthorization?() ?? false
                                notificationAuthorizationDidComplete = granted
                            }
                        }
                        .disabled(notificationAuthorizationDidComplete)
                    }
                }
                .frame(maxWidth: VA.Space.onboardingMaxWidth)
            }

            Text(String(
                localized: "You can change these anytime from Profile.",
                comment: "Onboarding permissions step footer pointing the user to Profile settings"
            ))
            .font(VA.Typography.footnote)
            .foregroundStyle(VA.Colors.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: VA.Space.onboardingMaxWidth)
        }
    }

    private var healthConnectButton: some View {
        Button {
            Task {
                VAHaptics.tap()
                let granted = await onRequestHealthAuthorization?() ?? false
                healthAuthorizationDidComplete = granted
            }
        } label: {
            HStack(spacing: VA.Space.md) {
                Image(systemName: healthAuthorizationDidComplete ? "checkmark.circle.fill" : "heart.text.square.fill")
                    .font(VA.Typography.title2)
                    .foregroundStyle(healthConnectForeground)
                    .frame(width: VA.Space.iconBadge, height: VA.Space.iconBadge)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(healthConnectTitle)
                        .font(VA.Typography.headline)
                        .foregroundStyle(healthConnectForeground)
                    Text(healthConnectSubtitle)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(healthConnectSecondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: VA.Space.sm)
                Image(systemName: healthAuthorizationDidComplete ? "lock.shield.fill" : "arrow.up.right")
                    .font(VA.Typography.buttonIcon)
                    .foregroundStyle(healthConnectSecondaryForeground)
                    .accessibilityHidden(true)
            }
            .padding(VA.Space.lg)
            .background(healthConnectBackground)
            .clipShape(RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous)
                    .stroke(healthConnectStroke, lineWidth: VA.Space.border)
            }
            .vaShadow(healthAuthorizationDidComplete ? .sm : .md)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(healthConnectAccessibilityLabel)
        .accessibilityHint(healthConnectSubtitle)
        .accessibilityIdentifier("onboarding.permissions.connect-health")
    }

    private var healthConnectTitle: String {
        healthAuthorizationDidComplete
            ? String(
                localized: "Apple Health Connected",
                comment: "Onboarding permissions connected Health button title"
            )
            : String(
                localized: "Connect Apple Health",
                comment: "Onboarding permissions Health button title"
            )
    }

    private var healthConnectSubtitle: String {
        healthAuthorizationDidComplete
            ? String(
                localized: "Recovery signals are ready for training guidance.",
                comment: "Onboarding permissions connected Health button subtitle"
            )
            : String(
                localized: "Use recovery, sleep, and workout history to tune every session.",
                comment: "Onboarding permissions Health button subtitle"
            )
    }

    private var healthConnectAccessibilityLabel: String {
        healthAuthorizationDidComplete
            ? String(
                localized: "Connected",
                comment: "Onboarding permissions connected Health button accessibility label"
            )
            : String(
                localized: "Connect Apple Health",
                comment: "Onboarding permissions Health button accessibility label"
            )
    }

    private var healthConnectForeground: Color {
        healthAuthorizationDidComplete ? VA.Colors.textPrimary : VA.Colors.textOnPrimary
    }

    private var healthConnectSecondaryForeground: Color {
        healthAuthorizationDidComplete
            ? VA.Colors.textSecondary
            : VA.Colors.textOnPrimary.opacity(VA.Opacity.textSecondaryOnPrimary)
    }

    @ViewBuilder
    private var healthConnectBackground: some View {
        if healthAuthorizationDidComplete {
            VA.Colors.surfacePrimary
        } else {
            VA.Gradients.sunriseHero
        }
    }

    private var healthConnectStroke: Color {
        healthAuthorizationDidComplete
            ? VA.Colors.success.opacity(VA.Opacity.strokeOnPrimary)
            : VA.Colors.textOnPrimary.opacity(VA.Opacity.strokeOnPrimary)
    }

    /// VOL-127: SF Symbol + body row for the structured HealthKit
    /// rationale bullets. Kept private to OnboardingView because it's
    /// only used by `permissionsStep`; promoting it to a public VAUI
    /// component would invite reuse outside the onboarding context
    /// before we've decided whether bulleted-icon rows are part of the
    /// design system proper.
    private func healthRationaleBullet(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: VA.Space.sm) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(VA.Colors.primary)
                .frame(width: VA.Space.lg, alignment: .center)
                .accessibilityHidden(true)
            Text(text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var doneStep: some View {
        VStack(spacing: VA.Space.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(VA.Typography.onboardingIcon)
                .foregroundStyle(VA.Colors.success)
                .vaAppear()

            VStack(spacing: VA.Space.md) {
                Text(String(localized: "You're all set", comment: "Onboarding done step title"))
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(doneStepSubtitle)
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: VA.Space.onboardingMaxWidth)
            }
        }
    }

    private var doneStepSubtitle: String {
        if result.name.isEmpty {
            return String(
                localized: "Let's build your first session.",
                comment: "Onboarding done step subtitle when no name was entered"
            )
        } else {
            return String(
                localized: "\(result.name), let's build your first session.",
                comment: "Onboarding done step subtitle addressing the user by name"
            )
        }
    }

    // MARK: - Helpers

    private func selectionRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: VA.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(subtitle)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? VA.Colors.primary : VA.Colors.textTertiary)
            }
            .padding(VA.Space.lg)
            .modifier(OnboardingSelectionRowBackgroundModifier(isSelected: isSelected))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                        .stroke(VA.Colors.primary, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func levelDescription(_ level: AdvancementLevel) -> String {
        switch level {
        case .beginner:
            return String(
                localized: "Less than 1 year of consistent lifting",
                comment: "Advancement level description — beginner"
            )
        case .intermediate:
            return String(
                localized: "1-3 years, comfortable with the major lifts",
                comment: "Advancement level description — intermediate"
            )
        case .advanced:
            return String(
                localized: "3+ years, refined technique and periodization",
                comment: "Advancement level description — advanced"
            )
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: VA.Space.md) {
            if step != .welcome {
                VAButton(
                    String(localized: "Back", comment: "Onboarding back button"),
                    style: .ghost,
                    // VOL-93: identifier threaded through VAButton's init so it
                    // attaches to the combined accessibility element rather
                    // than the outer modifier wrapper.
                    accessibilityIdentifier: "onboarding.back"
                ) {
                    withAnimation(VAAnimation.standard) {
                        saveStep(Step(rawValue: step.rawValue - 1) ?? .welcome)
                    }
                }
                .frame(maxWidth: 100)
            }

            // VOL-93: on the final step the button says "Get Started"; on
            // every other step it says "Continue". The identifier changes
            // with the step so the test can distinguish the final commit
            // from intermediate taps. Threaded through VAButton's init so
            // it attaches to the combined accessibility element.
            VAButton(
                step == .done
                    ? String(localized: "Get Started", comment: "Onboarding final button to finish onboarding")
                    : String(localized: "Continue", comment: "Onboarding step-forward button"),
                style: .primary,
                accessibilityIdentifier: step == .done ? "onboarding.finish" : "onboarding.continue"
            ) {
                VAHaptics.tap()
                if step == .done {
                    onComplete(result)
                } else {
                    withAnimation(VAAnimation.standard) {
                        saveStep(Step(rawValue: step.rawValue + 1) ?? .done)
                    }
                }
            }
        }
    }

    private static func initialStep() -> Step {
        guard let rawValue = OnboardingProgressStore.loadStepRaw(),
              let savedStep = Step(rawValue: rawValue) else {
            return .welcome
        }
        return savedStep
    }

    private func saveStep(_ nextStep: Step) {
        step = nextStep
        OnboardingProgressStore.saveStepRaw(nextStep.rawValue)
    }

    fileprivate enum Step: Int, CaseIterable {
        case welcome = 0
        case profile = 1
        case preferences = 2
        case coachingStyle = 3
        // VOL-109: Apple Health connection step. The Continue button
        // advances to .done regardless of grant state — connection is
        // optional. The "Connect Apple Health" button on the step
        // triggers the HealthKit auth prompt via the dashboard model;
        // tests use `addUIInterruptionMonitor` to drive the system sheet.
        case permissions = 4
        case done = 5
    }
}

/// Result of completing the onboarding flow.
public struct OnboardingResult: Sendable {
    public var name: String
    public var advancementLevel: AdvancementLevel
    public var weeklyDays: Int
    public var sessionMinutes: Int
    public var coachingStyle: CoachingStyle
    public var privacyMode: PrivacyMode

    public init(
        name: String = "",
        advancementLevel: AdvancementLevel = .intermediate,
        weeklyDays: Int = 4,
        sessionMinutes: Int = 60,
        coachingStyle: CoachingStyle = .motivational,
        privacyMode: PrivacyMode = .standard
    ) {
        self.name = name
        self.advancementLevel = advancementLevel
        self.weeklyDays = weeklyDays
        self.sessionMinutes = sessionMinutes
        self.coachingStyle = coachingStyle
        self.privacyMode = privacyMode
    }

    /// Convert to a `UserProfileDefaults` for persistence.
    public func toDefaults() -> UserProfileDefaults {
        UserProfileDefaults(
            name: name,
            coachingStyle: coachingStyle,
            privacyMode: privacyMode,
            advancementLevel: advancementLevel,
            availableEquipment: [.barbell, .dumbbell, .machine, .bodyweight],
            preferredRepRangeLower: 5,
            preferredRepRangeUpper: 8,
            sessionTimeBudgetMinutes: sessionMinutes,
            weeklyTrainingDays: weeklyDays
        )
    }
}

public struct OnboardingAppleAccount: Sendable, Equatable {
    public let userID: String
    public let displayName: String
    public let email: String?

    public init(userID: String, displayName: String, email: String?) {
        self.userID = userID
        self.displayName = displayName
        self.email = email
    }
}

@_spi(Testing) public enum OnboardingSnapshotStep: Sendable {
    case welcome
    case profile
    case preferences
    case coachingStyle
    case permissions
    case done
}

private extension OnboardingView.Step {
    init(snapshotStep: OnboardingSnapshotStep) {
        switch snapshotStep {
        case .welcome:
            self = .welcome
        case .profile:
            self = .profile
        case .preferences:
            self = .preferences
        case .coachingStyle:
            self = .coachingStyle
        case .permissions:
            self = .permissions
        case .done:
            self = .done
        }
    }
}

private struct OnboardingProofRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: VA.Space.md) {
            Image(systemName: icon)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.primary)
                .frame(width: 32, height: 32)
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

/// Selected onboarding rows pick up the brand-tinted overlay; unselected rows
/// use real iOS 26 Liquid Glass via `vaGlassBackground`.
private struct OnboardingSelectionRowBackgroundModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .background(VA.Colors.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        } else {
            content
                .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        }
    }
}
#endif
