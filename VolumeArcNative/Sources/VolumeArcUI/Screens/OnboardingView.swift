#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// First-run onboarding experience.
/// 6 steps: welcome → profile → preferences → coaching style → permissions → done.
public struct OnboardingView: View {
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

    @State private var step: Step = .welcome
    @State private var result = OnboardingResult()
    /// VOL-109: tracked locally so the permissions step can show a
    /// "Connected" affordance after the prompt closes. Doesn't drive
    /// any business logic — Continue advances unconditionally — so a
    /// "false" value just means we don't change the button label.
    @State private var healthAuthorizationDidComplete = false

    public init(
        isPresented: Binding<Bool>,
        onComplete: @escaping (OnboardingResult) -> Void,
        onRequestHealthAuthorization: (() async -> Bool)? = nil
    ) {
        self._isPresented = isPresented
        self.onComplete = onComplete
        self.onRequestHealthAuthorization = onRequestHealthAuthorization
    }

    public var body: some View {
        VStack(spacing: 0) {
            // VOL-114: progressBar carries the `onboarding.root` identifier
            // instead of attaching it to the outer VStack. Previously the
            // outer identifier propagated to every descendant — so every
            // Button inside OnboardingView ended up with identifier
            // `onboarding.root` and the per-button identifiers
            // (onboarding.continue / onboarding.finish / onboarding.back)
            // were silently replaced. Putting it on the progress bar keeps
            // the smoke-test gate ("`onboarding.root` exists when the cover
            // is presented") working AND lets the action-row buttons keep
            // their journey-test identifiers.
            progressBar
                .accessibilityIdentifier("onboarding.root")
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
    }

    // MARK: - Progress bar

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
            Image(systemName: "figure.strengthtraining.traditional.circle.fill")
                .font(VA.Typography.onboardingIcon)
                .foregroundStyle(VA.Colors.primary)
                .vaAppear()

            VStack(spacing: VA.Space.md) {
                Text(String(localized: "Welcome to VolumeArc", comment: "Onboarding welcome step title"))
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(String(
                    localized: "An AI coach that knows your training, adapts to your recovery, and helps you make the right call on every set.",
                    comment: "Onboarding welcome step description"
                ))
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
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
                    .tracking(0.5)
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

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "Experience level", comment: "Onboarding profile step — experience level label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
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
                    .tracking(0.5)
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
                    .tracking(0.5)
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

            VStack(spacing: VA.Space.md) {
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
        }
    }

    /// VOL-109: Apple Health permission step. Optional connect — the
    /// Continue button advances to `.done` regardless of grant state.
    /// The "Connect Apple Health" button triggers the system prompt via
    /// `onRequestHealthAuthorization` (when wired by the host); after
    /// HealthKit only when the model reports a successful authorization
    /// request. Denial/failure leaves the button available so the user can
    /// retry or continue without connecting.
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

                Text(String(
                    localized: """
                    VolumeArc reads your past workouts and writes new sessions back. You stay in control — \
                    connect later from Profile if you'd rather decide now.
                    """,
                    comment: "Onboarding permissions step body explaining what HealthKit data is read/written and that the connection is optional"
                ))
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            }

            if onRequestHealthAuthorization != nil {
                VAButton(
                    healthAuthorizationDidComplete
                        ? String(
                            localized: "Connected",
                            comment: "Onboarding permissions step button label after the system prompt has been answered"
                        )
                        : String(
                            localized: "Connect Apple Health",
                            comment: "Onboarding permissions step primary action — opens the HealthKit authorization sheet"
                        ),
                    style: healthAuthorizationDidComplete ? .ghost : .secondary,
                    accessibilityIdentifier: "onboarding.permissions.connect-health"
                ) {
                    Task {
                        VAHaptics.tap()
                        let granted = await onRequestHealthAuthorization?() ?? false
                        healthAuthorizationDidComplete = granted
                    }
                }
                .frame(maxWidth: 320)
                .disabled(healthAuthorizationDidComplete)
            }

            Text(String(
                localized: "You can change this anytime in Profile → Apple Health.",
                comment: "Onboarding permissions step footer pointing the user to the Profile-tab settings entry for HealthKit"
            ))
            .font(VA.Typography.footnote)
            .foregroundStyle(VA.Colors.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
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
                    .frame(maxWidth: 320)
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
                        step = Step(rawValue: step.rawValue - 1) ?? .welcome
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
                        step = Step(rawValue: step.rawValue + 1) ?? .done
                    }
                }
            }
        }
    }

    private enum Step: Int, CaseIterable {
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

    public init(
        name: String = "",
        advancementLevel: AdvancementLevel = .intermediate,
        weeklyDays: Int = 4,
        sessionMinutes: Int = 60,
        coachingStyle: CoachingStyle = .motivational
    ) {
        self.name = name
        self.advancementLevel = advancementLevel
        self.weeklyDays = weeklyDays
        self.sessionMinutes = sessionMinutes
        self.coachingStyle = coachingStyle
    }

    /// Convert to a `UserProfileDefaults` for persistence.
    public func toDefaults() -> UserProfileDefaults {
        UserProfileDefaults(
            name: name,
            coachingStyle: coachingStyle,
            privacyMode: .standard,
            advancementLevel: advancementLevel,
            availableEquipment: [.barbell, .dumbbell, .machine, .bodyweight],
            preferredRepRangeLower: 5,
            preferredRepRangeUpper: 8,
            sessionTimeBudgetMinutes: sessionMinutes,
            weeklyTrainingDays: weeklyDays
        )
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
