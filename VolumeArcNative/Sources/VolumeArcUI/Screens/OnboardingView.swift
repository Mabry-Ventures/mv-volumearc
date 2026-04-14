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
                Text("Welcome to VolumeArc")
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text("An AI coach that knows your training, adapts to your recovery, and helps you make the right call on every set.")
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
                Text("Tell me about you")
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text("I'll use this to personalize your training.")
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text("Your name")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
                TextField("First name", text: $result.name)
                    .textFieldStyle(.plain)
                    .font(VA.Typography.title2)
                    .padding(VA.Space.md)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
            }

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text("Experience level")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
                ForEach(AdvancementLevel.allCases, id: \.self) { level in
                    selectionRow(
                        title: level.rawValue.capitalized,
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
                Text("Training preferences")
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text("How often can you train?")
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text("Days per week")
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
                Text("Session time budget")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
                Picker("", selection: $result.sessionMinutes) {
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                    Text("75 min").tag(75)
                    Text("90 min").tag(90)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var coachingStyleStep: some View {
        VStack(alignment: .leading, spacing: VA.Space.xl) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text("Pick a coaching voice")
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text("You can change this anytime in settings.")
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
            }

            VStack(spacing: VA.Space.md) {
                ForEach(CoachingStyle.allCases, id: \.self) { style in
                    selectionRow(
                        title: style.rawValue.capitalized,
                        subtitle: styleDescription(style),
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
                Text("You're all set")
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(result.name.isEmpty ? "Let's" : "\(result.name), let's") build your first session.")
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
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
            .background(isSelected ? VA.Colors.primary.opacity(0.08) : .regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
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
        case .beginner: return "Less than 1 year of consistent lifting"
        case .intermediate: return "1-3 years, comfortable with the major lifts"
        case .advanced: return "3+ years, refined technique and periodization"
        }
    }

    private func styleDescription(_ style: CoachingStyle) -> String {
        switch style {
        case .motivational: return "High energy, keeps you pushing through"
        case .analytical: return "Data-driven, explains the why behind every call"
        case .minimal: return "Short and direct, only when it matters"
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: VA.Space.md) {
            if step != .welcome {
                VAButton("Back", style: .ghost) {
                    withAnimation(VAAnimation.standard) {
                        step = Step(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                .frame(maxWidth: 100)
            }

            VAButton(step == .done ? "Get Started" : "Continue", style: .primary) {
                VAHaptics.tap()
                if step == .done {
                    onComplete(result)
                    isPresented = false
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
#endif
