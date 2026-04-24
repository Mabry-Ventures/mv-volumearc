#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// First-run onboarding experience.
/// 5 steps: welcome → profile → preferences → coaching style → permissions → done.
public struct OnboardingView: View {
    @Binding var isPresented: Bool
    let onComplete: (OnboardingResult) -> Void

    @State private var step: Step = .welcome
    @State private var result = OnboardingResult()

    public init(isPresented: Binding<Bool>, onComplete: @escaping (OnboardingResult) -> Void) {
        self._isPresented = isPresented
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            progressBar
            Spacer()
            stepContent
                .padding(VA.Space.xl)
            Spacer()
            actionRow
                .padding(VA.Space.lg)
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
        .accessibilityIdentifier("onboarding.root")
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
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: VA.Space.xl) {
            Image(systemName: "figure.strengthtraining.traditional.circle.fill")
                .font(.system(size: 88, weight: .semibold))
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

    private var doneStep: some View {
        VStack(spacing: VA.Space.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 88, weight: .semibold))
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
        case done = 4
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
