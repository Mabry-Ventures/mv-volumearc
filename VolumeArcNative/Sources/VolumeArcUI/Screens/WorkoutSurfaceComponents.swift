#if canImport(SwiftUI)
import SwiftUI

struct WorkoutIdleLibrary: View {
    let featuredTitle: String
    let featuredFocus: String
    let startWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xl) {
            featuredWorkoutCard
            thisWeekSection
            templatesSection
        }
    }

    private var featuredWorkoutCard: some View {
        Button(action: startWorkout) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [VA.Colors.sunriseA, VA.Colors.sunriseB, VA.Colors.sunriseC],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(VA.Typography.onboardingIcon)
                    .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.26))
                    .offset(x: 18, y: -18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VA.Space.sm) {
                    Text(String(localized: "SCHEDULED · TODAY", comment: "Featured workout scheduled label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.84))
                        .tracking(0.6)
                    Text(featuredTitle)
                        .font(VA.Typography.title)
                        .foregroundStyle(VA.Colors.textOnPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(featuredFocus)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.86))
                        .lineLimit(2)
                    featuredMeta
                    featuredStartPill
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VA.Space.xl)
            }
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous))
            .vaShadow(.lg)
        }
        .buttonStyle(.plain)
    }

    private var featuredMeta: some View {
        HStack(spacing: VA.Space.sm) {
            Text(String(localized: "45 min", comment: "Featured workout duration"))
            Text("·").foregroundStyle(VA.Colors.textOnPrimary.opacity(0.58))
            Text(String(localized: "5 exercises", comment: "Featured workout exercise count"))
        }
        .font(VA.Typography.footnote)
        .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.9))
    }

    private var featuredStartPill: some View {
        HStack(spacing: VA.Space.sm) {
            Image(systemName: "arrow.right")
                .font(VA.Typography.caption)
            Text(String(localized: "Start workout", comment: "Featured workout start label"))
                .font(VA.Typography.button)
        }
        .foregroundStyle(VA.Colors.primaryDeep)
        .padding(.horizontal, VA.Space.lg)
        .padding(.vertical, VA.Space.md)
        .background(VA.Colors.textOnPrimary.opacity(0.96), in: Capsule())
        .padding(.top, VA.Space.xs)
    }

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader(
                String(localized: "This week", comment: "Workouts this week section"),
                action: (
                    label: String(localized: "Edit plan", comment: "Workouts edit plan action"),
                    handler: { VAHaptics.tap() }
                )
            )
            VStack(spacing: VA.Space.md) {
                workoutPlanRow(
                    title: String(localized: "Pull A", comment: "Workout library row title"),
                    focus: String(localized: "Back · Biceps", comment: "Workout library row focus"),
                    schedule: String(localized: "Sat", comment: "Workout library row schedule"),
                    icon: "figure.pull",
                    duration: 50,
                    exercises: 6
                )
                workoutPlanRow(
                    title: String(localized: "Legs", comment: "Workout library row title"),
                    focus: String(localized: "Quads · Hams · Glutes", comment: "Workout library row focus"),
                    schedule: String(localized: "Mon", comment: "Workout library row schedule"),
                    icon: "figure.strengthtraining.traditional",
                    duration: 55,
                    exercises: 5
                )
                workoutPlanRow(
                    title: String(localized: "Mobility", comment: "Workout library row title"),
                    focus: String(localized: "Hips · T-spine", comment: "Workout library row focus"),
                    schedule: String(localized: "Wed", comment: "Workout library row schedule"),
                    icon: "figure.cooldown",
                    duration: 20,
                    exercises: 8
                )
            }
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            Text(String(localized: "Templates", comment: "Workout templates section title"))
                .font(VA.Typography.title2)
                .foregroundStyle(VA.Colors.textPrimary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VA.Space.md) {
                    templateCard(title: String(localized: "Quick HIIT", comment: "Workout template title"),
                                 duration: 18,
                                 icon: "figure.run")
                    templateCard(title: String(localized: "Cooldown", comment: "Workout template title"),
                                 duration: 8,
                                 icon: "lungs.fill")
                }
                VStack(spacing: VA.Space.md) {
                    templateCard(title: String(localized: "Quick HIIT", comment: "Workout template title"),
                                 duration: 18,
                                 icon: "figure.run")
                    templateCard(title: String(localized: "Cooldown", comment: "Workout template title"),
                                 duration: 8,
                                 icon: "lungs.fill")
                }
            }
        }
    }

    private func workoutPlanRow(
        title: String,
        focus: String,
        schedule: String,
        icon: String,
        duration: Int,
        exercises: Int
    ) -> some View {
        Button(action: startWorkout) {
            VACard(style: .flat) {
                HStack(alignment: .center, spacing: VA.Space.md) {
                    WorkoutIllustrationTile(systemImage: icon, size: 64, accent: VA.Colors.primary)
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        HStack(spacing: VA.Space.xs) {
                            Text(title)
                                .font(VA.Typography.headline)
                                .foregroundStyle(VA.Colors.textPrimary)
                            WorkoutChip(text: schedule, tone: .neutral)
                        }
                        Text(focus)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                        Text(String(
                            localized: "\(duration) min · \(exercises) exercises",
                            comment: "Workout library row duration and exercise count"
                        ))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func templateCard(title: String, duration: Int, icon: String) -> some View {
        Button(action: startWorkout) {
            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.sm) {
                    WorkoutIllustrationTile(systemImage: icon, size: 72, accent: VA.Colors.primary)
                    Text(title)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(String(localized: "\(duration) min", comment: "Workout template duration"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct WorkoutChip: View {
    enum Tone {
        case neutral
        case primary
        case success
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(VA.Typography.caption)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, VA.Space.sm)
            .padding(.vertical, VA.Space.xs)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return VA.Colors.textSecondary
        case .primary: return VA.Colors.primary
        case .success: return VA.Colors.success
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return VA.Colors.textTertiary.opacity(0.12)
        case .primary: return VA.Colors.primary.opacity(0.14)
        case .success: return VA.Colors.success.opacity(0.14)
        }
    }
}

struct WorkoutIllustrationTile: View {
    let systemImage: String
    let size: CGFloat
    let accent: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(size >= 80 ? VA.Typography.title : VA.Typography.headline)
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(VA.Colors.textTertiary.opacity(0.10), in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SetLogRow: View {
    let setNumber: Int
    let isDone: Bool
    let target: String
    let rpe: Double

    var body: some View {
        HStack(spacing: VA.Space.md) {
            completionGlyph
            Text(String(localized: "Set \(setNumber)", comment: "Active workout set log row label"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(target)
                .font(VA.Typography.monoDigit)
                .foregroundStyle(isDone ? VA.Colors.textPrimary : VA.Colors.textTertiary)
                .monospacedDigit()
            Spacer()
            Text(isDone ? String(format: "%.1f", rpe) : "—")
                .font(VA.Typography.monoDigit)
                .foregroundStyle(isDone ? VA.Colors.textPrimary : VA.Colors.textTertiary)
                .monospacedDigit()
        }
        .padding(.vertical, VA.Space.sm)
        .accessibilityElement(children: .combine)
    }

    private var completionGlyph: some View {
        ZStack {
            Circle()
                .fill(isDone ? VA.Colors.success : VA.Colors.textTertiary.opacity(0.14))
            if isDone {
                Image(systemName: "checkmark")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textOnPrimary)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// Dedicated subview for the rest timer so only this view re-renders each second,
/// not the whole WorkoutsView.
struct RestTimerDisplay: View {
    let endsAt: Date
    let active: Bool
    let onComplete: () -> Void

    @State private var lastFired: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endsAt.timeIntervalSince(context.date)))
            let total: TimeInterval = 90
            let elapsed = total - endsAt.timeIntervalSince(context.date)
            let progress = max(0, min(1, elapsed / total))

            restRing(remaining: remaining, progress: progress)
                .accessibilityElement()
                .accessibilityLabel("Rest timer")
                .accessibilityValue(remaining == 0 ? "Go time" : "\(remaining) seconds remaining")
                .onChange(of: remaining) { _, newValue in
                    if active && newValue == 0 && !lastFired {
                        lastFired = true
                        onComplete()
                    }
                    if newValue > 0 { lastFired = false }
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 212)
    }

    private func restRing(remaining: Int, progress: Double) -> some View {
        ZStack {
            VAProgressRing(
                progress: progress,
                lineWidth: 10,
                color: remaining == 0 ? VA.Colors.success : VA.Colors.primary
            )
            .frame(width: 190, height: 190)
            VStack(spacing: VA.Space.xs) {
                Text(restDisplay(remaining))
                    .font(VA.Typography.timerDisplay)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                Text(remaining == 0 ? "GO" : "seconds")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(1)
            }
        }
    }

    private func restDisplay(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
#endif
